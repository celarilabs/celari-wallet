/**
 * Celari Bridge — Deploy L2 Contracts to Aztec Testnet
 *
 * Deploys CelariTokenBridge and BridgedToken contracts on Aztec.
 *
 * Usage:
 *   AZTEC_NODE_URL=... PORTAL_ADDRESS=... npx tsx bridge/scripts/deploy-l2.ts
 *
 * Environment variables:
 *   AZTEC_NODE_URL    — Aztec PXE endpoint (default: http://localhost:8080)
 *   PORTAL_ADDRESS    — L1 CelariBridgePortal address on Sepolia
 */

// ─── Configuration ───────────────────────────────────

const AZTEC_NODE_URL =
  process.env.AZTEC_NODE_URL || "http://localhost:8080";
const PORTAL_ADDRESS = process.env.PORTAL_ADDRESS;

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

  // Check PXE connection
  try {
    const response = await fetch(`${AZTEC_NODE_URL}/api/node-info`, {
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      throw new Error(`PXE responded with status ${response.status}`);
    }

    const nodeInfo = await response.json();
    console.log("Connected to Aztec node:");
    console.log("  Version:", nodeInfo.nodeVersion || "unknown");
    console.log("  Chain ID:", nodeInfo.l1ChainId || "unknown");
    console.log();
  } catch (err) {
    console.error("Error: Cannot connect to Aztec PXE at", AZTEC_NODE_URL);
    console.error("  Start sandbox: yarn start:sandbox");
    console.error("  Or set AZTEC_NODE_URL for testnet");
    process.exit(1);
  }

  // Deployment instructions
  console.log("Deployment steps:");
  console.log();
  console.log("1. Compile contracts:");
  console.log("   cd bridge/contracts/l2/bridged_token && aztec-nargo compile");
  console.log("   cd bridge/contracts/l2/celari_token_bridge && aztec-nargo compile");
  console.log();
  console.log("2. Generate TypeScript artifacts:");
  console.log("   aztec codegen bridge/contracts/l2/bridged_token/target -o bridge/sdk/artifacts");
  console.log("   aztec codegen bridge/contracts/l2/celari_token_bridge/target -o bridge/sdk/artifacts");
  console.log();
  console.log("3. Deploy BridgedToken:");
  console.log("   - Admin: your Aztec wallet address");
  console.log('   - Name: "Celari Bridged ETH" (encoded as Field)');
  console.log('   - Symbol: "cbETH" (encoded as Field)');
  console.log("   - Decimals: 18");
  console.log();
  console.log("4. Deploy CelariTokenBridge:");
  console.log("   - Token: BridgedToken address from step 3");
  console.log(`   - Portal: ${PORTAL_ADDRESS}`);
  console.log();
  console.log("5. Set minter on BridgedToken:");
  console.log("   Call BridgedToken.set_minter(bridge_address)");
  console.log();

  // Save deployment config
  const deployConfig = {
    network: "aztec-testnet",
    pxeUrl: AZTEC_NODE_URL,
    portalAddress: PORTAL_ADDRESS,
    deployedAt: new Date().toISOString(),
    status: "pending_deploy",
    instructions: {
      compile:
        "cd bridge/contracts/l2/celari_token_bridge && aztec-nargo compile",
      codegen:
        "aztec codegen bridge/contracts/l2/celari_token_bridge/target -o bridge/sdk/artifacts",
    },
  };

  const fs = await import("fs");
  const path = await import("path");
  const outputPath = path.join(
    process.cwd(),
    "bridge",
    ".l2-deployment.json"
  );
  fs.writeFileSync(outputPath, JSON.stringify(deployConfig, null, 2));
  console.log(`Deployment config saved to: ${outputPath}`);
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
