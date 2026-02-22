// Browser shim for Node.js "crypto" module
// Provides webcrypto from browser's native crypto API
export const webcrypto = globalThis.crypto;
export const subtle = globalThis.crypto.subtle;
export function randomBytes(size) {
  const buf = new Uint8Array(size);
  globalThis.crypto.getRandomValues(buf);
  return buf;
}
export function createHash() {
  throw new Error("createHash not available in browser — use SubtleCrypto");
}
export default { webcrypto, subtle, randomBytes, createHash };
