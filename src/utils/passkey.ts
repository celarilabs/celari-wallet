/**
 * Celari Wallet — WebAuthn/Passkey Utility
 *
 * Handles passkey lifecycle:
 * 1. Create credential (register) → P256 key pair in secure enclave
 * 2. Sign challenge (authenticate) → P256 signature via biometric
 * 3. Extract public key coordinates for account contract
 *
 * Compatible with:
 * - Apple Face ID / Touch ID (iCloud Keychain sync)
 * - Android Fingerprint / Face Unlock (Google Password Manager sync)
 * - Windows Hello (PIN / fingerprint / face)
 * - YubiKey / hardware security keys
 */

// ─── Types ─────────────────────────────────────────────

export interface PasskeyCredential {
  credentialId: string;
  rawId: Uint8Array;
  publicKeyX: Uint8Array; // 32 bytes
  publicKeyY: Uint8Array; // 32 bytes
  publicKeyHex: { x: string; y: string };
}

export interface PasskeySignature {
  signature: Uint8Array;   // 64 bytes (r || s)
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  signatureHex: string;
}

// ─── Constants ─────────────────────────────────────────

const RP_NAME = "Celari Wallet";
const RP_ID = typeof window !== "undefined" ? window.location.hostname : "localhost";

// COSE algorithm identifier for ES256 (ECDSA w/ SHA-256 on P-256)
const COSE_ALG_ES256 = -7;

// ─── Credential Creation ───────────────────────────────

/**
 * Create a new passkey credential.
 *
 * This triggers the browser's WebAuthn dialog:
 * - On macOS/iOS: Face ID or Touch ID prompt
 * - On Android: Fingerprint or face unlock
 * - On Windows: Windows Hello prompt
 *
 * The P256 key pair is generated and stored in the device's
 * secure enclave. The private key NEVER leaves the device.
 *
 * @param username - Display name for the credential
 * @returns PasskeyCredential with public key coordinates
 */
export async function createPasskeyCredential(
  username: string = "Celari User"
): Promise<PasskeyCredential> {
  // Generate a random user ID
  const userId = crypto.getRandomValues(new Uint8Array(32));

  const createOptions: CredentialCreationOptions = {
    publicKey: {
      rp: {
        name: RP_NAME,
        id: RP_ID,
      },
      user: {
        id: userId,
        name: username,
        displayName: username,
      },
      challenge: crypto.getRandomValues(new Uint8Array(32)),
      pubKeyCredParams: [
        { type: "public-key", alg: COSE_ALG_ES256 },
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform", // Use built-in authenticator
        residentKey: "required",             // Discoverable credential
        userVerification: "required",        // Always require biometric
      },
      timeout: 60000,
      attestation: "none", // We don't need attestation
    },
  };

  const credential = (await navigator.credentials.create(
    createOptions
  )) as PublicKeyCredential;

  if (!credential) {
    throw new Error("Passkey creation cancelled or failed");
  }

  const response = credential.response as AuthenticatorAttestationResponse;

  // Extract P256 public key from attestation
  const publicKey = extractP256PublicKey(response);

  return {
    credentialId: credential.id,
    rawId: new Uint8Array(credential.rawId),
    publicKeyX: publicKey.x,
    publicKeyY: publicKey.y,
    publicKeyHex: {
      x: bytesToHex(publicKey.x),
      y: bytesToHex(publicKey.y),
    },
  };
}

// ─── Signature (Authentication) ────────────────────────

/**
 * Sign a challenge hash using a passkey.
 *
 * This triggers biometric authentication:
 * - User sees "Sign in to Celari Wallet"
 * - User authenticates with Face ID / fingerprint
 * - Secure enclave produces P256 signature
 * - Signature is returned (private key never exposed)
 *
 * @param credentialId - The credential to use for signing
 * @param challenge - 32-byte hash to sign (transaction payload hash)
 * @returns PasskeySignature with raw signature bytes
 */
export async function signWithPasskey(
  credentialId: string,
  challenge: Uint8Array
): Promise<PasskeySignature> {
  const getOptions: CredentialRequestOptions = {
    publicKey: {
      challenge: challenge.buffer as ArrayBuffer,
      rpId: RP_ID,
      allowCredentials: [
        {
          type: "public-key",
          id: base64UrlToBytes(credentialId).buffer as ArrayBuffer,
        },
      ],
      userVerification: "required",
      timeout: 60000,
    },
  };

  const assertion = (await navigator.credentials.get(
    getOptions
  )) as PublicKeyCredential;

  if (!assertion) {
    throw new Error("Passkey authentication cancelled or failed");
  }

  const response = assertion.response as AuthenticatorAssertionResponse;

  // Extract and normalize the signature to fixed 64-byte format
  const rawSignature = new Uint8Array(response.signature);
  const normalizedSig = normalizeP256Signature(rawSignature);

  return {
    signature: normalizedSig,
    authenticatorData: new Uint8Array(response.authenticatorData),
    clientDataJSON: new Uint8Array(response.clientDataJSON),
    signatureHex: bytesToHex(normalizedSig),
  };
}

// ─── Public Key Extraction ─────────────────────────────

