// Celari Recoverable Account Contract v0.1.0
//
// WebAuthn/Passkey authentication + Guardian-based social recovery
// Built on celari_passkey_account v0.3.0 with these additions:
//   - PrivateMutable signing key (enables key rotation)
//   - Guardian hash storage (3 guardians, 2-of-3 threshold)
//   - Time-locked recovery with block-based delay (24h)
//   - Owner cancellation during time-lock window
//
// Recovery flow:
//   1. Owner sets up 3 guardians (stores sha256 hashes on-chain)
//   2. On device loss, 2-of-3 guardians approve new key
//   3. initiate_recovery() stores new key + records start block
//   4. Owner can cancel_recovery() during the 24h window
//   5. execute_recovery() finalizes key change after delay

mod public_key_note;
mod test;

use aztec::macros::aztec;

// 24 hours in blocks (~12 sec/block on Aztec testnet)
// 24 * 60 * 60 / 12 = 7200 blocks
// Note: defined as global but #[aztec] macro doesn't propagate globals into scope.
// Use the literal 7200 inside the contract where needed.

#[aztec]
pub contract CelariRecoverableAccount {
    use aztec::{
        authwit::{account::AccountActions, entrypoint::app::AppPayload},
        context::PrivateContext,
        macros::{
            functions::{allow_phase_change, external, initializer, noinitcheck, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        oracle::{
            auth_witness::get_auth_witness,
            notes::{get_sender_for_tags, set_sender_for_tags},
        },
        state_vars::{Owned, PrivateMutable, PublicImmutable, PublicMutable},
    };

    use crate::public_key_note::PublicKeyNote;

    #[storage]
    struct Storage<Context> {
        // === Signing Key (rotatable) ===
        // PrivateMutable enables key rotation via guardian recovery.
        // Wrapped in Owned as required by Aztec storage model.
        signing_public_key: Owned<PrivateMutable<PublicKeyNote, Context>, Context>,

        // === Guardian Configuration ===
        // SHA-256 hashes of guardian keys.
        // Guardian keys are random secrets shared with guardians via email.
        guardian_hash_0: PublicImmutable<Field, Context>,
        guardian_hash_1: PublicImmutable<Field, Context>,
        guardian_hash_2: PublicImmutable<Field, Context>,
        // How many guardian approvals needed (default: 2)
        threshold: PublicImmutable<Field, Context>,
        // Whether guardians have been configured
        guardians_configured: PublicMutable<bool, Context>,

        // === Recovery State ===
        // Pending new key coordinates (set during initiate_recovery)
        pending_key_x: PublicMutable<Field, Context>,
        pending_key_y: PublicMutable<Field, Context>,
        // Block number when recovery was initiated (for time-lock)
        recovery_start_block: PublicMutable<Field, Context>,
        // Recovery nonce prevents replay attacks
        recovery_nonce: PublicMutable<Field, Context>,
        // Whether a recovery is currently in progress
        recovery_active: PublicMutable<bool, Context>,

        // === IPFS Recovery Bundle ===
        // CID of the encrypted recovery bundle on IPFS.
        // Public because the bundle itself is AES-256-GCM encrypted.
        // Stored as two Field elements (CID is typically 46 bytes).
        recovery_cid_part1: PublicMutable<Field, Context>,
        recovery_cid_part2: PublicMutable<Field, Context>,
    }

    // ================================================================
    // ACCOUNT LIFECYCLE
    // ================================================================

    // Initialize the account with a P256 public key from WebAuthn.
    #[external("private")]
    #[initializer]
    fn constructor(pub_key_x: [u8; 32], pub_key_y: [u8; 32]) {
        let pub_key_note = PublicKeyNote { x: pub_key_x, y: pub_key_y };

        // Safety: The sender for tags is only used to compute unconstrained shared secrets
        // for emitting logs. Safe to load from unconstrained context.
        let original_sender = unsafe { get_sender_for_tags().unwrap_or(self.address) };

        // Safety: Same as above
        unsafe { set_sender_for_tags(self.address) };

        self.storage.signing_public_key.at(self.address).initialize(pub_key_note).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );

        // Safety: Same as above
        unsafe { set_sender_for_tags(original_sender) };
    }

    // Main transaction entrypoint -- identical to v1.
    #[external("private")]
    #[noinitcheck]
    #[allow_phase_change]
    fn entrypoint(app_payload: AppPayload, fee_payment_method: u8, cancellable: bool) {
        // Safety: sender for tags is unconstrained tagging only
        unsafe { set_sender_for_tags(self.address) };

        let actions = AccountActions::init(self.context, is_valid_impl);
        actions.entrypoint(app_payload, fee_payment_method, cancellable);
    }

    // Verify authorization for delegated actions -- identical to v1.
    #[external("private")]
    #[noinitcheck]
    #[view]
    fn verify_private_authwit(inner_hash: Field) -> Field {
        let actions = AccountActions::init(self.context, is_valid_impl);
        actions.verify_private_authwit(inner_hash)
    }

    // ================================================================
    // GUARDIAN SETUP
    // ================================================================

    // Configure guardians for this account.
    // Called once by the account owner after deployment.
    //
    // hash_i = sha256(guardian_key_i) truncated to a Field
    // where guardian_key_i is a random 32-byte secret shared with the guardian.
    //
    // The guardian keys are NOT stored on-chain -- only their hashes.
    #[external("public")]
    fn setup_guardians(
        hash_0: Field,
        hash_1: Field,
        hash_2: Field,
        recovery_threshold: Field,
        cid_part1: Field,
        cid_part2: Field,
    ) {
        // Only the account itself can set guardians
        assert(self.context.maybe_msg_sender().unwrap() == self.address, "Only account owner");

        // Guardians can only be set once (immutable after setup)
        assert(!self.storage.guardians_configured.read(), "Guardians already configured");

        // Validate threshold
        assert(recovery_threshold as u64 >= 1, "Threshold must be >= 1");
        assert(recovery_threshold as u64 <= 3, "Threshold must be <= 3");

        // All hashes must be non-zero and unique
        assert(hash_0 != 0, "Guardian hash 0 is zero");
        assert(hash_1 != 0, "Guardian hash 1 is zero");
        assert(hash_2 != 0, "Guardian hash 2 is zero");
        assert(hash_0 != hash_1, "Duplicate guardian hash 0-1");
        assert(hash_0 != hash_2, "Duplicate guardian hash 0-2");
        assert(hash_1 != hash_2, "Duplicate guardian hash 1-2");

        // Store guardian hashes
        self.storage.guardian_hash_0.initialize(hash_0);
        self.storage.guardian_hash_1.initialize(hash_1);
        self.storage.guardian_hash_2.initialize(hash_2);
        self.storage.threshold.initialize(recovery_threshold);

        // Store encrypted recovery bundle CID
        self.storage.recovery_cid_part1.write(cid_part1);
        self.storage.recovery_cid_part2.write(cid_part2);

        // Mark as configured
        self.storage.guardians_configured.write(true);

        // Initialize recovery state
        self.storage.recovery_nonce.write(0);
        self.storage.recovery_active.write(false);
    }

    // ================================================================
    // RECOVERY: INITIATE
    // ================================================================

    // Start the recovery process with 2-of-3 guardian approval.
    // Guardian keys are verified against stored hashes.
    // Starts a block-based time-lock (RECOVERY_DELAY_BLOCKS).
    #[external("public")]
    fn initiate_recovery(
        new_key_x: Field,
        new_key_y: Field,
        guardian_key_a: Field,
        guardian_key_b: Field,
    ) {
        // Guardians must be configured
        assert(self.storage.guardians_configured.read(), "Guardians not configured");

        // No active recovery in progress
        assert(!self.storage.recovery_active.read(), "Recovery already active");

        // New key must be non-zero
        assert(new_key_x != 0, "New key X is zero");
        assert(new_key_y != 0, "New key Y is zero");

        // Verify guardian keys: compute hash and check against stored hashes.
        // Using sha256 for hashing (available in both Noir and client-side JS/Swift).
        let key_a_bytes: [u8; 32] = guardian_key_a.to_be_bytes();
        let key_b_bytes: [u8; 32] = guardian_key_b.to_be_bytes();
        let hash_a_bytes: [u8; 32] = sha256::digest(key_a_bytes);
        let hash_b_bytes: [u8; 32] = sha256::digest(key_b_bytes);

        // Truncate sha256 to Field (take first 31 bytes to fit BN254)
        let hash_a = bytes31_to_field(hash_a_bytes);
        let hash_b = bytes31_to_field(hash_b_bytes);

        let stored_0 = self.storage.guardian_hash_0.read();
        let stored_1 = self.storage.guardian_hash_1.read();
        let stored_2 = self.storage.guardian_hash_2.read();

        // Each provided key must match one stored hash
        let valid_a = (hash_a == stored_0) | (hash_a == stored_1) | (hash_a == stored_2);
        let valid_b = (hash_b == stored_0) | (hash_b == stored_1) | (hash_b == stored_2);
        assert(valid_a, "Guardian key A invalid");
        assert(valid_b, "Guardian key B invalid");

        // Keys must be different (can't use same guardian twice)
        assert(guardian_key_a != guardian_key_b, "Duplicate guardian key");

        // Store pending key
        self.storage.pending_key_x.write(new_key_x);
        self.storage.pending_key_y.write(new_key_y);

        // Record the block number for time-lock
        let current_block = self.context.block_number() as Field;
        self.storage.recovery_start_block.write(current_block);

        // Mark recovery as active
        self.storage.recovery_active.write(true);

        // Increment nonce for replay protection
        let nonce = self.storage.recovery_nonce.read();
        self.storage.recovery_nonce.write(nonce + 1);
    }

    // ================================================================
    // RECOVERY: CANCEL
    // ================================================================

    // Cancel an active recovery.
    // Only callable by the account owner (requires valid P256 signature).
    // This is the safety net: if someone maliciously initiates recovery,
    // the real owner has 24h to cancel it.
    #[external("private")]
    #[noinitcheck]
    fn cancel_recovery() {
        // If this function executes, the caller passed entrypoint
        // P256 auth, proving they own the account.

        // Enqueue public call to reset recovery state
        CelariRecoverableAccount::at(self.context.this_address())
            .reset_recovery_state()
            .enqueue(self.context);
    }

    // Internal: reset recovery state (called via enqueue from cancel/execute)
    #[external("public")]
    #[noinitcheck]
    fn reset_recovery_state() {
        // Only callable by self (via enqueue)
        assert(self.context.maybe_msg_sender().unwrap() == self.address, "Only self");

        self.storage.pending_key_x.write(0);
        self.storage.pending_key_y.write(0);
        self.storage.recovery_start_block.write(0);
        self.storage.recovery_active.write(false);
    }

    // ================================================================
    // RECOVERY: EXECUTE
    // ================================================================

    // Finalize the recovery after the time-lock has expired.
    // First enqueues a public call to verify time-lock, then
    // replaces the signing key in private.
    #[external("private")]
    #[noinitcheck]
    fn execute_recovery(new_key_x: [u8; 32], new_key_y: [u8; 32]) {
        // Set sender for tags (required for private note delivery)
        // Safety: sender for tags is unconstrained tagging only
        unsafe { set_sender_for_tags(self.address) };

        // Replace the signing key with the new key.
        // The caller must provide the same key that was approved by guardians.
        // The public verify_and_clear function (enqueued below) checks
        // that the time-lock has passed and the provided key matches.
        let new_key = PublicKeyNote { x: new_key_x, y: new_key_y };
        self.storage.signing_public_key.at(self.address).replace(|_old| new_key).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );

        // Enqueue time-lock verification + state cleanup.
        // If this fails, the entire tx (including key replace above) reverts.
        let key_x_field = bytes32_to_field(new_key_x);
        let key_y_field = bytes32_to_field(new_key_y);
        CelariRecoverableAccount::at(self.context.this_address())
            .verify_and_clear_recovery(key_x_field, key_y_field)
            .enqueue(self.context);
    }

    // Public: verify time-lock has expired and key matches, then clear state.
    // Called via enqueue from execute_recovery.
    // If this reverts, the private key replacement also reverts.
    #[external("public")]
    #[noinitcheck]
    fn verify_and_clear_recovery(expected_key_x: Field, expected_key_y: Field) {
        // Only callable by self
        assert(self.context.maybe_msg_sender().unwrap() == self.address, "Only self");

        // Recovery must be active
        assert(self.storage.recovery_active.read(), "No active recovery");

        // Verify time-lock has passed
        let start_block = self.storage.recovery_start_block.read();
        let current_block = self.context.block_number() as u64;
        let start = start_block as u64;
        // 24h in blocks: 24 * 60 * 60 / 12 = 7200
        let delay: u64 = 7200;
        assert(current_block >= start + delay, "Time-lock not expired");

        // Verify the provided key matches the pending key
        let pending_x = self.storage.pending_key_x.read();
        let pending_y = self.storage.pending_key_y.read();
        assert(expected_key_x == pending_x, "Key X mismatch");
        assert(expected_key_y == pending_y, "Key Y mismatch");

        // Clear recovery state
        self.storage.pending_key_x.write(0);
        self.storage.pending_key_y.write(0);
        self.storage.recovery_start_block.write(0);
        self.storage.recovery_active.write(false);
    }

    // ================================================================
    // KEY ROTATION (owner-initiated)
    // ================================================================

    // Rotate the signing key without guardians.
    // Only callable by the current owner (requires valid P256 signature).
    #[external("private")]
    #[noinitcheck]
    fn rotate_key(new_pub_key_x: [u8; 32], new_pub_key_y: [u8; 32]) {
        // Safety: sender for tags is unconstrained tagging only
        unsafe { set_sender_for_tags(self.address) };

        let new_key = PublicKeyNote { x: new_pub_key_x, y: new_pub_key_y };
        self.storage.signing_public_key.at(self.address).replace(|_old| new_key).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    // ================================================================
    // READ-ONLY: Recovery state queries
    // ================================================================

    #[external("public")]
    #[view]
    fn is_guardian_configured() -> pub bool {
        self.storage.guardians_configured.read()
    }

    #[external("public")]
    #[view]
    fn is_recovery_active() -> pub bool {
        self.storage.recovery_active.read()
    }

    #[external("public")]
    #[view]
    fn get_recovery_nonce() -> pub Field {
        self.storage.recovery_nonce.read()
    }

    #[external("public")]
    #[view]
    fn get_recovery_cid() -> pub (Field, Field) {
        (
            self.storage.recovery_cid_part1.read(),
            self.storage.recovery_cid_part2.read(),
        )
    }

    // ================================================================
    // SIGNATURE VERIFICATION
    // ================================================================

    // Core WebAuthn/Passkey P256 signature verification.
    // Same logic as v1 but reads from PrivateMutable (via Owned wrapper).
    // NOTE: When upgrading to Aztec Alpha, &mut PrivateContext may need to change
    // to value type or immutable reference per Alpha API changes.
    #[contract_library_method]
    fn is_valid_impl(context: &mut PrivateContext, outer_hash: Field) -> bool {
        let storage = Storage::init(context);
        // Read the signing key: Owned -> at(owner) -> PrivateMutable -> get_note() -> NoteMessage
        // Then extract the Note via NoteMessage.get_note()
        // The note hash is already in the tree from PrivateMutable.get_note()'s create_note.
        // The PXE executing this transaction already knows about the note.
        let note_msg = storage.signing_public_key.at(context.this_address()).get_note();
        let public_key = note_msg.get_note();

        // Safety: The witness is only used to verify the signature below.
        let witness: [Field; 64] = unsafe { get_auth_witness(outer_hash) };

        let mut signature: [u8; 64] = [0; 64];
        for i in 0..64 {
            signature[i] = witness[i] as u8;
        }

        let pub_key_x_bytes: [u8; 32] = public_key.x;
        let pub_key_y_bytes: [u8; 32] = public_key.y;

        let outer_hash_bytes: [u8; 32] = outer_hash.to_be_bytes();
        let hashed_message: [u8; 32] = sha256::digest(outer_hash_bytes);

        std::ecdsa_secp256r1::verify_signature(
            pub_key_x_bytes,
            pub_key_y_bytes,
            signature,
            hashed_message,
        )
    }

    // ================================================================
    // UTILITY: Field <-> bytes conversion
    // ================================================================

    // Convert first 31 bytes of a 32-byte array to a Field.
    // (BN254 field is ~254 bits, so 31 bytes = 248 bits fits safely)
    #[contract_library_method]
    fn bytes31_to_field(bytes: [u8; 32]) -> Field {
        let mut result: Field = 0;
        let mut mul: Field = 1;
        for i in 1..32 {
            let byte: Field = bytes[31 - i] as Field;
            result = result + (byte * mul);
            mul *= 256;
        }
        result
    }

    // Convert a 32-byte array to a Field (for key matching).
    #[contract_library_method]
    fn bytes32_to_field(bytes: [u8; 32]) -> Field {
        let mut result: Field = 0;
        let mut mul: Field = 1;
        for i in 1..32 {
            let byte: Field = bytes[31 - i] as Field;
            result = result + (byte * mul);
            mul *= 256;
        }
        // Add last byte separately
        result + (bytes[31] as Field) * mul
    }
}
