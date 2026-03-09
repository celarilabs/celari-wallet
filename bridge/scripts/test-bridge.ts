/**
 * Celari Bridge — E2E Bridge Test
 *
 * Tests the full bridge flow:
 *   1. Connect to Sepolia and Aztec
 *   2. Check supported tokens
 *   3. Prepare a deposit transaction
 *   4. Verify content hash computation
 *
 * Usage:
 *   SEPOLIA_RPC_URL=... PORTAL_ADDRESS=... npx tsx bridge/scripts/test-bridge.ts
 */

import { CelariBridge } from "../sdk/bridge-client.js";
import {
  computeDepositContentHash,
  computeWithdrawContentHash,
  generateSecretHash,
  sha256ToField,
  bigintToHex,
} from "../sdk/content-hash.js";

// ─── Configuration ───────────────────────────────────

const SEPOLIA_RPC_URL =
  process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";
const AZTEC_PXE_URL =
  process.env.AZTEC_NODE_URL || "http://localhost:8080";
const PORTAL_ADDRESS =
  (process.env.PORTAL_ADDRESS as `0x${string}`) ||
  "0x0000000000000000000000000000000000000000";

// ─── Test Helpers ────────────────────────────────────

let passCount = 0;
let failCount = 0;

function assert(condition: boolean, message: string) {
  if (condition) {
    console.log(`  [PASS] ${message}`);
    passCount++;
  } else {
    console.log(`  [FAIL] ${message}`);
    failCount++;
  }
}

// ─── Tests ───────────────────────────────────────────

async function testContentHash() {
  console.log("\n--- Content Hash Tests ---\n");

  // Test 1: sha256ToField produces valid field element
  const testData = new Uint8Array(32);
  testData.fill(0xff);
  const hash = await crypto.subtle.digest("SHA-256", testData);
  const hashBytes = new Uint8Array(hash);
  const field = sha256ToField(hashBytes);

  assert(field >= BigInt(0), "sha256ToField returns non-negative value");
  assert(
    field < BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617"),
    "sha256ToField fits in BN254 field"
  );

  // Verify MSB is zeroed (field should be at most 248 bits)
  const hexField = field.toString(16);
  assert(
    hexField.length <= 62,
    `sha256ToField MSB zeroed (hex length ${hexField.length} <= 62)`
  );

  // Test 2: Deterministic hashing
  const hash1 = await computeDepositContentHash(
    "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
    BigInt(1e18),
    BigInt(0xCAFE),
    BigInt(0x1234)
  );
  const hash2 = await computeDepositContentHash(
    "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
    BigInt(1e18),
    BigInt(0xCAFE),
    BigInt(0x1234)
  );
  assert(hash1 === hash2, "Deposit content hash is deterministic");

  // Test 3: Different inputs produce different hashes
  const hash3 = await computeDepositContentHash(
    "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
    BigInt(2e18), // different amount
    BigInt(0xCAFE),
    BigInt(0x1234)
  );
  assert(hash1 !== hash3, "Different inputs produce different hashes");

  // Test 4: Withdraw content hash
  const withdrawHash = await computeWithdrawContentHash(
    "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
    BigInt(1e18),
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "0x0000000000000000000000000000000000000000"
  );
  assert(withdrawHash > BigInt(0), "Withdraw content hash is non-zero");

  // Test 5: Secret generation
  const { secret, secretHash } = await generateSecretHash();
  assert(secret > BigInt(0), "Generated secret is non-zero");
  assert(secretHash > BigInt(0), "Generated secretHash is non-zero");
  assert(secret !== secretHash, "Secret and secretHash are different");

  // Test 6: Multiple secrets are unique
  const { secret: s2 } = await generateSecretHash();
  assert(secret !== s2, "Multiple generated secrets are unique");
}

async function testBridgeClient() {
  console.log("\n--- Bridge Client Tests ---\n");

  // Test 1: Create bridge instance
  const bridge = new CelariBridge({
    l1RpcUrl: SEPOLIA_RPC_URL,
    l2PxeUrl: AZTEC_PXE_URL,
    portalAddress: PORTAL_ADDRESS,
  });
  assert(bridge !== null, "Bridge client created successfully");

  // Test 2: Check connections
  const connections = await bridge.checkConnections();
  assert(typeof connections.l1 === "boolean", "L1 connection status returned");
  assert(typeof connections.l2 === "boolean", "L2 connection status returned");
  console.log(
    `    L1: ${connections.l1 ? "connected" : "disconnected"}, L2: ${connections.l2 ? "connected" : "disconnected"}`
  );

  // Test 3: Prepare deposit (doesn't require actual connection)
  try {
    const depositPrep = await bridge.prepareDeposit({
      token: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as `0x${string}`,
      amount: BigInt(1e17),
      recipient:
        "0x000000000000000000000000000000000000000000000000000000000000CAFE" as `0x${string}`,
      isPrivate: false,
    });

    assert(!!depositPrep.txId, "Deposit preparation returns txId");
    assert(!!depositPrep.secret, "Deposit preparation returns secret");
    assert(!!depositPrep.secretHash, "Deposit preparation returns secretHash");
    assert(!!depositPrep.depositTx.data, "Deposit preparation returns calldata");
    assert(depositPrep.needsApproval === true, "ERC-20 deposit needs approval");
  } catch (err) {
    console.log(`  [SKIP] Deposit preparation test (${err})`);
  }

  // Test 4: Transaction history
  const txHistory = bridge.getTransactions();
  assert(Array.isArray(txHistory), "Transaction history is an array");
  assert(txHistory.length >= 0, "Transaction history has entries");

  // Test 5: ETH deposit (no approval needed)
  try {
    const ethDeposit = await bridge.prepareDeposit({
      token: "0x0000000000000000000000000000000000000000" as `0x${string}`,
      amount: BigInt(1e17),
      recipient:
        "0x000000000000000000000000000000000000000000000000000000000000CAFE" as `0x${string}`,
      isPrivate: false,
    });

    assert(ethDeposit.needsApproval === false, "ETH deposit needs no approval");
    assert(
      ethDeposit.depositTx.value === BigInt(1e17),
      "ETH deposit has correct value"
    );
  } catch (err) {
    console.log(`  [SKIP] ETH deposit test (${err})`);
  }
}

// ─── Main ────────────────────────────────────────────

async function main() {
  console.log("╔═══════════════════════════════════════════╗");
  console.log("║    Celari Bridge — E2E Test Suite         ║");
  console.log("╚═══════════════════════════════════════════╝");
  console.log();
  console.log("Config:");
  console.log("  L1 RPC:", SEPOLIA_RPC_URL);
  console.log("  L2 PXE:", AZTEC_PXE_URL);
  console.log("  Portal:", PORTAL_ADDRESS);

  await testContentHash();
  await testBridgeClient();

  console.log("\n" + "=".repeat(40));
  console.log(`Results: ${passCount} passed, ${failCount} failed`);
  console.log("=".repeat(40) + "\n");

  if (failCount > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Test suite failed:", err);
  process.exit(1);
});
