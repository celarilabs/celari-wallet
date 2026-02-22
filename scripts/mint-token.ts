#!/usr/bin/env npx tsx
/**
 * Mint CLR tokens to our deployed account using the existing Token contract.
 */

import { readFileSync, existsSync } from "fs";
import { join, dirname, resolve } from "path";
import { fileURLToPath } from "url";

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { TestWallet } from "@aztec/test-wallet/server";

import { setupSponsoredFPC } from "./lib/aztec-helpers.js";

import { CelariPasskeyAccountContract } from "../src/utils/passkey_account.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const NODE_URL = "https://rpc.testnet.aztec-labs.com/";

function getTokenAddress(): string {
  const tokenPath = resolve(__dirname, '../.celari-token.json');
  if (existsSync(tokenPath)) {
    const data = JSON.parse(readFileSync(tokenPath, 'utf-8'));
    return data.tokenAddress;
  }
  if (process.env.TOKEN_ADDRESS) {
    return process.env.TOKEN_ADDRESS;
  }
  throw new Error('Token address not found. Deploy token first or set TOKEN_ADDRESS env var.');
}

async function main() {
  console.log("Celari -- Mint CLR Tokens\n");

  // Load account info
  const accountInfo = JSON.parse(readFileSync(join(__dirname, "..", ".celari-passkey-account.json"), "utf-8"));
  const accountAddress = AztecAddress.fromString(accountInfo.address);
  const keys = JSON.parse(readFileSync(join(__dirname, "..", ".celari-keys.json"), "utf-8"));

  // Connect
  console.log("Connecting...");
  const node = createAztecNodeClient(NODE_URL);
  const wallet = await TestWallet.create(node, { proverEnabled: true });

  // Register account
  const accountContract = new CelariPasskeyAccountContract(
    Buffer.from(keys.publicKeyX.replace("0x", ""), "hex"),
    Buffer.from(keys.publicKeyY.replace("0x", ""), "hex"),
    undefined,
    new Uint8Array(Buffer.from(keys.privateKeyPkcs8, "base64")),
  );
  await wallet.createAccount({
    secret: Fr.fromHexString(accountInfo.secretKey),
    salt: Fr.fromHexString(accountInfo.salt),
    contract: accountContract,
  });
  console.log(`Account: ${accountAddress.toString().slice(0, 22)}...`);

  // Register SponsoredFPC
  const { paymentMethod } = await setupSponsoredFPC(wallet);

  // Load Token contract at existing address
  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");
  const tokenAddress = AztecAddress.fromString(getTokenAddress());
  const token = await TokenContract.at(tokenAddress, wallet);
  console.log(`Token: ${tokenAddress.toString().slice(0, 22)}...`);

  // Mint
  console.log("\nMinting 10,000 CLR...");
  const mintTx = await token.methods
    .mint_to_public(accountAddress, 10_000n * 10n ** 18n)
    .send({ from: accountAddress, fee: { paymentMethod } });

  const txHash = await mintTx.getTxHash();
  console.log(`TX: ${txHash.toString().slice(0, 22)}...`);

  const receipt = await mintTx.wait({ timeout: 180_000 });
  console.log(`Minted! Block: ${receipt.blockNumber}`);

  // Check balance
  const balance = await token.methods.balance_of_public(accountAddress).simulate({ from: accountAddress });
  console.log(`Balance: ${Number(balance) / 1e18} CLR`);
}

main().catch((e) => {
  console.error("Failed:", e.message || e);
  process.exit(1);
});
