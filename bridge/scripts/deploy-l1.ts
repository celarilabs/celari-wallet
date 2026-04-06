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
 *   SEPOLIA_RPC_URL=... PRIVATE_KEY=... L2_BRIDGE_ADDRESS=... npx tsx bridge/scripts/deploy-l1.ts
 *
 * Environment variables:
 *   SEPOLIA_RPC_URL     — Sepolia RPC endpoint (Infura/Alchemy)
 *   PRIVATE_KEY         — Deployer wallet private key (0x-prefixed)
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
  encodeDeployData,
  encodeFunctionData,
} from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import { join } from "path";

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

// ─── ABI (from compiled artifact) ────────────────────

const PORTAL_ABI = [
  {
    type: "constructor",
    inputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [
      { name: "_registry", type: "address" },
      { name: "_l2Bridge", type: "bytes32" },
      { name: "_weth", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "addSupportedToken",
    inputs: [{ name: "token", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

// ─── Load Bytecode ────────────────────────────────────

function loadBytecode(): `0x${string}` {
  const artifactPath = join(
    process.cwd(),
    "bridge/contracts/l1/out/CelariBridgePortal.sol/CelariBridgePortal.json"
  );
  try {
    const artifact = JSON.parse(readFileSync(artifactPath, "utf-8"));
    const bytecode = artifact?.bytecode?.object as string | undefined;
    if (!bytecode) {
      throw new Error("bytecode.object not found in artifact");
    }
    return (bytecode.startsWith("0x") ? bytecode : `0x${bytecode}`) as `0x${string}`;
  } catch (err) {
    console.error("Error loading bytecode from compiled artifact:", err);
    console.error("Run `cd bridge/contracts/l1 && forge build` first.");
    process.exit(1);
  }
}

// ─── Helpers ─────────────────────────────────────────

async function waitForReceipt(
  publicClient: ReturnType<typeof createPublicClient>,
  hash: Hash,
  label: string
) {
  console.log(`  Waiting for ${label} (${hash})...`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    throw new Error(`Transaction ${label} reverted (status: ${receipt.status})`);
  }
  console.log(`  ${label} confirmed in block ${receipt.blockNumber}`);
  return receipt;
}

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
  const balance = await publicClient.getBalance({ address: account.address });
  console.log("Deployer balance:", (Number(balance) / 1e18).toFixed(4), "ETH");
  if (balance < BigInt("10000000000000000")) {
    // 0.01 ETH
    console.error("Error: Insufficient balance. Need at least 0.01 ETH for deployment.");
    console.error("Get Sepolia ETH from: https://sepoliafaucet.com/");
    process.exit(1);
  }

  // Load compiled bytecode
  console.log("Loading compiled bytecode...");
  const bytecode = loadBytecode();
  console.log("Bytecode loaded:", bytecode.length / 2 - 1, "bytes");
  console.log();

  // ─── Step 1: Deploy CelariBridgePortal ───────────

  console.log("Step 1: Deploying CelariBridgePortal...");
  const deployHash = await walletClient.deployContract({
    abi: PORTAL_ABI,
    bytecode,
    args: [],
  });
  const deployReceipt = await waitForReceipt(publicClient, deployHash, "deploy");
  const portalAddress = deployReceipt.contractAddress;
  if (!portalAddress) {
    throw new Error("Deploy succeeded but contractAddress is null");
  }
  console.log("CelariBridgePortal deployed at:", portalAddress);
  console.log();

  // ─── Step 2: Initialize ──────────────────────────

  console.log("Step 2: Initializing portal...");
  const l2BridgeBytes32 = l2BridgeAddress.startsWith("0x")
    ? (l2BridgeAddress.padEnd(66, "0") as `0x${string}`)
    : (`0x${l2BridgeAddress.padEnd(64, "0")}` as `0x${string}`);

  const initHash = await walletClient.writeContract({
    address: portalAddress,
    abi: PORTAL_ABI,
    functionName: "initialize",
    args: [registryAddress, l2BridgeBytes32 as `0x${string}`, wethAddress],
  });
  await waitForReceipt(publicClient, initHash, "initialize");
  console.log();

  // ─── Step 3: Add supported tokens ───────────────

  console.log("Step 3: Adding supported tokens...");

  // Add WETH
  const addWethHash = await walletClient.writeContract({
    address: portalAddress,
    abi: PORTAL_ABI,
    functionName: "addSupportedToken",
    args: [wethAddress],
  });
  await waitForReceipt(publicClient, addWethHash, "addSupportedToken(WETH)");
  console.log("  WETH added:", wethAddress);

  // Add USDC if on Sepolia
  const usdcAddress = KNOWN_ADDRESSES.sepoliaUSDC;
  const addUsdcHash = await walletClient.writeContract({
    address: portalAddress,
    abi: PORTAL_ABI,
    functionName: "addSupportedToken",
    args: [usdcAddress],
  });
  await waitForReceipt(publicClient, addUsdcHash, "addSupportedToken(USDC)");
  console.log("  USDC added:", usdcAddress);
  console.log();

  // ─── Save deployment info ────────────────────────

  const deployInfo = {
    network: "sepolia",
    portalAddress,
    registry: registryAddress,
    l2Bridge: l2BridgeAddress,
    weth: wethAddress,
    supportedTokens: [wethAddress, usdcAddress],
    deployer: account.address,
    deployTxHash: deployHash,
    initTxHash: initHash,
    deployedAt: new Date().toISOString(),
    status: "deployed",
  };

  const fs = await import("fs");
  const path = await import("path");
  const outputPath = path.join(process.cwd(), "bridge", ".l1-deployment.json");
  fs.writeFileSync(outputPath, JSON.stringify(deployInfo, null, 2));

  console.log("╔═══════════════════════════════════════════╗");
  console.log("║           Deployment Complete!            ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log();
  console.log("CelariBridgePortal:", portalAddress);
  console.log("Deployment info saved to:", outputPath);
  console.log();
  console.log("Next steps:");
  console.log("  1. Export PORTAL_ADDRESS=" + portalAddress);
  console.log("  2. Deploy L2 contracts: yarn bridge:deploy:l2");
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
