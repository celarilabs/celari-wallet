#!/usr/bin/env npx tsx
/**
 * Celari Bridge — Deploy L2 Contracts to Aztec Testnet
 *
 * Deploys BridgedToken + CelariTokenBridge on Aztec, then wires them together.
 *
 * Steps:
 *   1. Deploy Schnorr admin account (EmbeddedWallet-managed)
 *   2. Deploy BridgedToken (admin, "Celari Bridged ETH", "cbETH", 18)
 *   3. Deploy CelariTokenBridge (token=BridgedToken, portal=L1 portal address)
 *   4. Call BridgedToken.set_minter(bridge_address)
 *   5. Save deployment info to .celari-bridge-l2.json
 *
 * Usage:
 *   npx tsx scripts/deploy-bridge-l2.ts
 *   AZTEC_NODE_URL=http://localhost:8080 npx tsx scripts/deploy-bridge-l2.ts
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { Fr } from "@aztec/aztec.js/fields";
import { AztecAddress, EthAddress } from "@aztec/aztec.js/addresses";
import { EmbeddedWallet } from "@aztec/wallets/embedded";
import { loadContractArtifact } from "@aztec/aztec.js/abi";
import { Contract } from "@aztec/aztec.js/contracts";

import { setupSponsoredFPC } from "./lib/aztec-helpers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const NODE_URL = process.env.AZTEC_NODE_URL || "https://rpc.testnet.aztec-labs.com/";

// L1 deployment info
const L1_DEPLOYMENT_PATH = join(__dirname, "..", "bridge", ".l1-deployment.json");
const L2_DEPLOYMENT_PATH = join(__dirname, "..", ".celari-bridge-l2.json");

// Contract artifacts (compiled Noir → JSON)
const BRIDGED_TOKEN_ARTIFACT_PATH = join(
  __dirname, "..", "bridge", "contracts", "l2", "bridged_token", "target",
  "bridged_token-BridgedToken.json",
);
const TOKEN_BRIDGE_ARTIFACT_PATH = join(
  __dirname, "..", "bridge", "contracts", "l2", "celari_token_bridge", "target",
  "celari_token_bridge-CelariTokenBridge.json",
);

// --- String → Field encoding ---
// Noir stores name/symbol as single Field values (max 31 bytes)
function stringToField(s: string): Fr {
  const bytes = Buffer.alloc(31, 0);
  const encoded = Buffer.from(s, "utf-8");
  encoded.copy(bytes, 0, 0, Math.min(encoded.length, 31));
  return Fr.fromBuffer(Buffer.concat([Buffer.alloc(1, 0), bytes])); // 32 bytes total
}

async function main() {
  console.log("╔═══════════════════════════════════════════╗");
  console.log("║  Celari Bridge — L2 Deployment (Aztec)    ║");
  console.log("╚═══════════════════════════════════════════╝\n");

  // --- Load L1 deployment info ---
  let l1Portal: string;
  if (existsSync(L1_DEPLOYMENT_PATH)) {
    const l1Info = JSON.parse(readFileSync(L1_DEPLOYMENT_PATH, "utf-8"));
    l1Portal = l1Info.portal;
    console.log(`L1 Portal: ${l1Portal}`);
  } else if (process.env.PORTAL_ADDRESS) {
    l1Portal = process.env.PORTAL_ADDRESS;
    console.log(`L1 Portal (env): ${l1Portal}`);
  } else {
    // Use the known deployed address
    l1Portal = "0x54b844835905B303d9618Ceb502601993040259B";
    console.log(`L1 Portal (default): ${l1Portal}`);
  }

  // --- Load contract artifacts ---
  console.log("\nLoading contract artifacts...");

  if (!existsSync(BRIDGED_TOKEN_ARTIFACT_PATH)) {
    console.error(`ERROR: BridgedToken artifact not found at ${BRIDGED_TOKEN_ARTIFACT_PATH}`);
    console.error("Compile first: cd bridge/contracts/l2/bridged_token && aztec-nargo compile");
    process.exit(1);
  }
  if (!existsSync(TOKEN_BRIDGE_ARTIFACT_PATH)) {
    console.error(`ERROR: CelariTokenBridge artifact not found at ${TOKEN_BRIDGE_ARTIFACT_PATH}`);
    console.error("Compile first: cd bridge/contracts/l2/celari_token_bridge && aztec-nargo compile");
    process.exit(1);
  }

  // Strip __aztec_nr_internals__ prefix from function names.
  // nargo adds this prefix to public functions in the artifact JSON, but the
  // public_dispatch bytecode computes selectors from clean names. Without this
  // fix, the SDK sends the wrong selector and the contract rejects with
  // "Unknown selector".
  function stripInternalPrefix(raw: any): any {
    if (raw.functions) {
      for (const fn of raw.functions) {
        fn.name = fn.name.replace(/^__aztec_nr_internals__/, "");
      }
    }
    return raw;
  }

  const bridgedTokenArtifact = loadContractArtifact(
    stripInternalPrefix(JSON.parse(readFileSync(BRIDGED_TOKEN_ARTIFACT_PATH, "utf-8"))),
  );
  const tokenBridgeArtifact = loadContractArtifact(
    stripInternalPrefix(JSON.parse(readFileSync(TOKEN_BRIDGE_ARTIFACT_PATH, "utf-8"))),
  );
  console.log("  BridgedToken artifact loaded ✓");
  console.log("  CelariTokenBridge artifact loaded ✓");

  // --- Connect to Aztec node ---
  console.log(`\nConnecting to ${NODE_URL}...`);
  const node = createAztecNodeClient(NODE_URL);
  const wallet = await EmbeddedWallet.create(node, { pxeConfig: { proverEnabled: true } });
  const chainInfo = await wallet.getChainInfo();
  console.log(`Connected — Chain ${chainInfo.chainId}, Protocol v${chainInfo.version}`);

  // --- Setup SponsoredFPC for gasless transactions ---
  console.log("\nSetting up SponsoredFPC...");
  const { paymentMethod } = await setupSponsoredFPC(wallet);
  console.log("SponsoredFPC ready ✓");

  // --- Create Schnorr admin account ---
  console.log("\nCreating admin account (Schnorr)...");
  const adminSecret = Fr.random();
  const adminSalt = Fr.random();
  const adminManager = await wallet.createSchnorrAccount(adminSecret, adminSalt);
  const adminAddress = adminManager.address;
  console.log(`Admin: ${adminAddress.toString().slice(0, 30)}...`);

  // Deploy admin account
  console.log("Deploying admin account...");
  const adminDeployMethod = await adminManager.getDeployMethod();
  const adminDeployReceipt = await adminDeployMethod.send({
    from: AztecAddress.ZERO,
    fee: { paymentMethod },
    wait: { timeout: 300_000, returnReceipt: true },
  });
  console.log(`  Tx: ${adminDeployReceipt.txHash.toString().slice(0, 30)}...`);
  console.log("  Admin deployed ✓");

  // --- Step 1: Deploy BridgedToken ---
  console.log("\n═══ Step 1/3: Deploying BridgedToken ═══");

  const tokenName = stringToField("Celari Bridged ETH");
  const tokenSymbol = stringToField("cbETH");
  const tokenDecimals = 18;

  const bridgedTokenDeploy = Contract.deploy(wallet, bridgedTokenArtifact, [
    adminAddress,
    tokenName,
    tokenSymbol,
    tokenDecimals,
  ]);

  // Simulate first to catch errors with detailed messages
  console.log("  Simulating deployment...");
  try {
    const simResult = await bridgedTokenDeploy.simulate({
      from: adminAddress,
      fee: { paymentMethod },
      skipTxValidation: true,
    });
    console.log("  Simulation OK ✓");
  } catch (simErr: any) {
    console.error("  Simulation FAILED:", simErr.message?.slice(0, 200));
    if (simErr.cause) console.error("  Cause:", simErr.cause?.message?.slice(0, 200));
    throw simErr;
  }

  console.log("  Sending deployment tx...");
  const bridgedTokenResult = await bridgedTokenDeploy.send({
    from: adminAddress,
    fee: { paymentMethod },
    wait: { timeout: 300_000, returnReceipt: true },
  });
  const bridgedTokenAddress = bridgedTokenResult.contract.address;
  console.log(`  Tx: ${bridgedTokenResult.txHash.toString().slice(0, 30)}...`);
  console.log(`  BridgedToken deployed! Block: ${bridgedTokenResult.blockNumber}`);
  console.log(`  Address: ${bridgedTokenAddress.toString()}`);

  // --- Step 2: Deploy CelariTokenBridge ---
  console.log("\n═══ Step 2/3: Deploying CelariTokenBridge ═══");

  const portalEthAddress = EthAddress.fromString(l1Portal);

  const bridgeDeploy = Contract.deploy(wallet, tokenBridgeArtifact, [
    bridgedTokenAddress,
    portalEthAddress,
  ]);

  const bridgeResult = await bridgeDeploy.send({
    from: adminAddress,
    fee: { paymentMethod },
    wait: { timeout: 300_000, returnReceipt: true },
  });
  const bridgeAddress = bridgeResult.contract.address;
  console.log(`  Tx: ${bridgeResult.txHash.toString().slice(0, 30)}...`);
  console.log(`  CelariTokenBridge deployed! Block: ${bridgeResult.blockNumber}`);
  console.log(`  Address: ${bridgeAddress.toString()}`);

  // --- Step 3: Set minter on BridgedToken ---
  console.log("\n═══ Step 3/3: Setting bridge as minter ═══");

  const bridgedToken = await Contract.at(bridgedTokenAddress, bridgedTokenArtifact, wallet);
  const minterReceipt = await bridgedToken.methods
    .set_minter(bridgeAddress)
    .send({ from: adminAddress, fee: { paymentMethod }, wait: { timeout: 300_000 } });
  console.log(`  Tx: ${minterReceipt.txHash.toString().slice(0, 30)}...`);
  console.log(`  Minter set ✓ Block: ${minterReceipt.blockNumber}`);

  // --- Verify ---
  console.log("\n═══ Verification ═══");
  try {
    const verifyMinter = await bridgedToken.methods.get_minter().simulate({ from: adminAddress });
    console.log(`  BridgedToken.minter = ${verifyMinter.toString()}`);
    console.log(`  Expected bridge     = ${bridgeAddress.toString()}`);
    console.log(`  Match: ${verifyMinter.toString() === bridgeAddress.toString() ? "✓" : "✗"}`);
  } catch (e: any) {
    console.log(`  Minter verify skipped: ${e.message?.slice(0, 60)}`);
  }

  // --- Save deployment info ---
  const deploymentInfo = {
    network: NODE_URL.includes("testnet") ? "testnet" : NODE_URL.includes("devnet") ? "devnet" : "local",
    nodeUrl: NODE_URL,
    chainId: chainInfo.chainId.toString(),

    // L1
    l1Portal: l1Portal,
    l1Network: "sepolia",

    // L2
    bridgedToken: {
      address: bridgedTokenAddress.toString(),
      name: "Celari Bridged ETH",
      symbol: "cbETH",
      decimals: 18,
      txHash: bridgedTokenResult.txHash.toString(),
      blockNumber: bridgedTokenResult.blockNumber?.toString() || "",
    },
    tokenBridge: {
      address: bridgeAddress.toString(),
      txHash: bridgeResult.txHash.toString(),
      blockNumber: bridgeResult.blockNumber?.toString() || "",
    },
    admin: {
      address: adminAddress.toString(),
      secret: adminSecret.toString(),
      salt: adminSalt.toString(),
    },

    deployedAt: new Date().toISOString(),
    status: "deployed",
  };

  writeFileSync(L2_DEPLOYMENT_PATH, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to ${L2_DEPLOYMENT_PATH}`);

  // Also update L1 deployment with L2 bridge address
  if (existsSync(L1_DEPLOYMENT_PATH)) {
    try {
      const l1Info = JSON.parse(readFileSync(L1_DEPLOYMENT_PATH, "utf-8"));
      l1Info.l2Bridge = bridgeAddress.toString();
      l1Info.l2BridgedToken = bridgedTokenAddress.toString();
      l1Info.l2DeployedAt = new Date().toISOString();
      writeFileSync(L1_DEPLOYMENT_PATH, JSON.stringify(l1Info, null, 2));
      console.log(`L1 deployment info updated with L2 addresses`);
    } catch {}
  }

  // --- Summary ---
  console.log("\n╔═══════════════════════════════════════════╗");
  console.log("║  Deployment Complete!                      ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log(`\n  L1 Portal:          ${l1Portal}`);
  console.log(`  L2 BridgedToken:    ${bridgedTokenAddress.toString()}`);
  console.log(`  L2 TokenBridge:     ${bridgeAddress.toString()}`);
  console.log(`  Admin:              ${adminAddress.toString().slice(0, 30)}...`);
  console.log(`\n  Next: Update L1 portal with L2 bridge address`);
  console.log(`        (if not already configured)\n`);
}

main().catch((e) => {
  console.error("\nDeployment failed:", e.message || e);
  if (e.stack) console.error(e.stack.split("\n").slice(0, 5).join("\n"));
  process.exit(1);
});
