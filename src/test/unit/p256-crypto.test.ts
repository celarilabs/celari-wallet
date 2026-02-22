/**
 * P256 Cryptography & Auth Witness Layout Tests
 *
 * Tests the complete signing pipeline:
 * 1. P256 key pair generation (same as deploy scripts)
 * 2. ECDSA-SHA256 signing (same as CliP256AuthWitnessProvider)
 * 3. Auth witness field packing (same as Noir contract expects)
 * 4. Signature verification round-trip
 */

import { describe, it, expect } from "@jest/globals";
import { webcrypto } from "crypto";

const { subtle } = webcrypto as any;

// ─── Helper: same as scripts/lib/aztec-helpers.ts ────────

async function generateP256KeyPair() {
  const keyPair = await subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pubRaw = new Uint8Array(await subtle.exportKey("raw", keyPair.publicKey));
  const pubKeyX = pubRaw.slice(1, 33);
  const pubKeyY = pubRaw.slice(33, 65);
  const privateKeyPkcs8 = new Uint8Array(await subtle.exportKey("pkcs8", keyPair.privateKey));
  return { keyPair, pubKeyX, pubKeyY, privateKeyPkcs8 };
}

// ─── Helper: same as CliP256AuthWitnessProvider ──────────

async function signWithP256(privateKeyPkcs8: Uint8Array, message: Uint8Array) {
  const key = await subtle.importKey(
    "pkcs8",
    privateKeyPkcs8,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    message,
  ));
  return sig;
}

async function verifyP256(publicKey: CryptoKey, message: Uint8Array, signature: Uint8Array) {
  return subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    signature,
    message,
  );
}

// ─── Tests ───────────────────────────────────────────────

