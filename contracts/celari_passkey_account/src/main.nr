// Celari Passkey Account Contract v0.3.0
// WebAuthn/Passkey authentication for Aztec Network
// - secp256r1 (P256) signature verification
// - WebAuthn challenge-response compatible
// - Biometric auth (Face ID / Touch ID / Windows Hello)
// - Synced passkeys (iCloud Keychain, Google Password Mgr)
// - No seed phrases ever

mod public_key_note;

use aztec::macros::aztec;

#[aztec]
pub contract CelariPasskeyAccount {
    use aztec::{
        authwit::{account::AccountActions, entrypoint::app::AppPayload},
        context::PrivateContext,
        macros::{
            functions::{external, initializer, noinitcheck, nophasecheck, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        oracle::{
            auth_witness::get_auth_witness,
            notes::{get_sender_for_tags, set_sender_for_tags},
        },
        state_vars::SinglePrivateImmutable,
    };

    use crate::public_key_note::PublicKeyNote;

    #[storage]
    struct Storage<Context> {
        signing_public_key: SinglePrivateImmutable<PublicKeyNote, Context>,
    }

    // Initialize the Celari Passkey account.
    // The P256 public key coordinates come from WebAuthn
    // credential creation (navigator.credentials.create).
    #[external("private")]
    #[initializer]
    fn constructor(pub_key_x: [u8; 32], pub_key_y: [u8; 32]) {
        let pub_key_note = PublicKeyNote { x: pub_key_x, y: pub_key_y };

        // Safety: The sender for tags is only used to compute unconstrained shared secrets
        // for emitting logs. Safe to load from unconstrained context.
        let original_sender = unsafe { get_sender_for_tags().unwrap_or(self.address) };

        // Set sender to self so the note can be found without registering the deployer
        // Safety: Same as above
        unsafe { set_sender_for_tags(self.address) };

        self.storage.signing_public_key.initialize(pub_key_note).deliver(
            MessageDelivery.CONSTRAINED_ONCHAIN,
        );

        // Safety: Same as above
        unsafe { set_sender_for_tags(original_sender) };
    }

    // Main transaction entrypoint.
    // Flow:
    // 1. Browser extension triggers WebAuthn assertion
    // 2. Device shows biometric prompt (Face ID / fingerprint)
    // 3. P256 signature generated in secure enclave
    // 4. Signature passed as auth witness
    // 5. This contract verifies via ecdsa_secp256r1
    // 6. Transaction executes privately
    #[external("private")]
    #[noinitcheck]
    #[nophasecheck]
    fn entrypoint(app_payload: AppPayload, fee_payment_method: u8, cancellable: bool) {
        // Safety: sender for tags is unconstrained tagging only
        unsafe { set_sender_for_tags(self.address) };

        let actions = AccountActions::init(self.context, is_valid_impl);
        actions.entrypoint(app_payload, fee_payment_method, cancellable);
    }

    // Verify authorization for delegated actions (e.g. token approvals).
    #[external("private")]
    #[noinitcheck]
    #[view]
    fn verify_private_authwit(inner_hash: Field) -> Field {
        let actions = AccountActions::init(self.context, is_valid_impl);
        actions.verify_private_authwit(inner_hash)
    }

    // Core WebAuthn/Passkey P256 signature verification.
    //
    // Auth witness layout: 64 Field elements -> 64 bytes of ECDSA-P256 signature (r || s)
    //
    // Why P256 instead of secp256k1?
    // - Passkeys/WebAuthn ONLY support P256 (secp256r1)
    // - Hardware secure enclaves (Apple/Android) use P256
    // - No seed phrases needed - keys never leave the device
    // - Cross-device sync via iCloud/Google
    #[contract_library_method]
    fn is_valid_impl(context: &mut PrivateContext, outer_hash: Field) -> bool {
        // Load P256 public key from private storage
        let storage = Storage::init(context);
        let public_key = storage.signing_public_key.get_note();

        // Get auth witness containing P256 signature (64 bytes)
        // Safety: The witness is only used to verify the signature below.
        let witness: [Field; 64] = unsafe { get_auth_witness(outer_hash) };

        // Extract P256 signature (r || s, 64 bytes)
        let mut signature: [u8; 64] = [0; 64];
        for i in 0..64 {
            signature[i] = witness[i] as u8;
        }

        // Public key coordinates are already stored as byte arrays
        let pub_key_x_bytes: [u8; 32] = public_key.x;
        let pub_key_y_bytes: [u8; 32] = public_key.y;

        // SHA-256 hash the outer_hash before ECDSA verification
        // (Aztec convention for ECDSA account contracts)
        let outer_hash_bytes: [u8; 32] = outer_hash.to_be_bytes();
        let hashed_message: [u8; 32] = sha256::digest(outer_hash_bytes);

        // ECDSA secp256r1 (P256) verification
        // Noir's native P256 support - the key enabler for WebAuthn/Passkey on Aztec
        std::ecdsa_secp256r1::verify_signature(
            pub_key_x_bytes,
            pub_key_y_bytes,
            signature,
            hashed_message,
        )
    }
}
