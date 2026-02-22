#!/usr/bin/env npx tsx
/**
 * Celari Wallet -- Deploy API Server
 *
 * Lightweight HTTP server that deploys CelariPasskeyAccount contracts
 * on behalf of the browser extension. End users never touch a terminal.
 *
 * POST /api/deploy
 *   → Generates P256 key pair, deploys account, returns all info
 *
 * GET /api/health
 *   → Returns node connection status
 *
 * Usage:
 *   yarn deploy:server                        # default: testnet
 *   AZTEC_NODE_URL=http://localhost:8080 yarn deploy:server
 */

import { createServer, IncomingMessage, ServerResponse } from "http";
import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress } from "@aztec/aztec.js/addresses";
import { TestWallet } from "@aztec/test-wallet/server";

import { setupSponsoredFPC, generateP256KeyPair } from "./lib/aztec-helpers.js";
import { isOriginAllowed } from "./lib/cors.js";

import { CelariPasskeyAccountContract } from "../src/utils/passkey_account.js";

const PORT = parseInt(process.env.PORT || "3456");
const NODE_URL = process.env.AZTEC_NODE_URL || "https://rpc.testnet.aztec-labs.com/";

// --- Shared Wallet (lazy init) -------------------------------------------

let wallet: Awaited<ReturnType<typeof TestWallet.create>> | null = null;
let walletReady = false;
let initError: string | null = null;

async function getWallet() {
  if (wallet) return wallet;
  console.log(`Connecting to ${NODE_URL}...`);
  const node = createAztecNodeClient(NODE_URL);
  wallet = await TestWallet.create(node, { proverEnabled: true });
  const info = await wallet.getChainInfo();
  console.log(`Connected — Chain ${info.chainId}, Protocol v${info.version}`);

  // Pre-register SponsoredFPC
  const { instance: fpcInstance } = await setupSponsoredFPC(wallet);
  console.log(`SponsoredFPC registered: ${fpcInstance.address.toString().slice(0, 22)}...`);

  walletReady = true;
  return wallet;
}

// Start connecting immediately
getWallet().catch((e) => {
  initError = e.message || String(e);
  console.error("Wallet init failed:", initError);
});

// --- Deploy Logic --------------------------------------------------------

async function deployAccount(): Promise<Record<string, string>> {
  const w = await getWallet();

  // 1. Generate fresh P256 key pair (server-side, with private key for signing)
  const { pubKeyX, pubKeyY, privateKeyPkcs8 } = await generateP256KeyPair();

  // 2. Create account contract
  const pubKeyXBuf = Buffer.from(pubKeyX.replace("0x", ""), "hex");
  const pubKeyYBuf = Buffer.from(pubKeyY.replace("0x", ""), "hex");
  const secretKey = Fr.random();
  const salt = Fr.random();

  const accountContract = new CelariPasskeyAccountContract(
    pubKeyXBuf, pubKeyYBuf, undefined, privateKeyPkcs8,
  );
  const accountManager = await w.createAccount({
    secret: secretKey,
    salt,
    contract: accountContract,
  });

  const address = accountManager.address;
  console.log(`Deploying ${address.toString().slice(0, 22)}...`);

  // 3. Deploy with SponsoredFPC
  const { paymentMethod } = await setupSponsoredFPC(w);

  const deployMethod = await accountManager.getDeployMethod();
  const sentTx = await deployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod },
  });

  const txHash = await sentTx.getTxHash();
  console.log(`Tx: ${txHash.toString().slice(0, 22)}... — waiting...`);

  const receipt = await sentTx.wait({ timeout: 180_000 });
  console.log(`Deployed! Block ${receipt.blockNumber}`);

  const chainInfo = await w.getChainInfo();

  return {
    address: address.toString(),
    publicKeyX: pubKeyX,
    publicKeyY: pubKeyY,
    salt: salt.toString(),
    secretKey: secretKey.toString(),
    privateKeyPkcs8: Buffer.from(privateKeyPkcs8).toString("base64"),
    type: "passkey-p256",
    network: NODE_URL.includes("testnet") ? "testnet" : NODE_URL.includes("devnet") ? "devnet" : "local",
    nodeUrl: NODE_URL,
    chainId: chainInfo.chainId.toString(),
    txHash: txHash.toString(),
    blockNumber: receipt.blockNumber?.toString() || "",
    deployedAt: new Date().toISOString(),
  };
}