describe("P256 Key Generation", () => {
  it("should generate valid P256 key pair", async () => {
    const { pubKeyX, pubKeyY, privateKeyPkcs8 } = await generateP256KeyPair();

    expect(pubKeyX.length).toBe(32);
    expect(pubKeyY.length).toBe(32);
    expect(privateKeyPkcs8.length).toBeGreaterThan(0);
  });

  it("should generate unique key pairs", async () => {
    const key1 = await generateP256KeyPair();
    const key2 = await generateP256KeyPair();

    expect(Array.from(key1.pubKeyX)).not.toEqual(Array.from(key2.pubKeyX));
  });

  it("should produce hex-encodable coordinates", async () => {
    const { pubKeyX, pubKeyY } = await generateP256KeyPair();
    const xHex = "0x" + Buffer.from(pubKeyX).toString("hex");
    const yHex = "0x" + Buffer.from(pubKeyY).toString("hex");

    expect(xHex).toMatch(/^0x[0-9a-f]{64}$/);
    expect(yHex).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it("should export public key in uncompressed format (0x04 prefix)", async () => {
    const { keyPair } = await generateP256KeyPair();
    const pubRaw = new Uint8Array(await subtle.exportKey("raw", keyPair.publicKey));

    expect(pubRaw.length).toBe(65);
    expect(pubRaw[0]).toBe(0x04); // uncompressed point prefix
  });

  it("should re-import exported private key", async () => {
    const { privateKeyPkcs8 } = await generateP256KeyPair();

    const reimported = await subtle.importKey(
      "pkcs8",
      privateKeyPkcs8,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );

    expect(reimported.type).toBe("private");
  });
});

describe("P256 Signing", () => {
  it("should produce IEEE P1363 format signature (64 bytes)", async () => {
    const { privateKeyPkcs8 } = await generateP256KeyPair();
    const message = new Uint8Array(32);
    webcrypto.getRandomValues(message);

    const sig = await signWithP256(privateKeyPkcs8, message);

    // WebCrypto ECDSA returns IEEE P1363 format: r(32) || s(32) = 64 bytes
    expect(sig.length).toBe(64);
  });

  it("should produce different signatures for different messages", async () => {
    const { privateKeyPkcs8 } = await generateP256KeyPair();
    const msg1 = webcrypto.getRandomValues(new Uint8Array(32));
    const msg2 = webcrypto.getRandomValues(new Uint8Array(32));

    const sig1 = await signWithP256(privateKeyPkcs8, msg1);
    const sig2 = await signWithP256(privateKeyPkcs8, msg2);

    expect(Array.from(sig1)).not.toEqual(Array.from(sig2));
  });

  it("should verify signature with corresponding public key", async () => {
    const { keyPair, privateKeyPkcs8 } = await generateP256KeyPair();
    const message = webcrypto.getRandomValues(new Uint8Array(32));

    const sig = await signWithP256(privateKeyPkcs8, message);
    const valid = await verifyP256(keyPair.publicKey, message, sig);

    expect(valid).toBe(true);
  });

  it("should fail verification with wrong message", async () => {
    const { keyPair, privateKeyPkcs8 } = await generateP256KeyPair();
    const message = webcrypto.getRandomValues(new Uint8Array(32));
    const wrongMessage = webcrypto.getRandomValues(new Uint8Array(32));

    const sig = await signWithP256(privateKeyPkcs8, message);
    const valid = await verifyP256(keyPair.publicKey, wrongMessage, sig);

    expect(valid).toBe(false);
  });

  it("should fail verification with wrong key", async () => {
    const key1 = await generateP256KeyPair();
    const key2 = await generateP256KeyPair();
    const message = webcrypto.getRandomValues(new Uint8Array(32));

    const sig = await signWithP256(key1.privateKeyPkcs8, message);
    const valid = await verifyP256(key2.keyPair.publicKey, message, sig);

    expect(valid).toBe(false);
  });
});

describe("Auth Witness Layout", () => {
  it("should pack 64-byte signature into 64 Field elements", async () => {
    const { privateKeyPkcs8 } = await generateP256KeyPair();
    const outerHash = webcrypto.getRandomValues(new Uint8Array(32));

    const sig = await signWithP256(privateKeyPkcs8, outerHash);

    // Pack as witness fields — same as CliP256AuthWitnessProvider
    const witnessFields: number[] = [];
    for (let i = 0; i < 64; i++) {
      witnessFields.push(sig[i]);
    }

    expect(witnessFields.length).toBe(64);

    // Each field should be a byte value (0-255)
    witnessFields.forEach((f, i) => {
      expect(f).toBeGreaterThanOrEqual(0);
      expect(f).toBeLessThanOrEqual(255);
      expect(f).toBe(sig[i]);
    });
  });

  it("should reconstruct signature from witness fields", async () => {
    const { keyPair, privateKeyPkcs8 } = await generateP256KeyPair();
    const message = webcrypto.getRandomValues(new Uint8Array(32));
    const sig = await signWithP256(privateKeyPkcs8, message);

    // Pack to fields
    const fields = Array.from(sig).map(Number);

    // Reconstruct
    const reconstructed = new Uint8Array(fields);

    // Verify reconstructed signature
    const valid = await verifyP256(keyPair.publicKey, message, reconstructed);
    expect(valid).toBe(true);
  });

  it("should extract r and s components correctly", async () => {
    const { privateKeyPkcs8 } = await generateP256KeyPair();
    const message = webcrypto.getRandomValues(new Uint8Array(32));
    const sig = await signWithP256(privateKeyPkcs8, message);

    const r = sig.slice(0, 32);
    const s = sig.slice(32, 64);

    // Both r and s should be 32 bytes
    expect(r.length).toBe(32);
    expect(s.length).toBe(32);

    // Neither should be all zeros (astronomically unlikely)
    expect(r.some(b => b !== 0)).toBe(true);
    expect(s.some(b => b !== 0)).toBe(true);
  });

  it("should match Noir contract's expected witness format", async () => {
    // The Noir contract reads:
    // let sig_bytes: [u8; 64] = witness[0..64]
    // Then uses ecdsa_secp256r1_verify(hashed_message, pub_key_x, pub_key_y, sig_bytes)
    //
    // Our packing: sig[0] → Field(witness[0]), ..., sig[63] → Field(witness[63])
    // Noir reads: witness[i].to_be_bytes()[0] to get back u8

    const { privateKeyPkcs8 } = await generateP256KeyPair();
    const outerHash = webcrypto.getRandomValues(new Uint8Array(32));
    const sig = await signWithP256(privateKeyPkcs8, outerHash);

    // Simulate Noir's reading pattern
    const witnessFields = Array.from(sig).map(b => BigInt(b));

    // Noir does: witness[i] as u8 (takes low byte)
    const noirSigBytes = witnessFields.map(f => Number(f & 0xFFn));

    expect(noirSigBytes).toEqual(Array.from(sig));
  });
});

describe("Full Pipeline: KeyGen → Sign → Witness → Verify", () => {
  it("should complete full passkey account lifecycle", async () => {
    // Step 1: Generate P256 key pair (same as extension popup)
    const { keyPair, pubKeyX, pubKeyY, privateKeyPkcs8 } = await generateP256KeyPair();

    expect(pubKeyX.length).toBe(32);
    expect(pubKeyY.length).toBe(32);

    // Step 2: Simulate transaction hash (outer_hash from Aztec)
    const outerHash = webcrypto.getRandomValues(new Uint8Array(32));

    // Step 3: Sign with P256 (same as CliP256AuthWitnessProvider)
    // WebCrypto will SHA-256 the outerHash before signing
    const sig = await signWithP256(privateKeyPkcs8, outerHash);
    expect(sig.length).toBe(64);

    // Step 4: Pack as auth witness (same as passkey_account.ts)
    const witnessFields: number[] = [];
    for (let i = 0; i < 64; i++) {
      witnessFields.push(sig[i]);
    }

    // Step 5: Unpack witness (same as Noir contract)
    const sigFromWitness = new Uint8Array(witnessFields);

    // Step 6: Verify (same as Noir's ecdsa_secp256r1_verify)
    const valid = await verifyP256(keyPair.publicKey, outerHash, sigFromWitness);
    expect(valid).toBe(true);
  });
});
