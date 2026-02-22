#!/usr/bin/env npx tsx
/**
 * Deploy CLR token using TestWallet's own Schnorr account as admin,
 * then mint to our passkey account.
 */

import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { TestWallet } from "@aztec/test-wallet/server";

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
  const wallet = await TestWallet.create(node, { proverEnabled: true });

  // Create a Schnorr admin account (TestWallet can sign for these natively)
  const adminManager = await wallet.createSchnorrAccount(Fr.random(), Fr.random());
  const adminAddress = adminManager.address;
  console.log(`Admin (Schnorr): ${adminAddress.toString().slice(0, 22)}...`);
  console.log(`Target account:  ${accountAddress.toString().slice(0, 22)}...`);

  // Deploy admin account first
  console.log("\nDeploying admin account...");
  const { paymentMethod } = await setupSponsoredFPC(wallet);

  const adminDeployMethod = await adminManager.getDeployMethod();
  const adminTx = await adminDeployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod },
  });
  const adminTxHash = await adminTx.getTxHash();
  console.log(`Admin deploy tx: ${adminTxHash.toString().slice(0, 22)}...`);
  await adminTx.wait({ timeout: 180_000 });
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

  const tokenTx = await tokenDeploy.send({
    from: adminAddress,
    fee: { paymentMethod },
  });
  const tokenTxHash = await tokenTx.getTxHash();
  console.log(`Token deploy tx: ${tokenTxHash.toString().slice(0, 22)}...`);

  const tokenReceipt = await tokenTx.wait({ timeout: 180_000 });
  const tokenAddress = tokenReceipt.contract.address;
  console.log(`Token deployed! Block: ${tokenReceipt.blockNumber}`);
  console.log(`Token: ${tokenAddress.toString()}`);

  // Mint to our passkey account
  console.log("\nMinting 10,000 CLR...");
  const token = await TokenContract.at(tokenAddress, wallet);

  const mintTx = await token.methods
    .mint_to_public(accountAddress, 10_000n * 10n ** 18n)
    .send({ from: adminAddress, fee: { paymentMethod } });
  const mintTxHash = await mintTx.getTxHash();
  console.log(`Mint tx: ${mintTxHash.toString().slice(0, 22)}...`);

  const mintReceipt = await mintTx.wait({ timeout: 180_000 });
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
    deployBlock: tokenReceipt.blockNumber?.toString(),
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