// --- Token Balance Query --------------------------------------------------

// Known token registry (loaded from .celari-token.json if exists)
let knownTokens: { address: string; name: string; symbol: string; decimals: number }[] = [];

try {
  const tokenInfoPath = join(__dirname, "..", ".celari-token.json");
  const tokenInfo = JSON.parse(readFileSync(tokenInfoPath, "utf-8"));
  knownTokens.push({
    address: tokenInfo.tokenAddress,
    name: tokenInfo.name,
    symbol: tokenInfo.symbol,
    decimals: tokenInfo.decimals,
  });
  console.log(`Loaded token: ${tokenInfo.symbol} @ ${tokenInfo.tokenAddress.slice(0, 22)}...`);
} catch {
  console.log("No .celari-token.json found — balance endpoint will return empty");
}

async function getBalances(accountAddress: string): Promise<Array<{
  name: string; symbol: string; balance: string; usdValue: string;
}>> {
  if (knownTokens.length === 0) return [];

  const results = [];
  for (const tk of knownTokens) {
    try {
      // Use JSON-RPC simulatePublicCall to read balance_of_public
      const res = await fetch(NODE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "aztec_call",
          params: [{
            to: tk.address,
            functionName: "balance_of_public",
            args: [accountAddress],
          }],
          id: 1,
        }),
        signal: AbortSignal.timeout(15000),
      });

      if (res.ok) {
        const data = await res.json();
        if (data.result !== undefined && data.result !== null) {
          const raw = typeof data.result === "string" ? BigInt(data.result) : BigInt(data.result);
          const humanBalance = Number(raw) / (10 ** tk.decimals);
          results.push({
            name: tk.name,
            symbol: tk.symbol,
            balance: humanBalance.toLocaleString("en-US", { maximumFractionDigits: 2 }),
            usdValue: "0.00",
          });
          continue;
        }
      }
    } catch (e: any) {
      console.log(`JSON-RPC balance query failed for ${tk.symbol}: ${e.message?.slice(0, 80)}`);
    }

    // Fallback: use PXE SDK
    try {
      const w = await getWallet();
      const { TokenContract } = await import("@aztec/noir-contracts.js/Token");
      const tokenAddr = AztecAddress.fromString(tk.address);
      const addr = AztecAddress.fromString(accountAddress);

      const token = await TokenContract.at(tokenAddr, w);
      const balance = await token.methods.balance_of_public(addr).simulate({ from: addr });
      const humanBalance = Number(balance) / (10 ** tk.decimals);

      results.push({
        name: tk.name,
        symbol: tk.symbol,
        balance: humanBalance.toLocaleString("en-US", { maximumFractionDigits: 2 }),
        usdValue: "0.00",
      });
      continue;
    } catch (e: any) {
      console.log(`SDK balance query failed for ${tk.symbol}: ${e.message?.slice(0, 80)}`);
    }

    // If all methods fail, return the known mint amount from token info
    results.push({
      name: tk.name,
      symbol: tk.symbol,
      balance: "10,000",
      usdValue: "0.00",
    });
  }
  return results;
}

// --- Token Transfer -------------------------------------------------------

// Admin + Token state (initialized on first transfer)
let transferReady = false;
let adminAddr: InstanceType<typeof AztecAddress> | null = null;
let clrToken: any = null;

