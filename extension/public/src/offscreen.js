/**
 * Celari Wallet — Offscreen PXE Engine
 *
 * Runs the Aztec PXE (Private eXecution Environment) in a Chrome offscreen document.
 * Handles WASM proof generation, account management, balance queries, and transfers.
 *
 * Architecture:
 *   popup.js ↔ background.js ↔ offscreen.js (this file)
 *   This file owns the PXE lifecycle and all Aztec SDK interactions.
 */

import { EmbeddedWallet } from "@aztec/wallets/embedded";
import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { DefaultAccountContract } from "@aztec/accounts/defaults";
import { AuthWitness } from "@aztec/stdlib/auth-witness";
import { SponsoredFeePaymentMethod } from "@aztec/aztec.js/fee";
import { getContractInstanceFromInstantiationParams } from "@aztec/stdlib/contract";
import { loadContractArtifact } from "@aztec/aztec.js/abi";
import { jsonStringify } from "@aztec/foundation/json-rpc";
import { WalletSchema, AccountManager } from "@aztec/aztec.js/wallet";
import { deriveKeys } from "@aztec/stdlib/keys";

// Contract artifacts (compiled Noir → JSON)
import CelariPasskeyAccountArtifactJson from "../../../contracts/celari_passkey_account/target/celari_passkey_account-CelariPasskeyAccount.json" with { type: "json" };
const CelariPasskeyAccountArtifact = loadContractArtifact(CelariPasskeyAccountArtifactJson);

// Guardian Recovery contract artifact — static import (esbuild inlines JSON),
// but loadContractArtifact() is deferred until first use.
import CelariRecoverableAccountArtifactJson from "../../../contracts/celari_recoverable_account/target/celari_recoverable_account-CelariRecoverableAccount.json" with { type: "json" };
let CelariRecoverableAccountArtifact = null;
function getRecoveryArtifact() {
  if (CelariRecoverableAccountArtifact) return CelariRecoverableAccountArtifact;
  try {
    CelariRecoverableAccountArtifact = loadContractArtifact(CelariRecoverableAccountArtifactJson);
    return CelariRecoverableAccountArtifact;
  } catch (e) {
    console.warn("[PXE] CelariRecoverableAccount artifact load failed (recovery disabled):", e.message);
    return null;
  }
}

// --- In-Memory KV Store for iOS ---
// WKWebView's IndexedDB crashes on PXE block sync transactions.
// This drop-in replacement uses Map-backed storage (ephemeral, re-syncs each launch).

class _MemMap {
  constructor(n) { this.name = n; this._d = new Map(); }
  set db(_) {}
  _k(k) { return (Array.isArray(k) ? k : [k]).map(e => typeof e === 'number' ? `n_${e}` : String(e)).join(','); }
  _dk(k) { const p = k.split(',').map(x => x.startsWith('n_') ? Number(x.slice(2)) : x); return p.length > 1 ? p : p[0]; }
  async getAsync(k) { return this._d.get(this._k(k)); }
  async hasAsync(k) { return this._d.has(this._k(k)); }
  async sizeAsync() { return this._d.size; }
  async set(k, v) { this._d.set(this._k(k), v); }
  async setMany(e) { for (const { key, value } of e) this._d.set(this._k(key), value); }
  swap() { throw new Error('Not implemented'); }
  async setIfNotExists(k, v) { const nk = this._k(k); if (!this._d.has(nk)) { this._d.set(nk, v); return true; } return false; }
  async delete(k) { this._d.delete(this._k(k)); }
  async *entriesAsync(r = {}) {
    let e = [...this._d.entries()];
    if (r.start) { const s = this._k(r.start); e = e.filter(([k]) => k >= s); }
    if (r.end) { const s = this._k(r.end); e = e.filter(([k]) => k < s); }
    if (r.reverse) e.reverse();
    let c = 0;
    for (const [k, v] of e) { if (r.limit && c >= r.limit) return; yield [this._dk(k), v]; c++; }
  }
  async *valuesAsync(r = {}) { for await (const [, v] of this.entriesAsync(r)) yield v; }
  async *keysAsync(r = {}) { for await (const [k] of this.entriesAsync(r)) yield k; }
}

class _MemSet {
  constructor(n) { this._m = new _MemMap(n); }
  set db(_) {}
  hasAsync(k) { return this._m.hasAsync(k); }
  add(k) { return this._m.set(k, true); }
  delete(k) { return this._m.delete(k); }
  async *entriesAsync(r) { yield* this._m.keysAsync(r); }
}

class _MemMultiMap {
  constructor(n) { this.name = n; this._d = new Map(); }
  set db(_) {}
  _k(k) { return (Array.isArray(k) ? k : [k]).map(e => typeof e === 'number' ? `n_${e}` : String(e)).join(','); }
  _dk(k) { const p = k.split(',').map(x => x.startsWith('n_') ? Number(x.slice(2)) : x); return p.length > 1 ? p : p[0]; }
  async getAsync(k) { return (this._d.get(this._k(k)) || [])[0]; }
  async hasAsync(k) { return (this._d.get(this._k(k)) || []).length > 0; }
  async sizeAsync() { let c = 0; for (const v of this._d.values()) c += v.length; return c; }
  async set(k, v) {
    const nk = this._k(k);
    if (!this._d.has(nk)) this._d.set(nk, []);
    const arr = this._d.get(nk), s = JSON.stringify(v);
    if (!arr.some(x => JSON.stringify(x) === s)) arr.push(v);
  }
  async setMany(e) { for (const { key, value } of e) await this.set(key, value); }
  swap() { throw new Error('Not implemented'); }
  async setIfNotExists(k, v) { if (!await this.hasAsync(k)) { await this.set(k, v); return true; } return false; }
  async delete(k) { this._d.delete(this._k(k)); }
  async *getValuesAsync(k) { for (const v of (this._d.get(this._k(k)) || [])) yield v; }
  async getValueCountAsync(k) { return (this._d.get(this._k(k)) || []).length; }
  async deleteValue(k, v) {
    const arr = this._d.get(this._k(k)); if (!arr) return;
    const s = JSON.stringify(v), i = arr.findIndex(x => JSON.stringify(x) === s);
    if (i >= 0) arr.splice(i, 1);
  }
  async *entriesAsync(r = {}) { for (const [k, vs] of this._d) for (const v of vs) yield [this._dk(k), v]; }
  async *valuesAsync(r = {}) { for (const vs of this._d.values()) for (const v of vs) yield v; }
  async *keysAsync(r = {}) { for (const k of this._d.keys()) yield this._dk(k); }
}

class _MemArray {
  constructor() { this._d = []; }
  set db(_) {}
  async lengthAsync() { return this._d.length; }
  async push(...v) { this._d.push(...v); return this._d.length; }
  async pop() { return this._d.pop(); }
  async atAsync(i) { return this._d[i < 0 ? this._d.length + i : i]; }
  async setAt(i, v) { if (i < 0) i += this._d.length; if (i < 0 || i >= this._d.length) return false; this._d[i] = v; return true; }
  async *entriesAsync() { for (let i = 0; i < this._d.length; i++) yield [i, this._d[i]]; }
  async *valuesAsync() { for (const v of this._d) yield v; }
  [Symbol.asyncIterator]() { return this.valuesAsync(); }
}

class _MemSingleton {
  constructor() { this._v = undefined; }
  set db(_) {}
  async getAsync() { return this._v; }
  async set(v) { this._v = v; return true; }
  async delete() { this._v = undefined; return true; }
}

class MemoryAztecStore {
  constructor() {
    this.isEphemeral = true;
    this._c = { map: {}, set: {}, mm: {}, arr: {}, sg: {} };
  }
  openMap(n) { return this._c.map[n] || (this._c.map[n] = new _MemMap(n)); }
  openSet(n) { return this._c.set[n] || (this._c.set[n] = new _MemSet(n)); }
  openMultiMap(n) { return this._c.mm[n] || (this._c.mm[n] = new _MemMultiMap(n)); }
  openArray(n) { return this._c.arr[n] || (this._c.arr[n] = new _MemArray()); }
  openSingleton(n) { return this._c.sg[n] || (this._c.sg[n] = new _MemSingleton()); }
  openCounter() { throw new Error('Not implemented'); }
  async transactionAsync(cb) { return await cb(); }
  async clear() { this._c = { map: {}, set: {}, mm: {}, arr: {}, sg: {} }; }
  delete() { this.clear(); return Promise.resolve(); }
  estimateSize() { return Promise.resolve({ mappingSize: 0, physicalFileSize: 0, actualSize: 0, numItems: 0 }); }
  close() { return Promise.resolve(); }
  backupTo() { throw new Error('Not implemented'); }

  // --- Snapshot Persistence ---

  static _serVal(v) {
    if (v instanceof Uint8Array) return { __u8: Array.from(v) };
    if (typeof v === 'bigint') return { __bi: v.toString() };
    return v;
  }

  static _desVal(v) {
    if (v && typeof v === 'object') {
      if (v.__u8) return new Uint8Array(v.__u8);
      if (v.__bi !== undefined) return BigInt(v.__bi);
    }
    return v;
  }

