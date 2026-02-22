/**
 * Celari Wallet — Passkey Account Manager
 *
 * Bridges WebAuthn passkeys with Aztec's account abstraction.
 *
 * Flow:
 * 1. User creates passkey -> P256 key pair in secure enclave
 * 2. Public key (x, y) -> deployed as CelariPasskeyAccount contract
 * 3. Each transaction -> WebAuthn assertion -> P256 signature -> auth witness
 * 4. Account contract verifies via ecdsa_secp256r1 in ZK
 *
 * No seed phrases. No private key export. Keys synced via iCloud/Google.
 */

import type { AuthWitnessProvider } from "@aztec/aztec.js/account";
import { AuthWitness } from "@aztec/stdlib/auth-witness";
import type { Fr } from "@aztec/aztec.js/fields";
import type { ContractArtifact } from "@aztec/stdlib/abi";
import type { CompleteAddress } from "@aztec/stdlib/contract";
import { DefaultAccountContract } from "@aztec/accounts/defaults";
import { CelariPasskeyAccountContractArtifact } from "../artifacts/CelariPasskeyAccount.js";

import {
  type PasskeyCredential,
  signWithPasskey,
} from "./passkey.js";

/**
 * Auth witness provider that uses WebAuthn passkeys.
 *
 * When Aztec needs a signature (auth witness) for a transaction,
 * this provider triggers the browser's passkey dialog.
 *
 * In v3, the auth witness layout is simplified:
 * - 64 Field elements representing 64 bytes of P256 signature (r || s)
 * - The Noir contract hashes the outer_hash with SHA-256 before verification
 */
export class PasskeyAuthWitnessProvider implements AuthWitnessProvider {
  constructor(private credential: PasskeyCredential) {}

  async createAuthWit(messageHash: Fr | Buffer): Promise<AuthWitness> {
    // Convert the Aztec message hash to a 32-byte Uint8Array for WebAuthn signing.
    // Using toBuffer() ensures consistent 32-byte big-endian encoding,
    // matching CliP256AuthWitnessProvider and the browser offscreen implementation.
    const hashBytes = messageHash instanceof Buffer
      ? new Uint8Array(messageHash)
      : new Uint8Array((messageHash as Fr).toBuffer());

    // Trigger biometric authentication
    // User sees: "Sign in to Celari Wallet" -> Face ID / fingerprint
    const passkeySignature = await signWithPasskey(
      this.credential.credentialId,
      hashBytes
    );

    // Pack signature into auth witness fields
    // Layout matches what the v3 Noir contract expects:
    // [0..64] -> P256 signature (r: 32 bytes, s: 32 bytes)
    // The contract internally hashes the outer_hash with SHA-256
    const witnessFields: (Fr | number)[] = [];

    // Signature bytes as individual Field elements
    for (let i = 0; i < 64; i++) {
      witnessFields.push(passkeySignature.signature[i]);
    }

    return new AuthWitness(messageHash as Fr, witnessFields);
  }
}

/**
 * @beta This function is part of the SDK public API but not yet used internally.
 */
/**
 * Create a deployment configuration for a new passkey-based account.
 *
 * Returns the init args needed to deploy CelariPasskeyAccount contract.
 */
export function getPasskeyAccountDeployArgs(credential: PasskeyCredential) {
  return {
    pubKeyX: credential.publicKeyHex.x,
    pubKeyY: credential.publicKeyHex.y,
    credentialId: credential.credentialId,
  };
}

/**
 * Auth witness provider for CLI/deploy context.
 * Uses a P256 private key directly (not via WebAuthn) to sign.
 * This is used when deploying from the command line where
 * the browser's secure enclave is not available.
 */
class CliP256AuthWitnessProvider implements AuthWitnessProvider {
  constructor(private privateKey: Uint8Array) {}

  async createAuthWit(messageHash: Fr): Promise<AuthWitness> {
    // Import Node.js crypto
    const { subtle } = (await import("crypto")).webcrypto as any;

    // Import the P256 private key
    const key = await subtle.importKey(
      "pkcs8",
      this.privateKey,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );

    // The Noir contract does: sha256(outer_hash_bytes) then verify_signature(... hashed_message)
    // WebCrypto's sign({ hash: "SHA-256" }) internally hashes the input with SHA-256
    // So we pass the raw outer_hash bytes (32 bytes, big-endian) via toBuffer()
    // Using toBuffer() instead of toString() to ensure correct 32-byte encoding
    const hashBytes = messageHash.toBuffer();

    // Sign with P256 — WebCrypto will SHA-256 hash hashBytes before signing
    const sigDer = new Uint8Array(await subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      hashBytes,
    ));

    // WebCrypto returns IEEE P1363 format (r || s, each 32 bytes)
    const witnessFields: number[] = [];
    for (let i = 0; i < 64; i++) {
      witnessFields.push(sigDer[i]);
    }

    return new AuthWitness(messageHash as Fr, witnessFields);
  }
}

/**
 * Account contract implementation for Celari's passkey-based accounts.
 *
 * Extends DefaultAccountContract to work with AccountManager.
 * Constructor args: (pub_key_x: Field, pub_key_y: Field)
 *
 * Unlike EcdsaR which uses a private key for signing, this uses
 * WebAuthn passkeys — signing happens in the browser's secure enclave.
 */
export class CelariPasskeyAccountContract extends DefaultAccountContract {
  constructor(
    private pubKeyX: Buffer,
    private pubKeyY: Buffer,
    private credential?: PasskeyCredential,
    private cliPrivateKey?: Uint8Array,
  ) {
    super();
  }

  async getContractArtifact(): Promise<ContractArtifact> {
    return CelariPasskeyAccountContractArtifact;
  }

  async getInitializationFunctionAndArgs() {
    return {
      constructorName: "constructor",
      constructorArgs: [this.pubKeyX, this.pubKeyY],
    };
  }

  getAuthWitnessProvider(address: CompleteAddress): AuthWitnessProvider {
    if (this.credential) {
      return new PasskeyAuthWitnessProvider(this.credential);
    }
    if (this.cliPrivateKey) {
      return new CliP256AuthWitnessProvider(this.cliPrivateKey);
    }
    throw new Error(
      "No passkey credential or CLI private key provided. " +
      "Pass a credential (browser) or cliPrivateKey (CLI) to sign transactions."
    );
  }
}