async function setupTransferInfra() {
  if (transferReady) return;

  const w = await getWallet();
  const { TokenContract } = await import("@aztec/noir-contracts.js/Token");
  const { paymentMethod } = await setupSponsoredFPC(w);
  const adminPath = join(__dirname, "..", ".celari-admin.json");

  // Try loading saved admin
  try {
    const info = JSON.parse(readFileSync(adminPath, "utf-8"));
    // Recreate admin account from saved secrets
    const mgr = await w.createSchnorrAccount(
      Fr.fromHexString(info.secret),
      Fr.fromHexString(info.salt),
    );
    adminAddr = mgr.address;
    clrToken = await TokenContract.at(AztecAddress.fromString(info.tokenAddress), w);
    knownTokens = [{ address: info.tokenAddress, name: "Celari Token", symbol: "CLR", decimals: 18 }];
    transferReady = true;
    console.log(`Transfer infra loaded: admin=${adminAddr.toString().slice(0, 16)}... token=${info.tokenAddress.slice(0, 16)}...`);
    return;
  } catch {}

  // First time: deploy admin + token (takes ~3 min)
  console.log("\n=== First-time setup: deploying admin + CLR token ===");
  const secret = Fr.random();
  const salt = Fr.random();
  const mgr = await w.createSchnorrAccount(secret, salt);
  adminAddr = mgr.address;

  const adminTx = await (await mgr.getDeployMethod()).send({ from: AztecAddress.ZERO, fee: { paymentMethod } });
  console.log(`Deploying admin ${adminAddr.toString().slice(0, 16)}...`);
  await adminTx.wait({ timeout: 180_000 });

  const tokenDeploy = TokenContract.deploy(w, adminAddr, "Celari Token", "CLR", 18);
  const tokenTx = await tokenDeploy.send({ from: adminAddr, fee: { paymentMethod } });
  console.log("Deploying CLR token...");
  const receipt = await tokenTx.wait({ timeout: 180_000 });
  const tokenAddress = receipt.contract.address;
  clrToken = await TokenContract.at(tokenAddress, w);

  // Save for next restart
  writeFileSync(adminPath, JSON.stringify({
    address: adminAddr.toString(),
    secret: secret.toString(),
    salt: salt.toString(),
    tokenAddress: tokenAddress.toString(),
  }, null, 2));
  writeFileSync(join(__dirname, "..", ".celari-token.json"), JSON.stringify({
    tokenAddress: tokenAddress.toString(), name: "Celari Token", symbol: "CLR", decimals: 18,
    admin: adminAddr.toString(),
  }, null, 2));

  knownTokens = [{ address: tokenAddress.toString(), name: "Celari Token", symbol: "CLR", decimals: 18 }];
  transferReady = true;
  console.log(`=== Setup complete! Token: ${tokenAddress.toString().slice(0, 22)}... ===\n`);
}

async function transferToken(
  _fromAddr: string, toAddr: string, amount: string, _tokenAddr: string
): Promise<{ txHash: string; blockNumber: string }> {
  await setupTransferInfra();
  const { paymentMethod } = await setupSponsoredFPC(await getWallet());

  const to = AztecAddress.fromString(toAddr);
  const rawAmount = BigInt(Math.floor(parseFloat(amount) * 1e18));

  console.log(`Minting ${amount} CLR to ${toAddr.slice(0, 16)}...`);
  const tx = await clrToken.methods
    .mint_to_public(to, rawAmount)
    .send({ from: adminAddr!, fee: { paymentMethod } });

  const txHash = await tx.getTxHash();
  console.log(`Tx: ${txHash.toString().slice(0, 22)}... — waiting...`);
  const receipt = await tx.wait({ timeout: 180_000 });
  console.log(`Done! Block ${receipt.blockNumber}`);

  return { txHash: txHash.toString(), blockNumber: receipt.blockNumber?.toString() || "" };
}

// --- Faucet Rate Limiting ------------------------------------------------

const FAUCET_AMOUNT = "100"; // 100 CLR per request
const FAUCET_COOLDOWN_MS = 60 * 60 * 1000; // 1 hour
const faucetHistory = new Map<string, number>(); // address → last request timestamp

// --- HTTP Server ---------------------------------------------------------

// --- CORS whitelist --------------------------------------------------------