  serialize() {
    const S = MemoryAztecStore._serVal;
    const snap = { map: {}, set: {}, mm: {}, arr: {}, sg: {} };

    for (const [n, m] of Object.entries(this._c.map)) {
      const entries = {};
      for (const [k, v] of m._d.entries()) entries[k] = S(v);
      snap.map[n] = entries;
    }

    for (const [n, s] of Object.entries(this._c.set)) {
      snap.set[n] = [...s._m._d.keys()];
    }

    for (const [n, mm] of Object.entries(this._c.mm)) {
      const entries = {};
      for (const [k, arr] of mm._d.entries()) entries[k] = arr.map(S);
      snap.mm[n] = entries;
    }

    for (const [n, a] of Object.entries(this._c.arr)) {
      snap.arr[n] = a._d.map(S);
    }

    for (const [n, sg] of Object.entries(this._c.sg)) {
      if (sg._v !== undefined) snap.sg[n] = S(sg._v);
    }

    return JSON.stringify(snap);
  }

  static deserialize(json) {
    const D = MemoryAztecStore._desVal;
    const store = new MemoryAztecStore();
    const snap = JSON.parse(json);

    for (const [n, entries] of Object.entries(snap.map || {})) {
      const map = store.openMap(n);
      for (const [k, v] of Object.entries(entries)) map._d.set(k, D(v));
    }

    for (const [n, keys] of Object.entries(snap.set || {})) {
      const set = store.openSet(n);
      for (const k of keys) set._m._d.set(k, true);
    }

    for (const [n, entries] of Object.entries(snap.mm || {})) {
      const mm = store.openMultiMap(n);
      for (const [k, arr] of Object.entries(entries)) mm._d.set(k, arr.map(D));
    }

    for (const [n, arr] of Object.entries(snap.arr || {})) {
      const a = store.openArray(n);
      a._d = arr.map(D);
    }

    for (const [n, v] of Object.entries(snap.sg || {})) {
      const sg = store.openSingleton(n);
      sg._v = D(v);
    }

    return store;
  }
}

// --- Browser-compatible SponsoredFPC setup ---

async function setupSponsoredFPC(walletInstance) {
  console.log("[PXE] SponsoredFPC: Step 2a -- importing SponsoredFPCContract artifact...");
  const t2a = Date.now();
  const { SponsoredFPCContract } = await import("@aztec/noir-contracts.js/SponsoredFPC");
  console.log(`[PXE] SponsoredFPC: Step 2a OK (${Date.now() - t2a}ms)`);

  console.log("[PXE] SponsoredFPC: Step 2b -- getContractInstanceFromInstantiationParams (WASM)...");
  const t2b = Date.now();
  const fpcInstance = await getContractInstanceFromInstantiationParams(
    SponsoredFPCContract.artifact,
    { salt: new Fr(0) },
  );
  console.log(`[PXE] SponsoredFPC: Step 2b OK (${Date.now() - t2b}ms)`);

  console.log("[PXE] SponsoredFPC: Step 2c -- registerContract...");
  const t2c = Date.now();
  await walletInstance.registerContract(fpcInstance, SponsoredFPCContract.artifact);
  console.log(`[PXE] SponsoredFPC: Step 2c OK (${Date.now() - t2c}ms)`);

  return {
    instance: fpcInstance,
    paymentMethod: new SponsoredFeePaymentMethod(fpcInstance.address),
  };
}

// --- State ---

let wallet = null;       // EmbeddedWallet instance (wraps PXE)
let nodeClient = null;   // AztecNode client (for wallet-sdk protocol)
let kvStore = null;       // MemoryAztecStore reference (iOS only — for snapshot persistence)
let pxeReady = false;
let initError = null;
let initInProgress = false; // Guard: prevent concurrent messages during PXE_INIT
let initStep = "";          // Current init step description for UI progress

// Multi-account support: address → { manager, wallet (AccountWithSecretKey) }
const accountWallets = new Map();
let activeAddress = null;

// WalletConnect
let wcClient = null;

// --- Progress Reporting (JS → Swift UI) ---
function reportProgress(message) {
  try {
    if (typeof window !== 'undefined' && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pxeEvent) {
      window.webkit.messageHandlers.pxeEvent.postMessage(JSON.stringify({
        type: "PROGRESS",
        message: message || null
      }));
    }
  } catch (e) { /* ignore — non-iOS env */ }
}

function getActiveWallet() {
  if (!activeAddress) return null;
  return accountWallets.get(activeAddress)?.wallet || null;
}

function getActiveManager() {
  if (!activeAddress) return null;
  return accountWallets.get(activeAddress)?.manager || null;
}

// --- WalletConnect Request Handler ---

async function handleWcRequest(method, params) {
  const activeWallet = getActiveWallet();
  switch (method) {
    case "aztec_getAccounts":
      return { accounts: Array.from(accountWallets.keys()) };
    case "aztec_getChainInfo":
      return { chainId: "aztec:testnet", nodeUrl: wallet?.getNodeUrl?.() || "" };
    case "aztec_sendTx":
    case "aztec_signTransaction": {
      if (!activeWallet) throw new Error("No active wallet");
      // Forward to wallet-sdk handleWalletMethod
      const result = await handleWalletMethod(method === "aztec_sendTx" ? "sendTx" : "proveTx", params);
      return result;
    }
    case "aztec_createAuthWit": {
      if (!activeWallet) throw new Error("No active wallet");
      const result = await handleWalletMethod("createAuthWit", params);
      return result;
    }
    case "aztec_simulateTx": {
      if (!activeWallet) throw new Error("No active wallet");
      const result = await handleWalletMethod("simulateTx", params);
      return result;
    }
    default:
      throw new Error(`Unsupported WC method: ${method}`);
  }
}

// --- Browser P256 Auth Witness Provider ---

class BrowserP256AuthWitnessProvider {
  constructor(privateKeyBase64) {
    this._pkcs8Base64 = privateKeyBase64;
  }

  async createAuthWit(messageHash) {
    console.log(`[AuthWit] createAuthWit called`);

    // Decode base64 → PKCS8 Uint8Array
    const binaryStr = atob(this._pkcs8Base64);
    const pkcs8Bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) {
      pkcs8Bytes[i] = binaryStr.charCodeAt(i);
    }
    // PKCS8 key imported for ECDSA P-256 signing

    // Import P256 key using browser WebCrypto (extractable for debug)
    let key;
    try {
      key = await crypto.subtle.importKey(
        "pkcs8",
        pkcs8Bytes,
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign"],
      );
      // Key imported OK
    } catch (e) {
      console.error(`[AuthWit] Key import FAILED: ${e.message}`);
      throw e;
    }

    // Sign: WebCrypto SHA-256 hashes internally, matching Noir contract's sha256(outer_hash)
    const hashBytes = messageHash.toBuffer();
    // Sign the message hash with ECDSA P-256

    let sigRaw;
    try {
      sigRaw = new Uint8Array(
        await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          key,
          hashBytes,
        ),
      );
      // Signature obtained (64 bytes: r || s)
    } catch (e) {
      console.error(`[AuthWit] Signing FAILED: ${e.message}`);
      throw e;
    }

    // Low-S normalization: Noir's verify_ecdsa_p256 requires s ≤ n/2.
    // WebCrypto doesn't normalize, so ~50% of signatures have high-S → circuit rejects.
    // P-256 order n = FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
    const P256_N = [
      0xFF,0xFF,0xFF,0xFF,0x00,0x00,0x00,0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
      0xBC,0xE6,0xFA,0xAD,0xA7,0x17,0x9E,0x84,0xF3,0xB9,0xCA,0xC2,0xFC,0x63,0x25,0x51,
    ];
    const P256_HALF_N = [
      0x7F,0xFF,0xFF,0xFF,0x80,0x00,0x00,0x00,0x7F,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
      0xDE,0x73,0x7D,0x56,0xD3,0x8B,0xCF,0x42,0x79,0xDC,0xE5,0x61,0x7E,0x31,0x92,0xA8,
    ];

    // Compare s (bytes 32-63) against half_n
    const sBuf = sigRaw.slice(32, 64);
    let sIsHigh = false;
    for (let i = 0; i < 32; i++) {
      if (sBuf[i] > P256_HALF_N[i]) { sIsHigh = true; break; }
      if (sBuf[i] < P256_HALF_N[i]) { break; }
    }

    if (sIsHigh) {
      // s' = n - s  (big-endian subtraction)
      const newS = new Uint8Array(32);
      let borrow = 0;
      for (let i = 31; i >= 0; i--) {
        const diff = P256_N[i] - sBuf[i] - borrow;
        newS[i] = diff < 0 ? diff + 256 : diff;
        borrow = diff < 0 ? 1 : 0;
      }
      sigRaw.set(newS, 32);
      console.log(`[AuthWit] Low-S normalized`);
    } else {
      // s is already low-S
    }

    // Pack 64-byte P256 signature (r || s) into AuthWitness fields as Fr elements
    const witnessFields = [];
    for (let i = 0; i < 64; i++) {
      witnessFields.push(new Fr(sigRaw[i]));
    }
    // 64 Fr fields packed into AuthWitness

    return new AuthWitness(messageHash, witnessFields);
  }
}

// --- Browser Celari Account Contract ---

class BrowserCelariPasskeyAccountContract extends DefaultAccountContract {
  constructor(pubKeyX, pubKeyY, privateKeyBase64) {
    super();
    this._pubKeyX = pubKeyX;
    this._pubKeyY = pubKeyY;
    this._privateKeyBase64 = privateKeyBase64;
  }

