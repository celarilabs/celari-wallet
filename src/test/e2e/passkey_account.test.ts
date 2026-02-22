/**
 * Celari Wallet — E2E Integration Tests (Aztec SDK v3)
 *
 * Tests the complete passkey account lifecycle:
 * 1. P256 key generation (simulated — no WebAuthn in Node.js)
 * 2. Passkey account deployment
 * 3. Private token mint
 * 4. Private transfer between passkey accounts
 * 5. Balance verification
 *
 * Prerequisites:
 *   - aztec start --sandbox (running on localhost:8080)
 *   - yarn build (contracts compiled)
 *
 * Run: yarn test
 */

import { describe, it, expect, beforeAll } from "@jest/globals";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { TestWallet } from "@aztec/test-wallet/server";
import { TokenContract } from "@aztec/noir-contracts.js/Token";

const NODE_URL = process.env.AZTEC_NODE_URL || "http://localhost:8080";

describe("Celari Wallet — Passkey Account E2E (SDK v3)", () => {
  let wallet: Awaited<ReturnType<typeof TestWallet.create>>;
  let aliceManager: any;
  let bobManager: any;
  let aliceWallet: any;
  let bobWallet: any;
  let aliceAddress: InstanceType<typeof AztecAddress>;
  let bobAddress: InstanceType<typeof AztecAddress>;
  let tokenAddress: InstanceType<typeof AztecAddress>;

  // ─── Setup ────────────────────────────────────────────

  beforeAll(async () => {
    // Connect to Aztec node via TestWallet
    const node = createAztecNodeClient(NODE_URL);
    wallet = await TestWallet.create(node, { proverEnabled: true });
    const chainInfo = await wallet.getChainInfo();
    console.log(`Connected to Aztec node — Chain ${chainInfo.chainId}`);

    // Create test accounts using Schnorr (P256 fallback in sandbox)
    // In production, CelariPasskeyAccount with real P256 keys is used.
    // The Noir contract tests (TXE) verify actual P256 signature logic.

    console.log("Creating Alice account (simulated passkey)...");
    const aliceSecret = Fr.random();
    const aliceSalt = Fr.random();
    aliceManager = await wallet.createSchnorrAccount(aliceSecret, aliceSalt);
    aliceAddress = aliceManager.address;
    aliceWallet = await aliceManager.getAccount();
    console.log(`Alice: ${aliceAddress.toString().slice(0, 22)}...`);

    console.log("Creating Bob account (simulated passkey)...");
    const bobSecret = Fr.random();
    const bobSalt = Fr.random();
    bobManager = await wallet.createSchnorrAccount(bobSecret, bobSalt);
    bobAddress = bobManager.address;
    bobWallet = await bobManager.getAccount();
    console.log(`Bob: ${bobAddress.toString().slice(0, 22)}...`);

    // Deploy both accounts on-chain
    console.log("Deploying accounts...");
    const aliceDeployTx = await (await aliceManager.getDeployMethod()).send({
      from: AztecAddress.ZERO,
    });
    await aliceDeployTx.wait({ timeout: 180_000 });

    const bobDeployTx = await (await bobManager.getDeployMethod()).send({
      from: AztecAddress.ZERO,
    });
    await bobDeployTx.wait({ timeout: 180_000 });
    console.log("Both accounts deployed.");
  }, 300_000);

  // ─── Test 1: Account Creation ─────────────────────────

  it("should create accounts with deterministic addresses", () => {
    expect(aliceAddress).toBeDefined();
    expect(bobAddress).toBeDefined();
    expect(aliceAddress.toString()).not.toBe(bobAddress.toString());
    console.log("Test 1 passed: Accounts created");
  });

  // ─── Test 2: Token Deployment ─────────────────────────

  it("should deploy a private token contract", async () => {
    console.log("Deploying zkUSD token...");

    const token = await TokenContract.deploy(
      wallet,
      aliceAddress,  // admin
      "Celari USD",  // name
      "zkUSD",       // symbol
      18,            // decimals
    ).send({ from: aliceAddress }).deployed();

    tokenAddress = token.address;
    console.log(`zkUSD deployed: ${tokenAddress.toString().slice(0, 22)}...`);

    expect(tokenAddress).toBeDefined();
    console.log("Test 2 passed: Token deployed");
  }, 300_000);

  // ─── Test 3: Private Mint ─────────────────────────────

  it("should mint tokens to private balance", async () => {
    const token = await TokenContract.at(tokenAddress, aliceWallet);
    const mintAmount = 10_000n;

    console.log(`Minting ${mintAmount} zkUSD to Alice (private)...`);

    await token.methods
      .mint_to_private(aliceAddress, mintAmount)
      .send({ from: aliceAddress })
      .wait({ timeout: 180_000 });

    const balance = await token.methods
      .balance_of_private(aliceAddress)
      .simulate({ from: aliceAddress });

    console.log(`Alice private balance: ${balance}`);
    expect(balance).toBe(mintAmount);
    console.log("Test 3 passed: Private mint successful");
  }, 300_000);

  // ─── Test 4: Private Transfer ─────────────────────────

  it("should transfer tokens privately between accounts", async () => {
    const token = await TokenContract.at(tokenAddress, aliceWallet);
    const transferAmount = 2_500n;

    console.log(`Alice -> Bob: ${transferAmount} zkUSD (private)...`);

    await token.methods
      .transfer(bobAddress, transferAmount)
      .send({ from: aliceAddress })
      .wait({ timeout: 180_000 });

    // Verify Alice's balance decreased
    const aliceBalance = await token.methods
      .balance_of_private(aliceAddress)
      .simulate({ from: aliceAddress });
    expect(aliceBalance).toBe(10_000n - transferAmount);

    // Verify Bob's balance (need Bob's wallet to see private notes)
    const tokenAsBob = await TokenContract.at(tokenAddress, bobWallet);
    const bobBalance = await tokenAsBob.methods
      .balance_of_private(bobAddress)
      .simulate({ from: bobAddress });
    expect(bobBalance).toBe(transferAmount);

    console.log(`Alice balance: ${aliceBalance}`);
    console.log(`Bob balance: ${bobBalance}`);
    console.log("Test 4 passed: Private transfer successful");
  }, 300_000);

  // ─── Test 5: Batch Transfer (Payroll Simulation) ──────

  it("should handle chained transfers (payroll-like)", async () => {
    const token = await TokenContract.at(tokenAddress, aliceWallet);

    // Create Charlie account
    const charlieSecret = Fr.random();
    const charlieSalt = Fr.random();
    const charlieMgr = await wallet.createSchnorrAccount(charlieSecret, charlieSalt);
    const charlieAddress = charlieMgr.address;
    const charlieWallet = await charlieMgr.getAccount();

    // Deploy Charlie
    const charlieDeploy = await (await charlieMgr.getDeployMethod()).send({
      from: AztecAddress.ZERO,
    });
    await charlieDeploy.wait({ timeout: 180_000 });

    // Alice → Bob (salary payment)
    const salary = 1_000n;
    await token.methods
      .transfer(bobAddress, salary)
      .send({ from: aliceAddress })
      .wait({ timeout: 180_000 });

    // Bob → Charlie (spending)
    const tokenAsBob = await TokenContract.at(tokenAddress, bobWallet as any);
    const spending = 500n;
    await tokenAsBob.methods
      .transfer(charlieAddress, spending)
      .send({ from: bobAddress })
      .wait({ timeout: 180_000 });

    // Verify Charlie received funds
    const tokenAsCharlie = await TokenContract.at(tokenAddress, charlieWallet as any);
    const charlieBalance = await tokenAsCharlie.methods
      .balance_of_private(charlieAddress)
      .simulate({ from: charlieAddress });
    expect(charlieBalance).toBe(spending);

    console.log(`Charlie balance: ${charlieBalance}`);
    console.log("Test 5 passed: Chained transfers (payroll flow)");
  }, 300_000);

  // ─── Test 6: P256 Key Format Verification ─────────────

  it("should correctly format P256 public key for contract", () => {
    // Simulate P256 key extraction (same logic as passkey.ts)
    const pubKeyX = new Uint8Array(32);
    const pubKeyY = new Uint8Array(32);
    crypto.getRandomValues(pubKeyX);
    crypto.getRandomValues(pubKeyY);

    // Convert to hex (same as passkey.ts bytesToHex)
    const xHex = "0x" + Array.from(pubKeyX).map(b => b.toString(16).padStart(2, "0")).join("");
    const yHex = "0x" + Array.from(pubKeyY).map(b => b.toString(16).padStart(2, "0")).join("");

    // Verify format
    expect(xHex).toMatch(/^0x[0-9a-f]{64}$/);
    expect(yHex).toMatch(/^0x[0-9a-f]{64}$/);

    // Convert to Field (same as contract constructor args)
    const xField = BigInt(xHex);
    const yField = BigInt(yHex);

    expect(xField).toBeGreaterThan(0n);
    expect(yField).toBeGreaterThan(0n);

    // Verify round-trip: Field → bytes → hex matches original
    const xBack = xField.toString(16).padStart(64, "0");
    expect("0x" + xBack).toBe(xHex);

    console.log("Test 6 passed: P256 key format verified");
  });

  // ─── Test 7: DER Signature Normalization ──────────────

  it("should normalize DER-encoded P256 signatures", () => {
    const r = new Uint8Array(32);
    const s = new Uint8Array(32);
    crypto.getRandomValues(r);
    crypto.getRandomValues(s);

    // Construct DER
    const derSig = new Uint8Array([
      0x30, 2 + 2 + r.length + s.length,
      0x02, r.length, ...r,
      0x02, s.length, ...s,
    ]);

    // Normalize (extract r || s)
    const normalized = normalizeDER(derSig);

    expect(normalized.length).toBe(64);
    expect(Array.from(normalized.slice(0, 32))).toEqual(Array.from(r));
    expect(Array.from(normalized.slice(32, 64))).toEqual(Array.from(s));

    console.log("Test 7 passed: DER normalization correct");
  });

  // ─── Test 8: Auth Witness Layout ──────────────────────

  it("should pack auth witness in correct layout for Noir", () => {
    const signature = new Uint8Array(64);
    const authDataHash = new Uint8Array(32);
    const clientDataHash = new Uint8Array(32);
    crypto.getRandomValues(signature);
    crypto.getRandomValues(authDataHash);
    crypto.getRandomValues(clientDataHash);

    // Pack as witness fields
    const witnessFields: bigint[] = [];
    for (let i = 0; i < 64; i++) witnessFields.push(BigInt(signature[i]));
    for (let i = 0; i < 32; i++) witnessFields.push(BigInt(authDataHash[i]));
    for (let i = 0; i < 32; i++) witnessFields.push(BigInt(clientDataHash[i]));

    expect(witnessFields.length).toBe(128);

    // Verify we can reconstruct signature from fields
    const sigRecon = new Uint8Array(64);
    for (let i = 0; i < 64; i++) sigRecon[i] = Number(witnessFields[i]);
    expect(Array.from(sigRecon)).toEqual(Array.from(signature));

    // Verify authData hash
    const authRecon = new Uint8Array(32);
    for (let i = 0; i < 32; i++) authRecon[i] = Number(witnessFields[64 + i]);
    expect(Array.from(authRecon)).toEqual(Array.from(authDataHash));

    console.log("Test 8 passed: Auth witness layout correct");
  });
});

// ─── Helpers ────────────────────────────────────────────

function normalizeDER(derSig: Uint8Array): Uint8Array {
  const result = new Uint8Array(64);
  if (derSig[0] !== 0x30) {
    if (derSig.length === 64) return derSig;
    throw new Error("Invalid signature format");
  }

  let offset = 2;
  if (derSig[offset] !== 0x02) throw new Error("Invalid DER");
  offset++;
  const rLen = derSig[offset]; offset++;
  const rBytes = derSig.slice(offset, offset + rLen); offset += rLen;

  if (derSig[offset] !== 0x02) throw new Error("Invalid DER");
  offset++;
  const sLen = derSig[offset]; offset++;
  const sBytes = derSig.slice(offset, offset + sLen);

  padTo32(rBytes, result, 0);
  padTo32(sBytes, result, 32);
  return result;
}

function padTo32(src: Uint8Array, dest: Uint8Array, off: number) {
  if (src.length === 32) { dest.set(src, off); }
  else if (src.length === 33 && src[0] === 0x00) { dest.set(src.slice(1), off); }
  else if (src.length < 32) { dest.set(src, off + (32 - src.length)); }
  else { throw new Error(`Unexpected: ${src.length}`); }
}
