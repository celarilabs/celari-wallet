/**
 * Shared Aztec helpers for deploy scripts.
 * Reduces duplication across deploy_passkey_account, deploy-server,
 * deploy-token, and mint-token scripts.
 */

import { Fr } from "@aztec/aztec.js/fields";
import { SponsoredFeePaymentMethod, FeeJuicePaymentMethod } from "@aztec/aztec.js/fee";
import { getContractInstanceFromInstantiationParams } from "@aztec/stdlib/contract";

/**
 * Register the SponsoredFPC contract and return a payment method.
 * Only available on devnet — not deployed on testnet or mainnet.
 */
export async function setupSponsoredFPC(wallet: { registerContract: Function }) {
  const { SponsoredFPCContract } = await import("@aztec/noir-contracts.js/SponsoredFPC");
  const fpcInstance = await getContractInstanceFromInstantiationParams(
    SponsoredFPCContract.artifact,
    { salt: new Fr(0) },
  );
  await wallet.registerContract(fpcInstance, SponsoredFPCContract.artifact);
  return {
    instance: fpcInstance,
    paymentMethod: new SponsoredFeePaymentMethod(fpcInstance.address),
  };
}

/**
 * Get a fee payment method with cascading fallback:
 * 1. SponsoredFPC (devnet only)
 * 2. FeeJuicePaymentMethod (testnet/mainnet — requires Fee Juice balance)
 */
export async function getPaymentMethod(
  wallet: { registerContract: Function },
  payerAddress: { toString: () => string },
): Promise<{ paymentMethod: SponsoredFeePaymentMethod | FeeJuicePaymentMethod }> {
  try {
    return await setupSponsoredFPC(wallet);
  } catch (e) {
    console.warn(`SponsoredFPC unavailable: ${(e as Error).message}. Using FeeJuicePaymentMethod.`);
    return { paymentMethod: new FeeJuicePaymentMethod(payerAddress as any) };
  }
}

/**
 * Generate a fresh P256 (secp256r1) key pair for WebAuthn/Passkey accounts.
 */
export async function generateP256KeyPair() {
  const { subtle } = (await import("crypto")).webcrypto as any;
  const keyPair = await subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pubRaw = new Uint8Array(await subtle.exportKey("raw", keyPair.publicKey));
  const pubKeyX = "0x" + Buffer.from(pubRaw.slice(1, 33)).toString("hex");
  const pubKeyY = "0x" + Buffer.from(pubRaw.slice(33, 65)).toString("hex");
  const privateKeyPkcs8 = new Uint8Array(await subtle.exportKey("pkcs8", keyPair.privateKey));
  return { pubKeyX, pubKeyY, privateKeyPkcs8 };
}
