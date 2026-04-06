#!/usr/bin/env npx tsx
/**
 * Celari Wallet -- Deploy Passkey Account on Aztec Devnet
 *
 * Deploys a CelariPasskeyAccount contract using P256 public key
 * coordinates from a previously created passkey.
 *
 * Uses SponsoredFPC for fee payment (free deployment on devnet).
 *
 * Usage:
 *   PUB_KEY_X=0x... PUB_KEY_Y=0x... yarn deploy:passkey
 *
 * Or reads from .celari-keys.json (saved by the browser extension):
 *   yarn deploy:passkey
 *
 * Environment:
 *   AZTEC_NODE_URL - Node endpoint (default: https://devnet-6.aztec-labs.com/)
 */

import { readFileSync, writeFileSync, chmodSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { EmbeddedWallet } from "@aztec/wallets/embedded";
import { AccountManager } from "@aztec/aztec.js/wallet";

import { getPaymentMethod, generateP256KeyPair } from "./lib/aztec-helpers.js";

import { CelariPasskeyAccountContract } from "../src/utils/passkey_account.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  console.log("Celari Wallet -- Passkey Account Deploy");
  console.log("ECDSA-P256 / WebAuthn + SponsoredFPC\n");

  // 1. Generate or load P256 key pair
  // Deploy requires a private key for signing. We either load from .celari-keys.json
  // or generate a fresh key pair.
  let pubKeyX = "";
  let pubKeyY = "";
  let privateKeyPkcs8 = new Uint8Array(0);

  const keyPath = join(__dirname, "..", ".celari-keys.json");
  let loaded = false;

  try {
    const keys = JSON.parse(readFileSync(keyPath, "utf-8"));
    if (keys.publicKeyX && keys.publicKeyY && keys.privateKeyPkcs8) {
      pubKeyX = keys.publicKeyX;
      pubKeyY = keys.publicKeyY;
      privateKeyPkcs8 = new Uint8Array(Buffer.from(keys.privateKeyPkcs8, "base64"));
      console.log("Loaded key pair from .celari-keys.json");
      loaded = true;
    }
  } catch {}

  if (!loaded) {
    // Generate a fresh P256 key pair
    console.log("Generating fresh P256 key pair...");
    const generated = await generateP256KeyPair();
    pubKeyX = generated.pubKeyX;
    pubKeyY = generated.pubKeyY;
    privateKeyPkcs8 = generated.privateKeyPkcs8;

    // Save keys for future use
    writeFileSync(keyPath, JSON.stringify({
      publicKeyX: pubKeyX,
      publicKeyY: pubKeyY,
      privateKeyPkcs8: Buffer.from(privateKeyPkcs8).toString("base64"),
    }, null, 2));
    chmodSync(keyPath, 0o600);
    console.warn("⚠️  WARNING: .celari-keys.json contains private keys. Never commit this file.");
    console.log(`Keys saved to ${keyPath}`);
  }

  // Ensure hex prefix
  if (!pubKeyX.startsWith("0x")) pubKeyX = "0x" + pubKeyX;
  if (!pubKeyY.startsWith("0x")) pubKeyY = "0x" + pubKeyY;

  console.log(`  X: ${pubKeyX.slice(0, 22)}...`);
  console.log(`  Y: ${pubKeyY.slice(0, 22)}...\n`);

  // 2. Connect to Aztec node
  const nodeUrl = process.env.AZTEC_NODE_URL || "https://devnet-6.aztec-labs.com/";
  console.log(`Connecting to ${nodeUrl}...`);

  const node = createAztecNodeClient(nodeUrl);
  const wallet = await EmbeddedWallet.create(node, { pxeConfig: { proverEnabled: true } });
  const chainInfo = await wallet.getChainInfo();
  console.log(`Connected -- Chain ${chainInfo.chainId}, Protocol v${chainInfo.version}\n`);

  // 3. Prepare account contract
  console.log("Preparing CelariPasskeyAccount...");
  console.log("  Auth: ECDSA-P256 (secp256r1)");
  console.log("  Signing: WebAuthn / Passkey");
  console.log("  Fee: SponsoredFPC (devnet) / FeeJuice (testnet/mainnet)\n");

  const pubKeyXBuf = Buffer.from(pubKeyX.replace("0x", ""), "hex");
  const pubKeyYBuf = Buffer.from(pubKeyY.replace("0x", ""), "hex");
  const secretKey = Fr.random();
  const salt = Fr.random();

  // Use wallet.createAccount() pattern -- this registers the contract + account in PXE
  // Pass private key for CLI signing (4th arg = undefined credential, 5th arg = CLI private key)
  const accountContract = new CelariPasskeyAccountContract(
    pubKeyXBuf, pubKeyYBuf, undefined, privateKeyPkcs8,
  );
  const accountManager = await AccountManager.create(wallet, secretKey, accountContract, salt);

  const address = accountManager.address;
  console.log(`Account address: ${address.toString()}`);

  // 4. Set up fee payment (SponsoredFPC on devnet, FeeJuice on testnet/mainnet)
  console.log("\nSetting up fee payment...");

  const { paymentMethod } = await getPaymentMethod(wallet, address);
  console.log(`Fee payment method: ${paymentMethod.constructor.name}`);

  // 5. Deploy account contract
  console.log("\nDeploying account...");
  console.log("(This may take 30-120 seconds)\n");

  const deployMethod = await accountManager.getDeployMethod();
  const receipt = await deployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
    wait: { timeout: 180_000 },
  });

  const txHash = receipt.txHash;
  console.log(`Tx hash: ${txHash.toString().slice(0, 22)}...`);
  console.log(`\nDeployed! Status: ${receipt.status}`);
  console.log(`Block: ${receipt.blockNumber}`);

  // 6. Save deployment info
  const deployInfo = {
    address: address.toString(),
    publicKeyX: pubKeyX,
    publicKeyY: pubKeyY,
    secretKey: secretKey.toString(),
    salt: salt.toString(),
    type: "passkey-p256",
    network: nodeUrl.includes("devnet") ? "devnet" : nodeUrl.includes("testnet") ? "testnet" : "local",
    nodeUrl,
    chainId: chainInfo.chainId.toString(),
    txHash: txHash.toString(),
    blockNumber: receipt.blockNumber?.toString(),
    deployedAt: new Date().toISOString(),
  };

  const outputPath = join(__dirname, "..", ".celari-passkey-account.json");
  writeFileSync(outputPath, JSON.stringify(deployInfo, null, 2));
  chmodSync(outputPath, 0o600);
  console.warn("⚠️  WARNING: .celari-passkey-account.json contains sensitive data. Never commit this file.");
  console.log(`\nDeployment info saved to ${outputPath}`);
  console.log(`\nAccount deployed successfully!`);
  console.log(`Address: ${address.toString()}`);
}

main().catch((e) => {
  console.error("\nDeployment failed:", e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