/**
 * Extract P256 public key (x, y) from attestation response.
 *
 * WebAuthn returns the public key in COSE format inside
 * the attestation object. We decode it to get raw X/Y
 * coordinates for the Noir account contract.
 */
function extractP256PublicKey(
  response: AuthenticatorAttestationResponse
): { x: Uint8Array; y: Uint8Array } {
  // getPublicKey() returns the key in SubjectPublicKeyInfo (SPKI) format
  const spki = response.getPublicKey();
  if (!spki) {
    throw new Error("No public key in attestation response");
  }

  const spkiBytes = new Uint8Array(spki);

  // P256 SPKI structure:
  // - 26 bytes header (ASN.1 metadata + OID for P256)
  // - 1 byte: 0x04 (uncompressed point indicator)
  // - 32 bytes: X coordinate
  // - 32 bytes: Y coordinate
  // Total: 91 bytes

  // Find the uncompressed point (0x04 prefix)
  let offset = -1;
  for (let i = 0; i < spkiBytes.length - 64; i++) {
    if (spkiBytes[i] === 0x04 && i + 65 <= spkiBytes.length) {
      offset = i;
      break;
    }
  }

  if (offset === -1) {
    throw new Error("Cannot find uncompressed point in SPKI");
  }

  const x = spkiBytes.slice(offset + 1, offset + 33);
  const y = spkiBytes.slice(offset + 33, offset + 65);

  return { x, y };
}

// ─── Signature Normalization ───────────────────────────

/**
 * Normalize a DER-encoded ECDSA signature to fixed 64-byte format.
 *
 * WebAuthn returns DER-encoded signatures:
 *   30 <len> 02 <r-len> <r> 02 <s-len> <s>
 *
 * We need raw (r || s) with exactly 32 bytes each for Noir.
 */
export function normalizeP256Signature(derSig: Uint8Array): Uint8Array {
  const result = new Uint8Array(64);

  // Parse DER structure
  if (derSig[0] !== 0x30) {
    // Already raw format
    if (derSig.length === 64) return derSig;
    throw new Error("Invalid signature format");
  }

  let offset = 2; // Skip 30 <len>

  // Parse r
  if (derSig[offset] !== 0x02) throw new Error("Invalid DER: expected 0x02 for r");
  offset++;
  const rLen = derSig[offset];
  offset++;
  const rBytes = derSig.slice(offset, offset + rLen);
  offset += rLen;

  // Parse s
  if (derSig[offset] !== 0x02) throw new Error("Invalid DER: expected 0x02 for s");
  offset++;
  const sLen = derSig[offset];
  offset++;
  const sBytes = derSig.slice(offset, offset + sLen);

  // Pad/trim r to 32 bytes (big-endian)
  padTo32Bytes(rBytes, result, 0);
  // Pad/trim s to 32 bytes (big-endian)
  padTo32Bytes(sBytes, result, 32);

  return result;
}

export function padTo32Bytes(src: Uint8Array, dest: Uint8Array, destOffset: number) {
  if (src.length === 32) {
    dest.set(src, destOffset);
  } else if (src.length === 33 && src[0] === 0x00) {
    // Remove leading zero (DER padding for positive integers)
    dest.set(src.slice(1), destOffset);
  } else if (src.length < 32) {
    // Left-pad with zeros
    dest.set(src, destOffset + (32 - src.length));
  } else {
    throw new Error(`Unexpected component length: ${src.length}`);
  }
}

// ─── Helpers ───────────────────────────────────────────

export function bytesToHex(bytes: Uint8Array): string {
  return "0x" + Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function base64UrlToBytes(base64url: string): Uint8Array {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export function bytesToBase64Url(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

// ─── Storage Helpers ───────────────────────────────────

/* global chrome */
declare const chrome: any;

const STORAGE_KEY = "celari_passkey_credentials";

export interface StoredCredential {
  credentialId: string;
  publicKeyX: string; // hex
  publicKeyY: string; // hex
  createdAt: string;
  label: string;
}

export async function saveCredential(cred: PasskeyCredential, label: string = "Default") {
  const stored = await getStoredCredentials();
  stored.push({
    credentialId: cred.credentialId,
    publicKeyX: cred.publicKeyHex.x,
    publicKeyY: cred.publicKeyHex.y,
    createdAt: new Date().toISOString(),
    label,
  });
  if (typeof chrome !== "undefined" && chrome.storage?.local) {
    await chrome.storage.local.set({ [STORAGE_KEY]: stored });
  } else if (typeof localStorage !== "undefined") {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
  }
}

export async function getStoredCredentials(): Promise<StoredCredential[]> {
  try {
    if (typeof chrome !== "undefined" && chrome.storage?.local) {
      const result = await chrome.storage.local.get(STORAGE_KEY);
      return result[STORAGE_KEY] || [];
    }
    if (typeof localStorage !== "undefined") {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : [];
    }
    return [];
  } catch {
    return [];
  }
}

export async function clearStoredCredentials() {
  if (typeof chrome !== "undefined" && chrome.storage?.local) {
    await chrome.storage.local.remove(STORAGE_KEY);
  } else if (typeof localStorage !== "undefined") {
    localStorage.removeItem(STORAGE_KEY);
  }
}