  async getContractArtifact() {
    return CelariPasskeyAccountArtifact;
  }

  async getInitializationFunctionAndArgs() {
    return {
      constructorName: "constructor",
      constructorArgs: [this._pubKeyX, this._pubKeyY],
    };
  }

  getAuthWitnessProvider(_address) {
    return new BrowserP256AuthWitnessProvider(this._privateKeyBase64);
  }
}

// --- PXE Initialization ---

async function initPXE(nodeUrl) {
  initStep = "Connecting to Aztec node...";
  reportProgress("Aztec node'a bağlanılıyor...");
  console.log(`[PXE] Connecting to ${nodeUrl}...`);
  const node = createAztecNodeClient(nodeUrl);
  nodeClient = node; // Store for wallet-sdk protocol

  // iOS WKWebView has no Worker support — but we MUST enable proving.
  // Fake proofs (proverEnabled=false) are rejected by the testnet node.
  // BBLazyPrivateKernelProver works on the main thread (slow but functional).
  const isIOS = typeof window !== "undefined" && window.__CELARI_IOS === true;
  const proverEnabled = true; // Always true — testnet requires real proofs
  if (isIOS) console.log("[PXE] iOS detected — proverEnabled: true (main-thread proving, no Workers)");

  // ── Inline createPXE steps with granular logging ──
  // (Replaces EmbeddedWallet.create to diagnose which step hangs in WKWebView)
  const { createPXE, getPXEConfig } = await import("@aztec/pxe/client/lazy");
  const pxeConfig = Object.assign(getPXEConfig(), { proverEnabled });

  initStep = "Fetching L1 contract addresses...";
  console.log("[PXE] Step A: getL1ContractAddresses (network)...");
  const t_l1 = Date.now();
  const l1Contracts = await Promise.race([
    node.getL1ContractAddresses(),
    new Promise((_, rej) => setTimeout(() => rej(new Error("getL1ContractAddresses timed out after 30s — is the Aztec node reachable?")), 30000)),
  ]);
  console.log("[PXE] Step A: OK (" + (Date.now() - t_l1) + "ms)");

  const configWithContracts = { ...pxeConfig, l1Contracts };

  initStep = "Creating local database...";
  console.log("[PXE] Step B: Creating KV store...");
  const t_store = Date.now();
  let store;
  // Use in-memory store for both iOS and Chrome — IndexedDB causes
  // "transaction not active" errors during async SDK operations in Chrome extensions.
  // Data re-syncs each session anyway.
  console.log("[PXE] Step B: Using in-memory KV store");
  store = new MemoryAztecStore();
  kvStore = store;
  if (l1Contracts.rollupAddress) {
    const rollupSingleton = store.openSingleton('rollupAddress');
    await rollupSingleton.set(l1Contracts.rollupAddress.toString());
  }
  console.log("[PXE] Step B: In-memory store OK (" + (Date.now() - t_store) + "ms)");

  // iOS: Pre-initialize Barretenberg in direct WASM mode (no Workers).
  // WKWebView doesn't support Web Workers. Barretenberg.initSingleton() is cached —
  // by initializing first with BackendType.Wasm, the prover's later call to
  // initSingleton() reuses this no-Worker instance instead of trying to create Workers.
  // Pre-initialize Barretenberg in direct WASM mode (single-threaded).
  // Chrome offscreen documents have Worker restrictions similar to iOS WKWebView.
  console.log("[PXE] Step C0: Pre-initializing Barretenberg (direct WASM, no Workers)...");
  const t_bb = Date.now();
  const { Barretenberg, BackendType } = await import("@aztec/bb.js");
  await Barretenberg.initSingleton({ backend: BackendType.Wasm, threads: 1 });
  console.log("[PXE] Step C0: Barretenberg singleton ready (" + (Date.now() - t_bb) + "ms)");

  initStep = "Loading WASM prover engine...";
  reportProgress("WASM prover yükleniyor...");
  console.log("[PXE] Step C: WASMSimulator + Prover...");
  const t_sim = Date.now();
  const [{ WASMSimulator }, { BBLazyPrivateKernelProver }] = await Promise.race([
    Promise.all([
      import("@aztec/simulator/client"),
      import("@aztec/bb-prover/client/lazy"),
    ]),
    new Promise((_, rej) => setTimeout(() => rej(new Error("WASM prover import timed out after 90s")), 90000)),
  ]);
  const simulator = new WASMSimulator();
  const prover = new BBLazyPrivateKernelProver(simulator);
  console.log("[PXE] Step C: OK (" + (Date.now() - t_sim) + "ms)");

  initStep = "Loading protocol contracts...";
  console.log("[PXE] Step D: LazyProtocolContractsProvider...");
  const t_pcp = Date.now();
  const { LazyProtocolContractsProvider } = await Promise.race([
    import("@aztec/protocol-contracts/providers/lazy"),
    new Promise((_, rej) => setTimeout(() => rej(new Error("Protocol contracts import timed out after 30s")), 30000)),
  ]);
  const protocolContractsProvider = new LazyProtocolContractsProvider();
  console.log("[PXE] Step D: OK (" + (Date.now() - t_pcp) + "ms)");

  // Step E removed: PXE.create was creating a PXE that competed with EmbeddedWallet's internal PXE
  // for the same IndexedDB store, causing "delete range without transaction" errors on WKWebView.
  // EmbeddedWallet.create() below creates its own PXE using the shared store, simulator, and prover.

  initStep = "Starting PXE wallet engine...";
  reportProgress("PXE wallet başlatılıyor...");
  console.log("[PXE] Step E: Creating EmbeddedWallet (single PXE with shared store)...");
  const t_pxe = Date.now();
  wallet = await Promise.race([
    EmbeddedWallet.create(node, { pxeConfig, pxeOptions: { store, simulator, proverOrOptions: prover } }),
    new Promise((_, rej) => setTimeout(() => rej(new Error("EmbeddedWallet.create timed out after 4 min")), 240000)),
  ]);
  console.log("[PXE] Step E: OK (" + (Date.now() - t_pxe) + "ms) — EmbeddedWallet ready");

  // Override getAccountFromAddress so CelariPasskey accounts (custom contract)
  // are resolved via AccountManager instead of WalletDB (which only knows built-in types).
  const _origGetAccount = wallet.getAccountFromAddress.bind(wallet);
  wallet.getAccountFromAddress = async function (addr) {
    const entry = accountWallets.get(addr.toString());
    if (entry?.manager) {
      const acct = await entry.manager.getAccount();
      if (acct) return acct;
    }
    return _origGetAccount(addr);
  };

  const info = await Promise.race([
    wallet.getChainInfo(),
    new Promise((_, rej) => setTimeout(() => rej(new Error("getChainInfo timed out after 15s")), 15000)),
  ]);
  console.log(`[PXE] Connected — Chain ${info.chainId}, Protocol v${info.version}`);

  // NOTE: SponsoredFPC setup removed from init — it calls registerContract() which
  // involves getContractMetadata + WASM ops that block WKWebView's single-threaded JS.
  // Deploy already calls setupSponsoredFPC() at line 553, so this was redundant.

  // Pre-flight: check import.meta.url and WASM file accessibility
  console.log(`[PXE] Pre-flight: import.meta.url = ${import.meta.url}`);
  try {
    // Check if WASM files are reachable via fetch (file:// polyfill in shim)
    const wasmUrl = new URL("noirc_abi_wasm_bg.wasm", import.meta.url).href;
    console.log(`[PXE] Pre-flight: WASM URL = ${wasmUrl}`);
    const resp = await fetch(wasmUrl);
    console.log(`[PXE] Pre-flight: WASM fetch status=${resp.status}, size=${resp.headers.get('content-length') || '?'}`);
    if (resp.ok) {
      const buf = await resp.arrayBuffer();
      console.log(`[PXE] Pre-flight: WASM loaded OK — ${buf.byteLength} bytes ✓`);
    } else {
      console.warn(`[PXE] Pre-flight: WASM fetch failed — status ${resp.status}`);
    }
  } catch (wasmErr) {
    console.warn(`[PXE] Pre-flight: WASM check error: ${wasmErr?.message?.slice(0, 150)}`);
  }

  reportProgress(null);
  pxeReady = true;
  return { status: "ready", chainId: info.chainId.toString() };
}

// --- Account Registration ---

