/**
 * Celari Bridge — Content Hash Computation
 *
 * Shared utility for computing content hashes that must match
 * between L1 (Solidity) and L2 (Noir/Aztec) message passing.
 *
 * Aztec uses SHA-256 content hashes truncated to fit a Field element
 * (< BN254 scalar field modulus). Both sides must compute identical
 * hashes for message claiming to work.
 */

/**
 * Compute SHA-256 hash of the given data.
 */
async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const hash = await crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(hash);
}

/**
 * Convert a 32-byte SHA-256 hash to an Aztec Field element.
 * Zeroes the most significant byte so the value fits in a
 * BN254 scalar field element (~254 bits).
 *
 * This matches the Solidity implementation:
 *   bytes32(bytes.concat(new bytes(1), bytes31(sha256(data))))
 */
export function sha256ToField(hash: Uint8Array): bigint {
  let value = BigInt(0);
  // Skip byte 0 (MSB) — start from byte 1
  for (let i = 1; i < 32; i++) {
    value = (value << BigInt(8)) | BigInt(hash[i]);
  }
  return value;
}

/**
 * Encode a bigint as a 32-byte big-endian Uint8Array.
 */
export function bigintToBytes32(value: bigint): Uint8Array {
  const bytes = new Uint8Array(32);
  let v = value;
  for (let i = 31; i >= 0; i--) {
    bytes[i] = Number(v & BigInt(0xff));
    v >>= BigInt(8);
  }
  return bytes;
}

/**
 * Encode an Ethereum address (20 bytes) as a 32-byte padded value.
 */
export function addressToBytes32(address: string): Uint8Array {
  const bytes = new Uint8Array(32);
  const hex = address.replace("0x", "").padStart(40, "0");
  for (let i = 0; i < 20; i++) {
    bytes[12 + i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

/**
 * Compute the content hash for a deposit message (L1 → L2).
 *
 * Must match the Solidity encoding:
 *   sha256(abi.encode(token, amount, to, secretHash))
 *
 * The result is reduced to a Field element for Aztec compatibility.
 */
export async function computeDepositContentHash(
  token: string,
  amount: bigint,
  to: bigint,
  secretHash: bigint
): Promise<bigint> {
  // ABI-encode: each value as 32 bytes, concatenated
  const encoded = new Uint8Array(128);
  encoded.set(addressToBytes32(token), 0);
  encoded.set(bigintToBytes32(amount), 32);
  encoded.set(bigintToBytes32(to), 64);
  encoded.set(bigintToBytes32(secretHash), 96);

  const hash = await sha256(encoded);
  return sha256ToField(hash);
}

/**
 * Compute the content hash for a withdrawal message (L2 → L1).
 *
 * Must match the Noir encoding:
 *   sha256(token, amount, recipient, callerOnL1)
 */
export async function computeWithdrawContentHash(
  token: string,
  amount: bigint,
  recipient: string,
  callerOnL1: string
): Promise<bigint> {
  const encoded = new Uint8Array(128);
  encoded.set(addressToBytes32(token), 0);
  encoded.set(bigintToBytes32(amount), 32);
  encoded.set(addressToBytes32(recipient), 64);
  encoded.set(addressToBytes32(callerOnL1), 96);

  const hash = await sha256(encoded);
  return sha256ToField(hash);
}

/**
 * Generate a random secret and compute its hash.
 * Used for private deposits where the secret proves ownership.
 */
export async function generateSecretHash(): Promise<{
  secret: bigint;
  secretHash: bigint;
}> {
  const secretBytes = new Uint8Array(32);
  crypto.getRandomValues(secretBytes);
  // Zero MSB to ensure it fits in a BN254 field element
  secretBytes[0] = 0;

  let secret = BigInt(0);
  for (const byte of secretBytes) {
    secret = (secret << BigInt(8)) | BigInt(byte);
  }

  const hash = await sha256(bigintToBytes32(secret));
  const secretHash = sha256ToField(hash);

  return { secret, secretHash };
}

/**
 * Convert a hex string (with or without 0x prefix) to bigint.
 */
export function hexToBigInt(hex: string): bigint {
  return BigInt(hex.startsWith("0x") ? hex : `0x${hex}`);
}

/**
 * Convert a bigint to a 0x-prefixed hex string.
 */
export function bigintToHex(value: bigint): string {
  return `0x${value.toString(16).padStart(64, "0")}`;
}
