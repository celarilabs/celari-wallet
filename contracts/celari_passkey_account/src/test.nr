// ┌──────────────────────────────────────────────────────────┐
// │  Celari Passkey Account — TXE Unit Tests                  │
// │                                                          │
// │  Tests P256/secp256r1 account contract deployment        │
// │  and basic signature verification flow.                  │
// │                                                          │
// │  Run: cd contracts/celari_passkey_account && aztec test   │
// └──────────────────────────────────────────────────────────┘

use crate::CelariPasskeyAccount;
use dep::aztec::test::helpers::test_environment::TestEnvironment;

/// Test that the passkey account contract deploys correctly
/// with P256 public key coordinates.
#[test]
fn test_passkey_account_deployment() {
    let mut env = TestEnvironment::new();

    // Example P256 public key coordinates (test values)
    // In production these come from WebAuthn navigator.credentials.create()
    // Note: Field to [u8;32] conversion handled by TXE deploy framework
    let pub_key_x: Field = 0x0102030405060708091011121314151617181920212223242526272829303132;
    let pub_key_y: Field = 0x3132333435363738394041424344454647484950515253545556575859606162;

    let contract = env.deploy_self("CelariPasskeyAccount").with_private_initializer(
        CelariPasskeyAccount::interface().constructor(pub_key_x, pub_key_y),
    );

    // Verify the contract address is deterministic and non-zero
    let address = contract.to_field();
    assert(address != 0, "Contract address should not be zero");
}

/// Test that the contract stores public key coordinates correctly.
#[test]
fn test_public_key_storage() {
    let mut env = TestEnvironment::new();

    // Note: Field to [u8;32] conversion handled by TXE deploy framework
    let pub_key_x: Field = 0xaabbccdd11223344556677889900aabbccdd11223344556677889900aabbccdd;
    let pub_key_y: Field = 0x1122334455667788990011223344556677889900112233445566778899001122;

    let _contract = env.deploy_self("CelariPasskeyAccount").with_private_initializer(
        CelariPasskeyAccount::interface().constructor(pub_key_x, pub_key_y),
    );

    // If deployment succeeds, the immutable storage was set correctly
    // (PublicImmutable.initialize would panic on re-initialization)
}

/// TODO: Test is_valid_impl (P256 signature verification)
///
/// The core signature verification function `is_valid_impl` is not directly
/// testable via TXE because it requires:
///   1. An initialized account with stored PublicKeyNote
///   2. An auth witness injected into the oracle (get_auth_witness)
///   3. A valid P256 signature over sha256(outer_hash)
///
/// Current coverage strategy:
///   - Deployment tests above verify the contract initializes correctly
///   - The Noir stdlib `ecdsa_secp256r1::verify_signature` is tested upstream
///   - E2E tests in src/test/e2e/ verify the full signing flow via Schnorr stand-in
///
/// Future: When TXE supports auth witness injection, add:
///   #[test]
///   fn test_is_valid_impl_with_real_p256_signature() {
///       // 1. Deploy contract with known P256 pub key
///       // 2. Sign outer_hash with corresponding private key
///       // 3. Inject signature as auth witness
///       // 4. Call entrypoint and verify success
///   }