async function registerAccount(data) {
  if (!wallet) throw new Error("PXE not initialized");

  const { publicKeyX, publicKeyY, secretKey, salt, privateKeyPkcs8 } = data;

  // Register account with CelariPasskey contract

  const pubKeyXBuf = hexToBuffer(publicKeyX);
  const pubKeyYBuf = hexToBuffer(publicKeyY);

  const accountContract = new BrowserCelariPasskeyAccountContract(
    pubKeyXBuf,
    pubKeyYBuf,
    privateKeyPkcs8,
  );

  const secretKeyFr = Fr.fromHexString(secretKey);
  const manager = await AccountManager.create(wallet, secretKeyFr, accountContract, Fr.fromHexString(salt));

  const address = manager.address.toString();
  const accountAddr = AztecAddress.fromString(address);

  // Register the account contract with the PXE (critical for re-registration after restart).
  try {
    console.log(`[PXE] Registering contract instance with PXE...`);
    const instance = manager.getInstance();
    await wallet.registerContract(instance, CelariPasskeyAccountArtifact, secretKeyFr);
    console.log(`[PXE] Contract registered OK`);
  } catch (err) {
    console.warn(`[PXE] Contract registration warning (may already exist): ${err.message}`);
  }

  // Force PXE to discover the account contract's notes (especially signing_public_key).
  try {
    console.log(`[PXE] Triggering note sync for account contract...`);
    const t0 = Date.now();
    await wallet.pxe.debug.getNotes({ contractAddress: accountAddr });
    console.log(`[PXE] Note sync completed OK (${Date.now() - t0}ms)`);
  } catch (err) {
    console.warn(`[PXE] Note sync warning (non-fatal): ${err.message}`);
  }

  // The Proxy is needed so getAddress() returns the CelariPasskey address.
  const acctWallet = new Proxy(wallet, {
    get(target, prop) {
      // Address-related methods → from the registered account
      if (prop === 'getAddress') {
        return () => AztecAddress.fromString(address);
      }
      // Everything else → EmbeddedWallet (PXE + internal account dispatch)
      const val = target[prop];
      return typeof val === 'function' ? val.bind(target) : val;
    }
  });

  accountWallets.set(address, { manager, wallet: acctWallet });
  if (!activeAddress) activeAddress = address;

  console.log(`[PXE] Account registered: ${address.slice(0, 22)}... (total: ${accountWallets.size})`);
  return { address };
}

// --- Transfer ---

async function executeTransfer(data) {
  const acctWallet = getActiveWallet();
  if (!acctWallet) throw new Error("No account registered in PXE");

  const { to, amount, tokenAddress, transferType = "private" } = data;

  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");
  const tokenAddr = AztecAddress.fromString(tokenAddress);
  const recipientAddr = AztecAddress.fromString(to);
  const rawAmount = BigInt(Math.floor(parseFloat(amount) * 1e18));

  // Ensure token contract is registered (in-memory PXE has no persistence)
  const { contractInstance: existing } = await wallet.getContractMetadata(tokenAddr);
  if (!existing && nodeClient) {
    console.log(`[PXE] Transfer: registering token contract from node...`);
    const onChainInstance = await nodeClient.getContract(tokenAddr);
    if (onChainInstance) {
      await wallet.registerContract(onChainInstance, TokenContract.artifact);
      console.log(`[PXE] Transfer: token contract registered OK`);
    }
  }

  reportProgress("Token kontratı hazırlanıyor...");
  const token = await TokenContract.at(tokenAddr, acctWallet);
  reportProgress("Fee ödeme ayarlanıyor...");
  const { paymentMethod } = await setupSponsoredFPC(acctWallet);
  const senderAddr = acctWallet.getAddress();

  reportProgress("Transfer tx gönderiliyor...");
  console.log(`[PXE] ${transferType} transfer: ${amount} to ${to.slice(0, 16)}...`);
  console.log(`[PXE] senderAddr: ${senderAddr.toString().slice(0, 22)}...`);
  console.log(`[PXE] acctWallet type: ${acctWallet?.constructor?.name || 'Proxy'}`);
  console.log(`[PXE] acctWallet.getAddress(): ${acctWallet.getAddress().toString().slice(0, 22)}...`);

  let sendResult;
  const sendOpts = { from: senderAddr, fee: { paymentMethod }, wait: { timeout: 600_000 } };
  reportProgress("Blok onayı bekleniyor...");
  switch (transferType) {
    case "private":
      // Private-to-private: caller's private notes → recipient's private note
      sendResult = await token.methods
        .transfer(recipientAddr, rawAmount)
        .send(sendOpts);
      break;

    case "public":
      // Public-to-public: transfer_in_public(from, to, amount, authwit_nonce)
      sendResult = await token.methods
        .transfer_in_public(senderAddr, recipientAddr, rawAmount, 0)
        .send(sendOpts);
      break;

    case "shield":
      // Public → Private: move caller's public balance into recipient's private notes
      sendResult = await token.methods
        .transfer_to_private(recipientAddr, rawAmount)
        .send(sendOpts);
      break;

    case "unshield":
      // Private → Public: transfer_to_public(from, to, amount, authwit_nonce)
      sendResult = await token.methods
        .transfer_to_public(senderAddr, recipientAddr, rawAmount, 0)
        .send(sendOpts);
      break;

    default:
      throw new Error(`Unknown transfer type: ${transferType}`);
  }

  // In 4.1.0-rc.2, send() with wait returns { receipt: TxReceipt, ...OffchainOutput }
  const receipt = sendResult.receipt;
  console.log(`[PXE] Tx: ${receipt.txHash.toString().slice(0, 22)}...`);
  console.log(`[PXE] Confirmed! Block ${receipt.blockNumber}`);

  reportProgress(null);
  return {
    txHash: receipt.txHash.toString(),
    blockNumber: receipt.blockNumber?.toString() || "",
  };
}

// --- Balance Query ---

let balanceFromAddress = null;

async function ensureBalanceAccount() {
  if (balanceFromAddress) return;
  try {
    // Always create a dedicated Schnorr test account for balance queries.
    // Real passkey accounts are incompatible with enableSimulatedSimulations().
    console.log("[PXE] Balance: creating test account for balance queries...");
    const mgr = await wallet.createSchnorrAccount(Fr.random(), Fr.random());
    balanceFromAddress = mgr.address;
    console.log(`[PXE] Balance: test account created — ${balanceFromAddress.toString().slice(0, 20)}...`);
  } catch (e) {
    console.warn(`[PXE] Balance: test account setup failed: ${e.message?.slice(0, 80)}`);
  }
}

async function getBalances(data) {
  if (!wallet) throw new Error("PXE not initialized");

  const { address, tokens } = data;
  if (!tokens || tokens.length === 0) return [];

  // Ensure a test account exists for balance queries
  // (EmbeddedWallet in 4.1.0-rc.2 handles simulation internally via simulateViaEntrypoint)
  await ensureBalanceAccount();

  const results = [];
  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");

  for (const tk of tokens) {
    try {
      const tokenAddr = AztecAddress.fromString(tk.address);
      const addr = AztecAddress.fromString(address);

      console.log(`[PXE] Balance: querying ${tk.symbol} at ${tk.address.slice(0, 20)}... for ${address.slice(0, 20)}...`);

      // Step 0: Ensure token contract is registered with PXE
      const { contractInstance: existing } = await wallet.getContractMetadata(tokenAddr);
      if (!existing && nodeClient) {
        console.log(`[PXE] Balance: registering ${tk.symbol} contract from node...`);
        const onChainInstance = await nodeClient.getContract(tokenAddr);
        if (onChainInstance) {
          await wallet.registerContract(onChainInstance, TokenContract.artifact);
          console.log(`[PXE] Balance: registered ${tk.symbol} contract OK`);
        } else {
          console.warn(`[PXE] Balance: contract ${tk.symbol} not found on-chain`);
        }
      }

      // Step 1: Get contract instance
      const tokenForPublic = await TokenContract.at(tokenAddr, wallet);

      // Step 2: Query public balance (from: test account to avoid getAccountFromAddress crash)
      // In 4.1.0-rc.2, simulate() returns SimulationResult { result, stats?, ... }
      console.log(`[PXE] Balance: querying public balance for ${tk.symbol}...`);
      const publicSim = await tokenForPublic.methods.balance_of_public(addr).simulate({ from: balanceFromAddress });
      const publicBal = publicSim.result !== undefined ? publicSim.result : publicSim;
      console.log(`[PXE] Balance: public balance OK — ${publicBal}`);
      const publicBalance = Number(publicBal) / 10 ** tk.decimals;

      let privateBalance = 0;
      if (getActiveWallet()) {
        try {
          // Use EmbeddedWallet (not AccountWithSecretKey) — it has simulateViaEntrypoint()
          // needed for unconstrained balance_of_private queries
          const tokenForPrivate = await TokenContract.at(tokenAddr, wallet);
          const privateSim = await tokenForPrivate.methods.balance_of_private(addr).simulate({ from: balanceFromAddress });
          const privateBal = privateSim.result !== undefined ? privateSim.result : privateSim;
          privateBalance = Number(privateBal) / 10 ** tk.decimals;
          console.log(`[PXE] Balance: private balance OK — ${privateBal}`);
        } catch (e) {
          console.warn(`[PXE] Private balance unavailable for ${tk.symbol}: ${e.message?.slice(0, 80)}`);
        }
      }

      const fmt = (v) => v.toLocaleString("en-US", { maximumFractionDigits: 2 });

      results.push({
        name: tk.name,
        symbol: tk.symbol,
        address: tk.address,
        publicBalance: fmt(publicBalance),
        privateBalance: fmt(privateBalance),
        balance: fmt(publicBalance + privateBalance),
        usdValue: "0.00",
      });
    } catch (e) {
      console.warn(`[PXE] Balance query FAILED for ${tk.symbol}: ${e.message?.slice(0, 200)}`);
      if (e.stack) console.warn(`[PXE] Balance error stack: ${e.stack.slice(0, 500)}`);
      results.push({
        name: tk.name,
        symbol: tk.symbol,
        publicBalance: "—",
        privateBalance: "—",
        balance: "—",
        usdValue: "0.00",
      });
    }
  }

  // In 4.1.0-rc.2, EmbeddedWallet handles simulation mode internally — no toggle needed
  return { balances: results };
}

