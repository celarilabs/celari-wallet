/**
 * Celari Wallet SDK — Faz 1 Exports
 *
 * Usage:
 *   import { createPasskeyCredential, PasskeyAuthWitnessProvider } from "celari-wallet";
 */

// Passkey / WebAuthn utilities
export {
  createPasskeyCredential,
  signWithPasskey,
  bytesToHex,
  hexToBytes,
  bytesToBase64Url,
  normalizeP256Signature,
  padTo32Bytes,
  saveCredential,
  getStoredCredentials,
  clearStoredCredentials,
  type PasskeyCredential,
  type PasskeySignature,
  type StoredCredential,
} from "./passkey.js";

// Aztec account integration
export {
  PasskeyAuthWitnessProvider,
  getPasskeyAccountDeployArgs,
} from "./passkey_account.js";
