/**
 * Celari Bridge — Deploy L2 Contracts to Aztec Testnet
 *
 * Deploys BridgedToken and CelariTokenBridge contracts on Aztec.
 *
 * Usage:
 *   AZTEC_NODE_URL=... PORTAL_ADDRESS=... DEPLOYER_SECRET_KEY=... npx tsx bridge/scripts/deploy-l2.ts
 *
 * Environment variables:
 *   AZTEC_NODE_URL        — Aztec PXE endpoint (default: http://localhost:8080)
 *   PORTAL_ADDRESS        — L1 CelariBridgePortal address on Sepolia (0x-prefixed)
 *   DEPLOYER_SECRET_KEY   — Aztec account secret key (0x-prefixed Fr field element)
 */

import {
  createPXEClient,
  Contract,
  Fr,
  GrumpkinScalar,
  AccountWallet,
  AztecAddress,
  waitForPXE,
} from "@aztec/aztec.js";
import { SingleKeyAccountContract } from "@aztec/accounts/single_key";

// ─── Configuration ───────────────────────────────────

const AZTEC_NODE_URL = process.env.AZTEC_NODE_URL || "http://localhost:8080";
const PORTAL_ADDRESS = process.env.PORTAL_ADDRESS;
const DEPLOYER_SECRET_KEY = process.env.DEPLOYER_SECRET_KEY;

// ─── Artifact paths ──────────────────────────────────

const ARTIFACTS_DIR = new URL(
  "../../bridge/sdk/artifacts",
  import.meta.url
).pathname;

// ─── Main ────────────────────────────────────────────

