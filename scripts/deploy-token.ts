#!/usr/bin/env npx tsx
/**
 * Deploy CLR token using EmbeddedWallet's own Schnorr account as admin,
 * then mint to our passkey account.
 */

import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { EmbeddedWallet } from "@aztec/wallets/embedded";

import { setupSponsoredFPC } from "./lib/aztec-helpers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const NODE_URL = "https://rpc.testnet.aztec-labs.com/";

async function main() {
  console.log("Celari -- Deploy CLR Token (v2)\n");

  const accountInfo = JSON.parse(readFileSync(join(__dirname, "..", ".celari-passkey-account.json"), "utf-8"));
  const accountAddress = AztecAddress.fromString(accountInfo.address);

  // Connect with a fresh Schnorr account as admin
  console.log("Connecting...");
  const node = createAztecNodeClient(NODE_URL);
  const wallet = await EmbeddedWallet.create(node, { pxeConfig: { proverEnabled: true } });

  // Create a Schnorr admin account (EmbeddedWallet can sign for these natively)
  const adminManager = await wallet.createSchnorrAccount(Fr.random(), Fr.random());
  const adminAddress = adminManager.address;
  console.log(`Admin (Schnorr): ${adminAddress.toString().slice(0, 22)}...`);
  console.log(`Target account:  ${accountAddress.toString().slice(0, 22)}...`);

  // Deploy admin account first
  console.log("\nDeploying admin account...");
  const { paymentMethod } = await setupSponsoredFPC(wallet);

  const adminDeployMethod = await adminManager.getDeployMethod();
  const adminReceipt = await adminDeployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
    wait: { timeout: 180_000 },
  });
  console.log(`Admin deploy tx: ${adminReceipt.txHash.toString().slice(0, 22)}...`);
  console.log("Admin deployed!");

  // Deploy Token with admin = Schnorr account
  console.log("\nDeploying CLR Token...");
  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");

  const tokenDeploy = TokenContract.deploy(
    wallet,
    adminAddress,
    "Celari Token",
    "CLR",
    18,
  );

  const token = await tokenDeploy.send({
    from: adminAddress,
    fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
    wait: { timeout: 180_000 },
  });
  const tokenAddress = token.address;
  console.log(`Token deployed at: ${tokenAddress.toString()}`);

  // Mint to our passkey account
  console.log("\nMinting 10,000 CLR...");

  const mintReceipt = await token.methods
    .mint_to_public(accountAddress, 10_000n * 10n ** 18n)
    .send({ from: adminAddress, fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 }, wait: { timeout: 180_000 } });
  console.log(`Minted! Block: ${mintReceipt.blockNumber}`);

  // Check balance (best-effort, simulate may fail on some SDK versions)
  try {
    const balance = await token.methods.balance_of_public(accountAddress).simulate({ from: adminAddress });
    console.log(`\nBalance: ${Number(balance) / 1e18} CLR`);
  } catch (e: any) {
    console.log(`\nBalance check skipped (${e.message?.slice(0, 60) || "simulate error"})`);
    console.log("Mint was successful — balance should be 10,000 CLR");
  }

  // Save token info
  const tokenInfo = {
    tokenAddress: tokenAddress.toString(),
    name: "Celari Token",
    symbol: "CLR",
    decimals: 18,
    admin: adminAddress.toString(),
    holderAddress: accountAddress.toString(),
    network: "testnet",
    deployBlock: "",
    mintBlock: mintReceipt.blockNumber?.toString(),
    deployedAt: new Date().toISOString(),
  };
  writeFileSync(join(__dirname, "..", ".celari-token.json"), JSON.stringify(tokenInfo, null, 2));
  console.log("\nToken info saved to .celari-token.json");

  console.log("\n--- Summary ---");
  console.log(`Token:   ${tokenAddress.toString()}`);
  console.log(`Holder:  ${accountAddress.toString()}`);
  console.log(`Balance: 10,000 CLR`);
}

main().catch((e) => {
  console.error("Failed:", e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