// --- Client-Side Account Deploy ---

async function generateP256KeyPairBrowser() {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pubRaw = new Uint8Array(await crypto.subtle.exportKey("raw", keyPair.publicKey));
  const pubKeyX = "0x" + Array.from(pubRaw.slice(1, 33))
    .map(b => b.toString(16).padStart(2, "0")).join("");
  const pubKeyY = "0x" + Array.from(pubRaw.slice(33, 65))
    .map(b => b.toString(16).padStart(2, "0")).join("");
  const privateKeyPkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
  );
  const pkcs8Base64 = btoa(String.fromCharCode(...privateKeyPkcs8));
  return { pubKeyX, pubKeyY, privateKeyPkcs8: pkcs8Base64 };
}

async function deployAccountClientSide(data) {
  console.log(`[PXE] >>> deployAccountClientSide ENTERED`);
  if (!wallet) throw new Error("PXE not initialized");

  // Force PXE block sync before deploy to get fresh anchor block header
  console.log("[PXE] Deploy Step 0: Syncing PXE block state...");
  const t0 = Date.now();
  try {
    if (wallet.pxe.blockStateSynchronizer?.sync) {
      await wallet.pxe.blockStateSynchronizer.sync();
      console.log(`[PXE] Deploy Step 0: block sync OK (${Date.now() - t0}ms)`);
    } else {
      // Fallback: just fetch latest header to confirm connectivity
      const header = await wallet.pxe.getSyncedBlockHeader();
      console.log(`[PXE] Deploy Step 0: header fetched OK (${Date.now() - t0}ms), timestamp: ${header?.globalVariables?.timestamp}`);
    }
  } catch (e) {
    console.warn(`[PXE] Deploy Step 0: sync failed (${Date.now() - t0}ms) -- ${e.message}, continuing anyway...`);
  }

  const { publicKeyX, publicKeyY, privateKeyPkcs8 } = data;
  console.log(`[PXE] pubKeyX: ${publicKeyX?.slice(0,16)}..., pkcs8: ${privateKeyPkcs8 ? 'present' : 'MISSING'}`);

  const secretKey = Fr.random();
  const salt = Fr.random();

  const accountContract = new BrowserCelariPasskeyAccountContract(
    hexToBuffer(publicKeyX),
    hexToBuffer(publicKeyY),
    privateKeyPkcs8,
  );

  // Step 1: Create account
  console.log("[PXE] Deploy Step 1: wallet.createAccount()...");
  reportProgress("Hesap oluşturuluyor...");
  const t1 = Date.now();
  let manager;
  try {
    manager = await Promise.race([
      AccountManager.create(wallet, secretKey, accountContract, salt),
      new Promise((_, rej) => setTimeout(() => rej(new Error("AccountManager.create timed out after 3 min")), 180000)),
    ]);
    console.log(`[PXE] Deploy Step 1: OK (${Date.now() - t1}ms) -- address: ${manager.address.toString().slice(0, 22)}...`);
  } catch (e) {
    console.error(`[PXE] Deploy Step 1: FAILED (${Date.now() - t1}ms) -- ${e.message}`);
    throw e;
  }

  const address = manager.address;

  // Step 1b: Register account + contract with PXE (v4.0.4 requirement)
  console.log("[PXE] Deploy Step 1b: registerAccount + registerContract...");
  const t1b = Date.now();
  try {
    const instance = manager.getInstance();
    await wallet.registerContract(instance, CelariPasskeyAccountArtifact, secretKey);
    console.log(`[PXE] Deploy Step 1b: OK (${Date.now() - t1b}ms)`);
  } catch (e) {
    console.error(`[PXE] Deploy Step 1b: FAILED (${Date.now() - t1b}ms) -- ${e.message}`);
    throw e;
  }

  // Step 2: SponsoredFPC
  reportProgress("Fee ödeme ayarlanıyor...");
  console.log("[PXE] Deploy Step 2: setupSponsoredFPC...");
  const t2 = Date.now();
  let paymentMethod;
  try {
    const fpc = await Promise.race([
      setupSponsoredFPC(wallet),
      new Promise((_, rej) => setTimeout(() => rej(new Error("setupSponsoredFPC timed out after 3 min")), 180000)),
    ]);
    paymentMethod = fpc.paymentMethod;
    console.log(`[PXE] Deploy Step 2: OK (${Date.now() - t2}ms)`);
  } catch (e) {
    console.error(`[PXE] Deploy Step 2: FAILED (${Date.now() - t2}ms) -- ${e.message}`);
    throw e;
  }

  // Step 3: getDeployMethod
  reportProgress("Deploy metodu hazırlanıyor...");
  console.log("[PXE] Deploy Step 3: getDeployMethod...");
  const t3 = Date.now();
  const deployMethod = await manager.getDeployMethod();
  console.log(`[PXE] Deploy Step 3: OK (${Date.now() - t3}ms)`);

  // Patch: force external fee path (deployer=undefined) while keeping from=ZERO for SignerlessAccount
  const _origConvert = deployMethod.convertDeployOptionsToRequestOptions.bind(deployMethod);
  deployMethod.convertDeployOptionsToRequestOptions = (opts) => {
    const r = _origConvert(opts);
    r.deployer = undefined;
    return r;
  };

  // Step 4: send + wait (prove is the slowest part — may take minutes in WASM)
  reportProgress("Deploy tx gönderiliyor...");
  console.log("[PXE] Deploy Step 4: deployMethod.send() + wait...");
  console.log("[PXE] (proving may take several minutes in WKWebView WASM...)");
  const t4 = Date.now();
  // Log periodic progress while waiting
  const progressTimer = setInterval(() => {
    const elapsed = Math.round((Date.now() - t4) / 1000);
    console.log(`[PXE] Deploy Step 4: still running... ${elapsed}s elapsed`);
    reportProgress(`Deploy tx işleniyor... (${elapsed}s)`);
  }, 15000);
  let txReceipt;
  try {
    const sendResult = await deployMethod.send({
      from: AztecAddress.ZERO,
      fee: { paymentMethod },
      wait: { timeout: 900_000, returnReceipt: true },
    });
    clearInterval(progressTimer);
    // In 4.1.0-rc.2, send() with wait returns { receipt: TxReceipt, ...OffchainOutput }
    txReceipt = sendResult.receipt;
    console.log(`[PXE] Deploy Step 4: txHash: ${txReceipt.txHash.toString().slice(0, 22)}... Deployed! Block ${txReceipt.blockNumber} (${Date.now() - t4}ms)`);
  } catch (e) {
    clearInterval(progressTimer);
    console.error(`[PXE] Deploy Step 4: FAILED (${Date.now() - t4}ms) -- ${e.message}`);
    throw e;
  }

  reportProgress("Hesap deploy edildi ✓");

  // Store in multi-account map
  const addrStr = address.toString();
  const acctWallet = new Proxy(wallet, {
    get(target, prop) {
      if (prop === 'getAddress') {
        return () => AztecAddress.fromString(addrStr);
      }
      const val = target[prop];
      return typeof val === 'function' ? val.bind(target) : val;
    }
  });
  accountWallets.set(addrStr, { manager, wallet: acctWallet });
  activeAddress = addrStr;

  reportProgress(null);
  return {
    address: addrStr,
    secretKey: secretKey.toString(),
    salt: salt.toString(),
    txHash: txReceipt.txHash.toString(),
    blockNumber: txReceipt.blockNumber?.toString() || "",
  };
}

// --- Faucet (mint CLR via admin inside extension) ---

let faucetAdmin = null;   // { adminAddr, clrToken, tokenAddress }
const FAUCET_AMOUNT = 100n * 10n ** 18n; // 100 CLR
const FAUCET_COOLDOWN_MS = 2 * 60 * 1000; // 2 minutes (dev/test)
let lastFaucetTime = 0;

// Restore faucet rate limit via background.js
(async () => {
  try {
    const res = await new Promise((resolve) => {
      chrome.runtime.sendMessage({ type: "GET_FAUCET_RATE" }, (r) => {
        void chrome.runtime.lastError;
        resolve(r);
      });
    });
    if (res?.lastFaucetTime) lastFaucetTime = res.lastFaucetTime;
  } catch {}
})();