async function main() {
  console.log("╔═══════════════════════════════════════════╗");
  console.log("║  Celari Bridge — L2 Deployment (Aztec)    ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log();
  console.log("PXE URL:", AZTEC_NODE_URL);
  console.log("Portal Address:", PORTAL_ADDRESS || "NOT SET");
  console.log();

  if (!PORTAL_ADDRESS) {
    console.error("Error: PORTAL_ADDRESS environment variable required");
    console.error("  Deploy L1 contracts first: yarn bridge:deploy:l1");
    process.exit(1);
  }

  if (!DEPLOYER_SECRET_KEY) {
    console.error("Error: DEPLOYER_SECRET_KEY environment variable required");
    console.error("  This is your Aztec account secret key (Fr field element)");
    process.exit(1);
  }

  // ─── Connect to PXE ──────────────────────────────

  console.log("Connecting to Aztec PXE...");
  const pxe = createPXEClient(AZTEC_NODE_URL);

  try {
    await waitForPXE(pxe, 30_000);
  } catch (err) {
    console.error("Error: Cannot connect to Aztec PXE at", AZTEC_NODE_URL);
    console.error("  Start sandbox: yarn start:sandbox");
    console.error("  Or set AZTEC_NODE_URL for testnet");
    process.exit(1);
  }

  const nodeInfo = await pxe.getNodeInfo();
  console.log("Connected to Aztec node:");
  console.log("  Version:", (nodeInfo as any).nodeVersion || "unknown");
  console.log("  Chain ID:", (nodeInfo as any).l1ChainId || "unknown");
  console.log();

  // ─── Load deployer account ───────────────────────

  console.log("Setting up deployer account...");
  const secretKey = Fr.fromHexString(DEPLOYER_SECRET_KEY);
  const accountContract = new SingleKeyAccountContract(
    GrumpkinScalar.fromBuffer(secretKey.toBuffer())
  );
  const wallet = await accountContract.getDeploymentInteraction(pxe).send().wait();
  const deployerAddress = wallet.getCompleteAddress().address;
  console.log("Deployer address:", deployerAddress.toString());
  console.log();

  // ─── Load artifacts ──────────────────────────────

  console.log("Loading contract artifacts...");
  let BridgedTokenArtifact: any;
  let CelariTokenBridgeArtifact: any;

  try {
    const { default: bt } = await import(
      `${ARTIFACTS_DIR}/BridgedToken.json`,
      { assert: { type: "json" } }
    );
    BridgedTokenArtifact = bt;
  } catch {
    console.error(
      "Error: BridgedToken artifact not found at",
      ARTIFACTS_DIR
    );
    console.error("  Compile first:");
    console.error("    cd bridge/contracts/l2/bridged_token && aztec-nargo compile");
    console.error(
      "    aztec codegen bridge/contracts/l2/bridged_token/target -o bridge/sdk/artifacts"
    );
    process.exit(1);
  }

  try {
    const { default: ctb } = await import(
      `${ARTIFACTS_DIR}/CelariTokenBridge.json`,
      { assert: { type: "json" } }
    );
    CelariTokenBridgeArtifact = ctb;
  } catch {
    console.error(
      "Error: CelariTokenBridge artifact not found at",
      ARTIFACTS_DIR
    );
    console.error("  Compile first:");
    console.error(
      "    cd bridge/contracts/l2/celari_token_bridge && aztec-nargo compile"
    );
    console.error(
      "    aztec codegen bridge/contracts/l2/celari_token_bridge/target -o bridge/sdk/artifacts"
    );
    process.exit(1);
  }

  // ─── Step 1: Deploy BridgedToken ─────────────────

  console.log("Step 1: Deploying BridgedToken...");
  const bridgedTokenDeploy = Contract.deploy(
    wallet,
    BridgedTokenArtifact,
    [
      deployerAddress,                  // admin
      "Celari Bridged ETH",             // name
      "cbETH",                          // symbol
      18,                               // decimals
    ]
  );
  const bridgedTokenTx = await bridgedTokenDeploy.send().wait();
  const bridgedTokenAddress = bridgedTokenTx.contract.address;
  console.log("BridgedToken deployed at:", bridgedTokenAddress.toString());
  console.log();

  // ─── Step 2: Deploy CelariTokenBridge ────────────

  console.log("Step 2: Deploying CelariTokenBridge...");
  // Convert L1 portal address (hex) to AztecAddress-compatible field
  const portalFr = Fr.fromHexString(PORTAL_ADDRESS.replace("0x", "").padStart(64, "0"));
  const bridgeDeploy = Contract.deploy(
    wallet,
    CelariTokenBridgeArtifact,
    [
      bridgedTokenAddress,    // token (BridgedToken on L2)
      portalFr,               // portal (CelariBridgePortal on L1)
    ]
  );
  const bridgeTx = await bridgeDeploy.send().wait();
  const bridgeAddress = bridgeTx.contract.address;
  console.log("CelariTokenBridge deployed at:", bridgeAddress.toString());
  console.log();

  // ─── Step 3: Set minter on BridgedToken ──────────

  console.log("Step 3: Setting bridge as minter on BridgedToken...");
  const bridgedToken = await Contract.at(
    bridgedTokenAddress,
    BridgedTokenArtifact,
    wallet
  );
  const setMinterTx = await bridgedToken.methods
    .set_minter(bridgeAddress, true)
    .send()
    .wait();
  console.log("Minter set. TX hash:", setMinterTx.txHash?.toString());
  console.log();

  // ─── Save deployment config ──────────────────────

  const deployConfig = {
    network: "aztec-testnet",
    pxeUrl: AZTEC_NODE_URL,
    portalAddress: PORTAL_ADDRESS,
    bridgedTokenAddress: bridgedTokenAddress.toString(),
    bridgeAddress: bridgeAddress.toString(),
    deployer: deployerAddress.toString(),
    deployedAt: new Date().toISOString(),
    status: "deployed",
  };

  const fs = await import("fs");
  const path = await import("path");
  const outputPath = path.join(process.cwd(), "bridge", ".l2-deployment.json");
  fs.writeFileSync(outputPath, JSON.stringify(deployConfig, null, 2));

  console.log("╔═══════════════════════════════════════════╗");
  console.log("║           Deployment Complete!            ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log();
  console.log("BridgedToken:      ", bridgedTokenAddress.toString());
  console.log("CelariTokenBridge: ", bridgeAddress.toString());
  console.log("Deployment config saved to:", outputPath);
  console.log();
  console.log("Next steps:");
  console.log("  1. Export L2_BRIDGE_ADDRESS=" + bridgeAddress.toString());
  console.log("  2. Re-deploy or re-initialize L1 portal with this L2 bridge address");
  console.log("     yarn bridge:deploy:l1");
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
