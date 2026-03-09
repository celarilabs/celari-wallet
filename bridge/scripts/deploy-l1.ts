/**
 * Celari Bridge — Deploy L1 Contracts to Sepolia
 *
 * Deploys CelariBridgePortal and initializes it with:
 * - Aztec Registry address
 * - L2 Bridge contract address
 * - WETH address
 * - Supported tokens
 *
 * Usage:
 *   SEPOLIA_RPC_URL=... PRIVATE_KEY=... npx tsx bridge/scripts/deploy-l1.ts
 *
 * Environment variables:
 *   SEPOLIA_RPC_URL     — Sepolia RPC endpoint (Infura/Alchemy)
 *   PRIVATE_KEY         — Deployer wallet private key
 *   L2_BRIDGE_ADDRESS   — L2 CelariTokenBridge address (Aztec, bytes32)
 *   REGISTRY_ADDRESS    — Aztec Registry on Sepolia (optional, uses known address)
 *   WETH_ADDRESS        — WETH on Sepolia (optional, uses known address)
 */

import {
  createWalletClient,
  createPublicClient,
  http,
  type Address,
  type Hash,
} from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

// ─── Known Addresses ─────────────────────────────────

const KNOWN_ADDRESSES = {
  // Aztec Testnet contracts on Sepolia
  registry: "0xa0bfb1b494fb49041e5c6e8c2c1be09cd171c6ba" as Address,
  inbox: "0x59f588603d55a45dd3e57d50403c7c359a39bfc9" as Address,
  outbox: "0x5fe98f5a4de64f7b5920b038cd32937ca30bab32" as Address,
  // Sepolia WETH
  weth: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as Address,
  // Common testnet tokens
  sepoliaUSDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as Address,
};

// ─── Main ────────────────────────────────────────────

async function main() {
  const rpcUrl = process.env.SEPOLIA_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;
  const l2BridgeAddress = process.env.L2_BRIDGE_ADDRESS;

  if (!rpcUrl) {
    console.error("Error: SEPOLIA_RPC_URL environment variable required");
    console.error("  Example: export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY");
    process.exit(1);
  }
  if (!privateKey) {
    console.error("Error: PRIVATE_KEY environment variable required");
    process.exit(1);
  }
  if (!l2BridgeAddress) {
    console.error("Error: L2_BRIDGE_ADDRESS environment variable required");
    console.error("  Deploy L2 contracts first: yarn bridge:deploy:l2");
    process.exit(1);
  }

  const registryAddress =
    (process.env.REGISTRY_ADDRESS as Address) || KNOWN_ADDRESSES.registry;
  const wethAddress =
    (process.env.WETH_ADDRESS as Address) || KNOWN_ADDRESSES.weth;

  // Create clients
  const account = privateKeyToAccount(privateKey as `0x${string}`);
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl),
  });
  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(rpcUrl),
  });

  console.log("╔═══════════════════════════════════════════╗");
  console.log("║   Celari Bridge — L1 Deployment (Sepolia) ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log();
  console.log("Deployer:", account.address);
  console.log("Registry:", registryAddress);
  console.log("L2 Bridge:", l2BridgeAddress);
  console.log("WETH:", wethAddress);
  console.log();

  // Check balance
  const balance = await publicClient.getBalance({
    address: account.address,
  });
  console.log(
    "Deployer balance:",
    (Number(balance) / 1e18).toFixed(4),
    "ETH"
  );
  if (balance < BigInt(0.01e18)) {
    console.error("Error: Insufficient balance. Need at least 0.01 ETH for deployment.");
    console.error("Get Sepolia ETH from: https://sepoliafaucet.com/");
    process.exit(1);
  }

  // Note: In production, we would compile and deploy the contract here.
  // For this script, we show the deployment flow.
  console.log();
  console.log("To deploy CelariBridgePortal:");
  console.log("  1. cd bridge/contracts/l1");
  console.log("  2. forge create CelariBridgePortal \\");
  console.log(`       --rpc-url ${rpcUrl} \\`);
  console.log(`       --private-key $PRIVATE_KEY`);
  console.log();
  console.log("After deployment, initialize with:");
  console.log("  cast send <PORTAL_ADDRESS> \\");
  console.log(`    "initialize(address,bytes32,address)" \\`);
  console.log(`    ${registryAddress} \\`);
  console.log(`    ${l2BridgeAddress} \\`);
  console.log(`    ${wethAddress} \\`);
  console.log(`    --rpc-url ${rpcUrl} \\`);
  console.log("    --private-key $PRIVATE_KEY");
  console.log();
  console.log("Then add supported tokens:");
  console.log("  cast send <PORTAL_ADDRESS> \\");
  console.log(`    "addSupportedToken(address)" \\`);
  console.log(`    ${wethAddress} \\`);
  console.log(`    --rpc-url ${rpcUrl} \\`);
  console.log("    --private-key $PRIVATE_KEY");
  console.log();

  // Save deployment info
  const deployInfo = {
    network: "sepolia",
    registry: registryAddress,
    l2Bridge: l2BridgeAddress,
    weth: wethAddress,
    deployer: account.address,
    deployedAt: new Date().toISOString(),
    status: "pending_deploy",
  };

  const fs = await import("fs");
  const path = await import("path");
  const outputPath = path.join(
    process.cwd(),
    "bridge",
    ".l1-deployment.json"
  );
  fs.writeFileSync(outputPath, JSON.stringify(deployInfo, null, 2));
  console.log(`Deployment info saved to: ${outputPath}`);
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