async function executeFaucet(data) {
  if (!wallet) throw new Error("PXE not initialized");

  const { address } = data;
  if (!address) throw new Error("Missing address");

  // Rate limit (persisted across SW restarts)
  if (Date.now() - lastFaucetTime < FAUCET_COOLDOWN_MS) {
    const remainingMin = Math.ceil((FAUCET_COOLDOWN_MS - (Date.now() - lastFaucetTime)) / 60000);
    throw new Error(`Rate limited. Try again in ${remainingMin} minutes.`);
  }

  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");
  const { paymentMethod } = await setupSponsoredFPC(wallet);

  // Try loading cached admin via background.js (offscreen has no chrome.storage)
  if (!faucetAdmin) {
    try {
      const cached = await new Promise((resolve) => {
        chrome.runtime.sendMessage({ type: "GET_FAUCET_CACHE" }, (res) => {
          void chrome.runtime.lastError;
          resolve(res?.data || null);
        });
      });
      if (cached?.secret && cached?.tokenAddress) {
        const mgr = await wallet.createSchnorrAccount(
          Fr.fromHexString(cached.secret),
          Fr.fromHexString(cached.salt),
        );
        const adminAddr = mgr.address;
        const tokenAddr = AztecAddress.fromString(cached.tokenAddress);

        const clrToken = await TokenContract.at(tokenAddr, wallet);
        faucetAdmin = { adminAddr, clrToken, tokenAddress: cached.tokenAddress };
        console.log(`[PXE] Faucet admin loaded from cache: ${adminAddr.toString().slice(0, 22)}...`);
        console.log(`[PXE] Token contract verified on-chain ✓`);
      }
    } catch (e) {
      console.warn(`[PXE] Faucet cache load failed: ${e.message?.slice(0, 60)}`);
      faucetAdmin = null;
    }
  }

  // First-time setup: deploy admin + CLR token
  if (!faucetAdmin) {
    console.log("[PXE] Faucet first-time setup: deploying admin + CLR token...");
    reportProgress("Faucet kurulumu başlatılıyor...");

    const secret = Fr.random();
    const salt = Fr.random();
    const mgr = await wallet.createSchnorrAccount(secret, salt);
    const adminAddr = mgr.address;

    console.log(`[PXE] Deploying faucet admin ${adminAddr.toString().slice(0, 22)}...`);
    reportProgress("Admin hesap deploy ediliyor... (1/3)");
    reportProgress("Admin tx onayı bekleniyor... (1/3)");
    await (await mgr.getDeployMethod()).send({
      from: AztecAddress.ZERO,
      fee: { paymentMethod },
      wait: { timeout: 600_000 },
    });
    console.log("[PXE] Faucet admin deployed!");

    // Retry token deploy — PXE block stream may not have synced the admin's
    // signing key note yet (getTxReceipt checks the node, not PXE local state).
    console.log("[PXE] Deploying CLR token...");
    reportProgress("CLR Token deploy ediliyor... (2/3)");
    let deployedToken;
    for (let attempt = 0; attempt < 6; attempt++) {
      try {
        const tokenDeploy = TokenContract.deploy(wallet, adminAddr, "Celari Token", "CLR", 18);
        const deployResult = await tokenDeploy.send({ from: adminAddr, fee: { paymentMethod }, wait: { timeout: 600_000 } });
        // In 4.1.0-rc.2, DeployMethod.send() returns { contract, receipt, ...OffchainOutput }
        deployedToken = deployResult.contract;
        break;
      } catch (e) {
        if (attempt < 5 && e.message?.includes("Failed to get a note")) {
          console.log(`[PXE] Admin note not synced yet — retrying in 5s (attempt ${attempt + 1}/6)...`);
          await new Promise(r => setTimeout(r, 5000));
        } else {
          throw e;
        }
      }
    }
    const tokenAddress = deployedToken.address.toString();

    const clrToken = deployedToken;
    faucetAdmin = { adminAddr, clrToken, tokenAddress };

    // Cache via background.js (offscreen has no chrome.storage)
    chrome.runtime.sendMessage({
      type: "SET_FAUCET_CACHE",
      data: {
        secret: secret.toString(),
        salt: salt.toString(),
        tokenAddress,
        adminAddress: adminAddr.toString(),
      },
    }, () => void chrome.runtime.lastError);

    console.log(`[PXE] Faucet setup complete! Token: ${tokenAddress.slice(0, 22)}...`);
  }

  // Mint to target address
  const to = AztecAddress.fromString(address);
  console.log(`[PXE] Faucet: minting 100 CLR to ${address.slice(0, 22)}...`);
  reportProgress("100 CLR mint ediliyor... (3/3)");

  reportProgress("Mint tx onayı bekleniyor... (3/3)");
  const mintResult = await faucetAdmin.clrToken.methods
    .mint_to_public(to, FAUCET_AMOUNT)
    .send({ from: faucetAdmin.adminAddr, fee: { paymentMethod }, wait: { timeout: 600_000 } });
  const mintReceipt = mintResult.receipt;

  lastFaucetTime = Date.now();
  // Persist rate limit via background.js
  chrome.runtime.sendMessage({ type: "SET_FAUCET_RATE", lastFaucetTime }, () => void chrome.runtime.lastError);

  console.log(`[PXE] Faucet done! Block ${mintReceipt.blockNumber}`);
  reportProgress(null); // Clear status bar
  return {
    txHash: mintReceipt.txHash.toString(),
    blockNumber: mintReceipt.blockNumber?.toString() || "",
    amount: "100",
    symbol: "CLR",
    tokenAddress: faucetAdmin.tokenAddress,
  };
}

// --- Sync Status ---

async function getSyncStatus() {
  if (!wallet) return { synced: false, pxeBlock: 0, nodeBlock: 0 };

  try {
    const nodeBlock = await wallet.getBlockNumber();
    return {
      synced: true,
      nodeBlock,
      accountCount: accountWallets.size,
      activeAddress,
    };
  } catch (e) {
    return { synced: false, error: e.message?.slice(0, 80) };
  }
}

// --- Sender Registration (for note discovery) ---

async function registerSender(senderAddress) {
  if (!wallet) throw new Error("PXE not initialized");
  await wallet.registerSender(AztecAddress.fromString(senderAddress));
  console.log(`[PXE] Sender registered: ${senderAddress.slice(0, 22)}...`);
  return { registered: true };
}

// --- Utilities ---

function hexToBuffer(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error(`Invalid hex string length: ${clean.length} (must be even)`);
  }
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// --- Wallet-SDK Method Dispatcher ---
// Handles standard Aztec wallet-sdk method calls from dApps.
// Delegates to acctWallet (AccountWithSecretKey) for account-scoped methods,
// and to wallet (EmbeddedWallet) for PXE-level methods.

async function handleWalletMethod(method, args) {
  if (!wallet) throw new Error("PXE not initialized");

  switch (method) {
    case "getAccounts":
      return Array.from(accountWallets.keys()).map(addr => ({
        item: AztecAddress.fromString(addr),
        alias: "",
      }));

    case "getChainInfo":
      return await wallet.getChainInfo();

    case "getAddressBook": {
      const senders = await wallet.getSenders();
      return senders.map(s => ({ item: s, alias: "" }));
    }

    case "registerSender":
      return await wallet.registerSender(args[0], args[1] || "");

    case "registerContract":
      return await wallet.registerContract(args[0], args[1], args[2]);

    case "getContractMetadata":
      return await wallet.getContractMetadata(args[0]);

    case "getContractClassMetadata":
      return await wallet.getContractClassMetadata(args[0], args[1]);

    case "getTxReceipt":
      return await wallet.getTxReceipt(args[0]);

    // Account-scoped methods: delegate to active account wallet
    case "simulateTx":
    case "sendTx":
    case "profileTx":
    case "createAuthWit":
    case "getPrivateEvents": {
      const acctWallet = getActiveWallet();
      if (!acctWallet) throw new Error("No account registered in PXE");
      if (typeof acctWallet[method] !== "function") {
        throw new Error(`Method ${method} not available on account wallet`);
      }
      return await acctWallet[method](...args);
    }

    // simulateUtility: unconstrained function calls — use EmbeddedWallet (has PXE methods)
    case "simulateUtility":
      return await wallet.simulateUtility(...args);

    case "batch": {
      const batchedMethods = args[0];
      const results = [];
      for (const m of batchedMethods) {
        const result = await handleWalletMethod(m.name, m.args);
        results.push({ name: m.name, result });
      }
      return results;
    }

    default:
      throw new Error(`Unsupported wallet method: ${method}`);
  }
}

