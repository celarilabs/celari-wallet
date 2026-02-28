// Celari Recoverable Account -- Unit Tests
//
// Run: cd contracts/celari_recoverable_account && nargo test

/// Test SHA-256 guardian hash computation.
/// Verifies that the hashing logic used for guardian keys works correctly.
#[test]
fn test_guardian_hash_computation() {
    // Simulate a guardian key as 32 bytes
    let guardian_key: Field = 0xdeadbeef12345678;
    let key_bytes: [u8; 32] = guardian_key.to_be_bytes();

    // Compute SHA-256 hash (same as contract's initiate_recovery)
    let hash_bytes: [u8; 32] = sha256::digest(key_bytes);

    // Truncate to 31 bytes for Field (same as contract's bytes31_to_field)
    let hash_field = bytes31_to_field(hash_bytes);

    // Hash should be non-zero
    assert(hash_field != 0, "Guardian hash should not be zero");

    // Same input should produce same hash (deterministic)
    let hash_bytes_2: [u8; 32] = sha256::digest(key_bytes);
    let hash_field_2 = bytes31_to_field(hash_bytes_2);
    assert(hash_field == hash_field_2, "Guardian hash should be deterministic");

    // Different input should produce different hash
    let different_key: Field = 0xdeadbeef12345679;
    let different_key_bytes: [u8; 32] = different_key.to_be_bytes();
    let different_hash_bytes: [u8; 32] = sha256::digest(different_key_bytes);
    let different_hash = bytes31_to_field(different_hash_bytes);
    assert(hash_field != different_hash, "Different keys should produce different hashes");
}

/// Test bytes31_to_field conversion.
/// BN254 field fits 31 bytes (248 bits), so we skip the last byte.
#[test]
fn test_bytes31_to_field() {
    // All zeros should give zero
    let zeros: [u8; 32] = [0; 32];
    assert(bytes31_to_field(zeros) == 0, "All zeros should give field 0");

    // Single byte at position 30 (LSB of the 31-byte window)
    let mut single: [u8; 32] = [0; 32];
    single[30] = 1;
    assert(bytes31_to_field(single) == 1, "Byte at position 30 should be 1");

    // Single byte at position 0 (MSB of the 31-byte window)
    let mut msb: [u8; 32] = [0; 32];
    msb[0] = 1;
    // 256^30 is a very large number, just check it's non-zero
    assert(bytes31_to_field(msb) != 0, "MSB byte should produce non-zero field");
}

/// Test bytes32_to_field conversion.
#[test]
fn test_bytes32_to_field() {
    let zeros: [u8; 32] = [0; 32];
    assert(bytes32_to_field(zeros) == 0, "All zeros should give field 0");

    // The 32nd byte (index 31) should also be included
    let mut last_byte: [u8; 32] = [0; 32];
    last_byte[31] = 1;
    // bytes32_to_field includes all 32 bytes
    // For index 31 (added separately with highest mul), it should be non-zero
    assert(bytes32_to_field(last_byte) != 0, "Last byte should produce non-zero field");
}

/// Test P256 signature verification logic.
/// Verifies that the SHA-256 message hashing step works correctly.
#[test]
fn test_message_hashing() {
    let outer_hash: Field = 0x1234567890abcdef;
    let outer_hash_bytes: [u8; 32] = outer_hash.to_be_bytes();
    let hashed: [u8; 32] = sha256::digest(outer_hash_bytes);

    // SHA-256 output should be non-zero for non-zero input
    let mut all_zero = true;
    for i in 0..32 {
        if hashed[i] != 0 {
            all_zero = false;
        }
    }
    assert(!all_zero, "SHA-256 of non-zero input should be non-zero");

    // Deterministic
    let hashed_2: [u8; 32] = sha256::digest(outer_hash_bytes);
    assert(hashed == hashed_2, "SHA-256 should be deterministic");
}

// --- Helper functions (copied from contract for testing) ---

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

fn bytes32_to_field(bytes: [u8; 32]) -> Field {
    let mut result: Field = 0;
    let mut mul: Field = 1;
    for i in 1..32 {
        let byte: Field = bytes[31 - i] as Field;
        result = result + (byte * mul);
        mul *= 256;
    }
    result + (bytes[31] as Field) * mul
}

// TODO: Full integration tests require TestEnvironment (TXE)
// These would test:
//   - Contract deployment with P256 key
//   - setup_guardians with 3 hashes
//   - initiate_recovery with 2 valid guardian keys
//   - cancel_recovery during time-lock
//   - execute_recovery after 7200 blocks
//   - rotate_key by current owner
//   - Invalid guardian keys rejected
//   - Duplicate guardian detection
//   - Time-lock enforcement (too early = revert)