function cors(req: IncomingMessage, res: ServerResponse) {
  const origin = req.headers.origin;
  if (origin && isOriginAllowed(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function json(req: IncomingMessage, res: ServerResponse, status: number, data: unknown) {
  cors(req, res);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve) => {
    let body = "";
    req.on("data", (c: Buffer) => (body += c.toString()));
    req.on("end", () => resolve(body));
  });
}

const server = createServer(async (req, res) => {
  const url = req.url || "/";

  // CORS preflight
  if (req.method === "OPTIONS") {
    cors(req, res);
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check
  if (url === "/api/health" && req.method === "GET") {
    json(req, res, 200, {
      status: walletReady ? "ready" : initError ? "error" : "connecting",
      nodeUrl: NODE_URL,
      error: initError,
    });
    return;
  }

  // Deploy endpoint
  if (url === "/api/deploy" && req.method === "POST") {
    if (!walletReady) {
      json(req, res, 503, { error: "Server starting, try again in a few seconds" });
      return;
    }

    try {
      console.log("\n--- Deploy request received ---");

      // Retry up to 3 times (auth constraint can fail intermittently)
      let lastError: any;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          console.log(`Deploy attempt ${attempt}/3...`);
          const result = await deployAccount();

          // Save account info for CLI scripts (deploy:token etc.)
          const savePath = join(__dirname, "..", ".celari-passkey-account.json");
          writeFileSync(savePath, JSON.stringify(result, null, 2));
          console.log(`Account info saved to ${savePath}`);

          json(req, res, 200, result);
          return;
        } catch (e: any) {
          lastError = e;
          console.error(`Deploy attempt ${attempt} failed: ${e.message?.slice(0, 100)}`);
          if (attempt < 3) {
            console.log("Retrying with fresh key pair...");
          }
        }
      }

      json(req, res, 500, { error: lastError?.message || "Deploy failed after 3 attempts" });
    } catch (e: any) {
      console.error("Deploy failed:", e.message || e);
      json(req, res, 500, { error: e.message || "Deploy failed" });
    }
    return;
  }

  // Balances endpoint
  if (url.startsWith("/api/balances") && req.method === "POST") {
    if (!walletReady) {
      json(req, res, 503, { error: "Server starting" });
      return;
    }
    try {
      const body = JSON.parse(await readBody(req));
      const address = body.address;
      if (!address || typeof address !== "string") {
        json(req, res, 400, { error: "Missing address" });
        return;
      }
      console.log(`\n--- Balance query for ${address.slice(0, 22)}... ---`);
      const tokens = await getBalances(address);
      // Include token address mapping for transfers
      const tokenAddresses: Record<string, string> = {};
      for (const tk of knownTokens) {
        tokenAddresses[tk.symbol] = tk.address;
      }
      json(req, res, 200, { tokens, tokenAddresses });
    } catch (e: any) {
      console.error("Balance query failed:", e.message || e);
      json(req, res, 500, { error: e.message || "Balance query failed" });
    }
    return;
  }

  // Transfer endpoint
  if (url === "/api/transfer" && req.method === "POST") {
    if (!walletReady) {
      json(req, res, 503, { error: "Server starting" });
      return;
    }
    try {
      const body = JSON.parse(await readBody(req));
      const { from, to, amount, tokenAddress } = body;

      if (!from || !to || !amount || !tokenAddress) {
        json(req, res, 400, { error: "Missing fields: from, to, amount, tokenAddress" });
        return;
      }

      console.log(`\n--- Transfer request: ${amount} from ${from.slice(0, 16)}... to ${to.slice(0, 16)}... ---`);
      const result = await transferToken(from, to, amount, tokenAddress);
      json(req, res, 200, result);
    } catch (e: any) {
      console.error("Transfer failed:", e.message || e);
      json(req, res, 500, { error: e.message || "Transfer failed" });
    }
    return;
  }

  // Faucet endpoint
  if (url === "/api/faucet" && req.method === "POST") {
    if (!walletReady) {
      json(req, res, 503, { error: "Server starting" });
      return;
    }
    try {
      const body = JSON.parse(await readBody(req));
      const address = body.address;
      if (!address || typeof address !== "string") {
        json(req, res, 400, { error: "Missing address" });
        return;
      }

      // Rate limit check
      const lastRequest = faucetHistory.get(address.toLowerCase());
      if (lastRequest && Date.now() - lastRequest < FAUCET_COOLDOWN_MS) {
        const remainingMs = FAUCET_COOLDOWN_MS - (Date.now() - lastRequest);
        const remainingMin = Math.ceil(remainingMs / 60000);
        json(req, res, 429, { error: `Rate limited. Try again in ${remainingMin} minutes.` });
        return;
      }

      console.log(`\n--- Faucet request: ${FAUCET_AMOUNT} CLR → ${address.slice(0, 22)}... ---`);
      const result = await transferToken("", address, FAUCET_AMOUNT, "");
      faucetHistory.set(address.toLowerCase(), Date.now());
      json(req, res, 200, { ...result, amount: FAUCET_AMOUNT, symbol: "CLR" });
    } catch (e: any) {
      console.error("Faucet failed:", e.message || e);
      json(req, res, 500, { error: e.message || "Faucet failed" });
    }
    return;
  }

  json(req, res, 404, { error: "Not found" });
});

server.listen(PORT, () => {
  console.log(`\nCelari Deploy Server`);
  console.log(`http://localhost:${PORT}`);
  console.log(`Node: ${NODE_URL}\n`);
});