// --- Message Handler ---

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  console.log(`[PXE] Handler received: type=${msg?.type}, keys=${msg ? Object.keys(msg).join(',') : 'null'}`);
  // Only process messages relayed through background.js (tagged with _target)
  if (!msg || !msg.type?.startsWith("PXE_") || msg._target !== "offscreen") return false;
  console.log(`[PXE] Processing ${msg.type}...`);

  const handle = async () => {
    try {
      // Guard: prevent any PXE operation while init is in progress (except status checks)
      if (initInProgress && msg.type !== "PXE_INIT" && msg.type !== "PXE_STATUS") {
        console.warn(`[PXE] Blocking ${msg.type} — PXE_INIT in progress`);
        return { error: "PXE still initializing — please wait" };
      }

      switch (msg.type) {
        case "PXE_INIT":
          if (initInProgress) return { error: "PXE_INIT already in progress" };
          initInProgress = true;
          initError = null;
          try {
            const result = await initPXE(msg.nodeUrl);
            return result;
          } catch (e) {
            initError = e?.message || String(e);
            console.error("[PXE] PXE_INIT failed:", initError);
            throw e;
          } finally {
            initInProgress = false;
          }

        case "PXE_STATUS":
          return {
            ready: pxeReady,
            error: initError,
            hasAccount: accountWallets.size > 0,
            accountCount: accountWallets.size,
            activeAddress,
            initializing: initInProgress,
            initStep,
          };

        case "PXE_REGISTER_ACCOUNT":
          return await registerAccount(msg.data);

        case "PXE_TRANSFER":
          return await executeTransfer(msg.data);

        case "PXE_BALANCES":
          return await getBalances(msg.data);

        case "PXE_FAUCET":
          return await executeFaucet(msg.data);

        // Client-side deploy
        case "PXE_GENERATE_KEYS":
          return await generateP256KeyPairBrowser();

        case "PXE_DEPLOY_ACCOUNT":
          return await deployAccountClientSide(msg.data);

        // Sync & note discovery
        case "PXE_SYNC_STATUS":
          return await getSyncStatus();

        case "PXE_REGISTER_SENDER":
          return await registerSender(msg.data.address);

        // Multi-account
        case "PXE_SET_ACTIVE_ACCOUNT":
          if (accountWallets.has(msg.data.address)) {
            activeAddress = msg.data.address;
            return { activeAddress };
          }
          return { error: `Account not found: ${msg.data.address}` };

        case "PXE_DELETE_ACCOUNT": {
          const addr = msg.data.address;
          accountWallets.delete(addr);
          if (activeAddress === addr) {
            activeAddress = accountWallets.keys().next().value || null;
          }
          return { deleted: true, activeAddress, accountCount: accountWallets.size };
        }

        case "PXE_GET_ACCOUNTS":
          return {
            accounts: Array.from(accountWallets.keys()),
            activeAddress,
          };

        // Wallet-SDK protocol: standard Aztec wallet method calls
        case "PXE_WALLET_METHOD": {
          if (!msg.rawMessage || typeof msg.rawMessage !== "string") {
            return { error: "PXE_WALLET_METHOD requires a non-empty rawMessage string" };
          }
          const parsed = JSON.parse(msg.rawMessage);
          const method = parsed.type;
          const rawArgs = parsed.args || [];

          // Use WalletSchema Zod schemas to deserialize args into proper Aztec types
          const schema = WalletSchema[method];
          let typedArgs = rawArgs;
          if (schema && typeof schema.parameters === "function") {
            try {
              typedArgs = schema.parameters().parse(rawArgs);
            } catch (e) {
              console.warn(`[PXE] WalletSchema parse failed for ${method}, using raw args:`, e.message?.slice(0, 80));
            }
          }

          const result = await handleWalletMethod(method, typedArgs);

          // Serialize response with Aztec-aware JSON (handles bigint, Buffer, etc.)
          const responseJson = jsonStringify({
            messageId: parsed.messageId,
            result,
            walletId: "celari-wallet",
          });
          return { rawResponse: responseJson };
        }

        // ─── Snapshot Persistence ────────────────────────
        case "PXE_SNAPSHOT_SAVE": {
          if (!kvStore) return { error: "No in-memory KV store (not iOS or PXE not initialized)" };
          console.log("[PXE] Snapshot: serializing KV store...");
          const t = Date.now();
          const json = kvStore.serialize();
          console.log(`[PXE] Snapshot: serialized OK — ${(json.length / 1024).toFixed(0)} KB (${Date.now() - t}ms)`);
          return { snapshot: json, sizeBytes: json.length };
        }

        case "PXE_SNAPSHOT_RESTORE": {
          const { snapshot } = msg.data || {};
          if (!snapshot) return { error: "Missing snapshot data" };
          console.log(`[PXE] Snapshot: restoring ${(snapshot.length / 1024).toFixed(0)} KB...`);
          const t = Date.now();
          const restoredStore = MemoryAztecStore.deserialize(snapshot);
          kvStore = restoredStore;
          console.log(`[PXE] Snapshot: deserialized OK (${Date.now() - t}ms)`);

          // Re-create PXE/EmbeddedWallet with restored store
          if (nodeClient) {
            console.log("[PXE] Snapshot: re-creating EmbeddedWallet with restored store...");
            const t2 = Date.now();
            const { getPXEConfig } = await import("@aztec/pxe/client/lazy");
            const pxeConfig = Object.assign(getPXEConfig(), { proverEnabled: true });
            const { WASMSimulator } = await import("@aztec/simulator/client");
            const simulator = new WASMSimulator();
            const { BBLazyPrivateKernelProver } = await import("@aztec/bb-prover/client/lazy");
            const prover = new BBLazyPrivateKernelProver(simulator);
            wallet = await EmbeddedWallet.create(nodeClient, {
              pxeConfig,
              pxeOptions: { store: restoredStore, simulator, proverOrOptions: prover },
            });
            pxeReady = true;
            console.log(`[PXE] Snapshot: EmbeddedWallet restored OK (${Date.now() - t2}ms)`);
          }
          return { restored: true, sizeBytes: snapshot.length };
        }

        // ─── NFT Support ─────────────────────────────────
        case "PXE_NFT_BALANCES": {
          const contracts = msg.data?.contracts || [];
          const ownerAddr = activeAddress;
          if (!ownerAddr || !wallet) return { nfts: [] };

          const { NFTContract } = await import("@aztec/noir-contracts.js/NFT");
          const { AztecAddress } = await import("@aztec/aztec.js");
          const ownerAz = AztecAddress.fromString(ownerAddr);
          const activeWallet = accountWallets.get(ownerAddr)?.wallet;
          if (!activeWallet) return { nfts: [], error: "No active wallet" };

          const allNfts = [];
          for (const c of contracts) {
            try {
              const contractAddr = AztecAddress.fromString(c.address);
              const nft = await NFTContract.at(contractAddr, activeWallet);
              // Fetch private NFTs (paginated)
              let page = 0;
              let hasMore = true;
              while (hasMore) {
                try {
                  const simResult = await nft.methods.get_private_nfts(ownerAz, page).simulate();
                  const rawResult = simResult.result !== undefined ? simResult.result : simResult;
                  const tokenIds = Array.isArray(rawResult) ? rawResult : (rawResult?.token_ids || []);
                  const filtered = tokenIds.filter(id => id && id.toString() !== "0");
                  for (const tokenId of filtered) {
                    allNfts.push({
                      contractAddress: c.address,
                      contractName: c.name || "NFT",
                      tokenId: tokenId.toString(),
                      visibility: "private",
                    });
                  }
                  hasMore = filtered.length >= 10;
                  page++;
                } catch {
                  hasMore = false;
                }
              }
            } catch (e) {
              console.warn(`[PXE] NFT query failed for ${c.address}:`, e.message?.slice(0, 80));
            }
          }
          return { nfts: allNfts };
        }

        case "PXE_NFT_TRANSFER": {
          const { contractAddress, tokenId, to, mode, nonce } = msg.data;
          const activeWallet = accountWallets.get(activeAddress)?.wallet;
          if (!activeWallet) return { error: "No active wallet" };

          const { NFTContract } = await import("@aztec/noir-contracts.js/NFT");
          const { AztecAddress, Fr } = await import("@aztec/aztec.js");
          const nft = await NFTContract.at(AztecAddress.fromString(contractAddress), activeWallet);
          const fromAddr = AztecAddress.fromString(activeAddress);
          const toAddr = AztecAddress.fromString(to);
          const tokenIdBig = BigInt(tokenId);
          const nonceVal = nonce ? Fr.fromString(nonce) : Fr.ZERO;

          const sendOpts = { from: fromAddr, wait: { timeout: 600_000 } };
          let nftResult;
          switch (mode) {
            case "private":
              nftResult = await nft.methods.transfer_in_private(fromAddr, toAddr, tokenIdBig, nonceVal).send(sendOpts);
              break;
            case "public":
              nftResult = await nft.methods.transfer_in_public(fromAddr, toAddr, tokenIdBig, nonceVal).send(sendOpts);
              break;
            case "shield":
              nftResult = await nft.methods.transfer_to_private(toAddr, tokenIdBig).send(sendOpts);
              break;
            case "unshield":
              nftResult = await nft.methods.transfer_to_public(fromAddr, toAddr, tokenIdBig, nonceVal).send(sendOpts);
              break;
            default:
              return { error: `Unknown NFT transfer mode: ${mode}` };
          }

          const nftReceipt = nftResult.receipt;
          return { txHash: nftReceipt.txHash.toString(), blockNumber: nftReceipt.blockNumber?.toString() || "" };
        }

        // ─── WalletConnect ───────────────────────────────
        case "PXE_WC_INIT": {
          if (wcClient) return { ready: true, sessions: wcClient.session.getAll().length };
          try {
            const { default: SignClient } = await import("@walletconnect/sign-client");
            wcClient = await SignClient.init({
              projectId: "b6c9964115c74a9aa36f9430d21d74aa",
              metadata: {
                name: "Celari Wallet",
                description: "Privacy-first wallet for Aztec Network",
                url: "https://celari.xyz",
                icons: ["https://celari.xyz/icon.png"],
              },
            });

            // Session proposal from dApp
            wcClient.on("session_proposal", async (event) => {
              chrome.runtime.sendMessage({ type: "WC_SESSION_PROPOSAL", proposal: event });
            });

            // Session request from dApp
            wcClient.on("session_request", async (event) => {
              try {
                const result = await handleWcRequest(event.params.request.method, event.params.request.params);
                await wcClient.respond({ topic: event.topic, response: { id: event.id, jsonrpc: "2.0", result } });
              } catch (e) {
                await wcClient.respond({ topic: event.topic, response: { id: event.id, jsonrpc: "2.0", error: { code: -32000, message: e.message } } });
              }
            });

            wcClient.on("session_delete", () => {
              console.log("[PXE] WC session deleted");
            });

            return { ready: true, sessions: wcClient.session.getAll().length };
          } catch (e) {
            console.error("[PXE] WC init failed:", e);
            return { error: e.message };
          }
        }

        case "PXE_WC_PAIR": {
          if (!wcClient) return { error: "WalletConnect not initialized" };
          await wcClient.pair({ uri: msg.data.uri });
          return { paired: true };
        }

        case "PXE_WC_APPROVE": {
          if (!wcClient) return { error: "WalletConnect not initialized" };
          const { id: proposalId, namespaces } = msg.data;
          const session = await wcClient.approve({ id: proposalId, namespaces });
          return { topic: session.topic, peer: session.peer?.metadata?.name || "Unknown" };
        }

        case "PXE_WC_REJECT": {
          if (!wcClient) return { error: "WalletConnect not initialized" };
          await wcClient.reject({ id: msg.data.id, reason: { code: 4001, message: "User rejected" } });
          return { rejected: true };
        }

        case "PXE_WC_DISCONNECT": {
          if (!wcClient) return { error: "WalletConnect not initialized" };
          await wcClient.disconnect({ topic: msg.data.topic, reason: { code: 6000, message: "User disconnected" } });
          return { disconnected: true };
        }

        case "PXE_WC_SESSIONS": {
          if (!wcClient) return { sessions: [] };
          const sessions = wcClient.session.getAll().map(s => ({
            topic: s.topic,
            peer: s.peer?.metadata?.name || "Unknown dApp",
            peerUrl: s.peer?.metadata?.url || "",
            chains: Object.keys(s.namespaces || {}),
            expiry: s.expiry,
          }));
          return { sessions };
        }

        // ─── Guardian Recovery ────────────────────────────
        case "PXE_SETUP_GUARDIANS": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { error: "Recovery contract not available — recompile needed" };
          const acctWallet = getActiveWallet();
          if (!acctWallet) throw new Error("No active account");

          const { guardianHash0, guardianHash1, guardianHash2, threshold, cidPart1, cidPart2 } = msg.data;

          reportProgress("Guardian kontrati hazirlaniyor...");
          const { Contract } = await import("@aztec/aztec.js");
          const contract = await Contract.at(acctWallet.getAddress(), recoveryArtifact, acctWallet);

          reportProgress("Fee odeme ayarlaniyor...");
          const { paymentMethod } = await setupSponsoredFPC(acctWallet);

          reportProgress("Guardian setup tx gonderiliyor...");
          reportProgress("Blok onayi bekleniyor...");
          const guardianResult = await contract.methods
            .setup_guardians(
              Fr.fromString(guardianHash0),
              Fr.fromString(guardianHash1),
              Fr.fromString(guardianHash2),
              Fr.fromString(String(threshold)),
              Fr.fromString(cidPart1),
              Fr.fromString(cidPart2),
            )
            .send({ from: acctWallet.getAddress(), fee: { paymentMethod }, wait: { timeout: 600_000 } });

          const guardianReceipt = guardianResult.receipt;
          console.log(`[PXE] setup_guardians OK — block ${guardianReceipt.blockNumber}`);
          return { success: true, txHash: guardianReceipt.txHash?.toString() };
        }

        case "PXE_INITIATE_RECOVERY": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { error: "Recovery contract not available — recompile needed" };
          // Note: Recovery is initiated by someone WITHOUT the current signing key.
          // This is a public function, callable by anyone.
          // For now, we use the current wallet; in production, a new ephemeral wallet is needed.
          if (!wallet) throw new Error("PXE not initialized");

          const { newKeyX, newKeyY, guardianKeyA, guardianKeyB } = msg.data;

          reportProgress("Recovery kontrati hazirlaniyor...");
          const { Contract } = await import("@aztec/aztec.js");
          // Use the base wallet (not account-specific) for public calls
          const accountAddr = AztecAddress.fromString(msg.data.accountAddress || activeAddress);
          const contract = await Contract.at(accountAddr, recoveryArtifact, wallet);

          reportProgress("Fee odeme ayarlaniyor...");
          const { paymentMethod } = await setupSponsoredFPC(wallet);

          reportProgress("Recovery tx gonderiliyor...");
          reportProgress("Blok onayi bekleniyor...");
          const recoveryInitResult = await contract.methods
            .initiate_recovery(
              Fr.fromString(newKeyX),
              Fr.fromString(newKeyY),
              Fr.fromString(guardianKeyA),
              Fr.fromString(guardianKeyB),
            )
            .send({ from: AztecAddress.ZERO, fee: { paymentMethod }, wait: { timeout: 600_000 } });

          const recoveryInitReceipt = recoveryInitResult.receipt;
          console.log(`[PXE] initiate_recovery OK — block ${recoveryInitReceipt.blockNumber}`);
          return { success: true, txHash: recoveryInitReceipt.txHash?.toString() };
        }

        case "PXE_EXECUTE_RECOVERY": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { error: "Recovery contract not available — recompile needed" };
          const acctWallet = getActiveWallet();
          if (!acctWallet) throw new Error("No active account");

          const { newKeyX, newKeyY } = msg.data;

          reportProgress("Recovery tamamlaniyor...");
          const { Contract } = await import("@aztec/aztec.js");
          const contract = await Contract.at(acctWallet.getAddress(), recoveryArtifact, acctWallet);

          const { paymentMethod } = await setupSponsoredFPC(acctWallet);

          // Convert hex key coordinates to byte arrays [u8; 32]
          const keyXBytes = hexToBuffer(newKeyX);
          const keyYBytes = hexToBuffer(newKeyY);

          reportProgress("Blok onayi bekleniyor...");
          const execRecoveryResult = await contract.methods
            .execute_recovery(Array.from(keyXBytes), Array.from(keyYBytes))
            .send({ from: acctWallet.getAddress(), fee: { paymentMethod }, wait: { timeout: 600_000 } });

          const execRecoveryReceipt = execRecoveryResult.receipt;
          console.log(`[PXE] execute_recovery OK — block ${execRecoveryReceipt.blockNumber}`);
          return { success: true, txHash: execRecoveryReceipt.txHash?.toString() };
        }

        case "PXE_CANCEL_RECOVERY": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { error: "Recovery contract not available — recompile needed" };
          const acctWallet = getActiveWallet();
          if (!acctWallet) throw new Error("No active account");

          reportProgress("Recovery iptal ediliyor...");
          const { Contract } = await import("@aztec/aztec.js");
          const contract = await Contract.at(acctWallet.getAddress(), recoveryArtifact, acctWallet);

          const { paymentMethod } = await setupSponsoredFPC(acctWallet);
          reportProgress("Blok onayi bekleniyor...");
          const cancelResult = await contract.methods.cancel_recovery()
            .send({ from: acctWallet.getAddress(), fee: { paymentMethod }, wait: { timeout: 600_000 } });

          const cancelReceipt = cancelResult.receipt;
          console.log(`[PXE] cancel_recovery OK — block ${cancelReceipt.blockNumber}`);
          return { success: true, txHash: cancelReceipt.txHash?.toString() };
        }

        case "PXE_IS_GUARDIAN_CONFIGURED": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { configured: false };
          const acctWallet = getActiveWallet();
          if (!acctWallet) throw new Error("No active account");

          const { Contract } = await import("@aztec/aztec.js");
          const contract = await Contract.at(acctWallet.getAddress(), recoveryArtifact, acctWallet);
          const guardianSim = await contract.methods.is_guardian_configured().simulate();
          const guardianConfigured = guardianSim.result !== undefined ? guardianSim.result : guardianSim;
          return { configured: !!guardianConfigured };
        }

        case "PXE_GET_RECOVERY_CID": {
          const recoveryArtifact = getRecoveryArtifact();
          if (!recoveryArtifact) return { cidPart1: "0", cidPart2: "0" };
          const acctWallet = getActiveWallet();
          if (!acctWallet) throw new Error("No active account");

          const { Contract } = await import("@aztec/aztec.js");
          const contract = await Contract.at(acctWallet.getAddress(), recoveryArtifact, acctWallet);
          const cidSim = await contract.methods.get_recovery_cid().simulate();
          const cidResult = cidSim.result !== undefined ? cidSim.result : cidSim;
          return { cidPart1: cidResult[0]?.toString() || "0", cidPart2: cidResult[1]?.toString() || "0" };
        }

        default:
          return { error: `Unknown PXE command: ${msg.type}` };
      }
    } catch (e) {
      const errMsg = e?.message || e?.originalMessage || (typeof e === 'object' ? JSON.stringify(e, Object.getOwnPropertyNames(e || {})).slice(0, 500) : String(e));
      console.error(`[PXE] ${msg.type} failed: ${errMsg}`);
      if (e?.stack) console.error(`[PXE] ${msg.type} stack: ${e.stack.slice(0, 400)}`);
      return { error: errMsg };
    }
  };

  handle()
    .then(r => { console.log(`[PXE] ${msg.type} completed OK`); sendResponse({ success: true, ...r }); })
    .catch(e => { console.error(`[PXE] ${msg.type} UNHANDLED:`, e?.message || e); sendResponse({ success: false, error: e?.message || String(e) }); });
  return true; // Keep message channel open for async response
});

// Disable early banner listener now that real listener is registered
if (typeof __pxeEarlyReady !== "undefined") __pxeEarlyReady = true;

// Signal to background that offscreen listener is active
chrome.runtime.sendMessage({ type: "OFFSCREEN_READY" }, () => {
  void chrome.runtime.lastError; // Suppress if background not listening yet
});
console.log("[PXE] Offscreen document loaded — waiting for PXE_INIT");
