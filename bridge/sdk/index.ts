/**
 * Celari Bridge SDK
 *
 * Public API for the bridge module.
 */

export { CelariBridge } from "./bridge-client.js";
export type {
  BridgeConfig,
  BridgeTransaction,
  BridgeState,
  DepositRequest,
  WithdrawRequest,
  DepositStatus,
} from "./bridge-client.js";

export { L1Client } from "./l1-client.js";
export type { L1ClientConfig, DepositResult, TokenInfo } from "./l1-client.js";

export { L2Client } from "./l2-client.js";
export type { L2ClientConfig, ClaimParams, ExitParams, L2Balance, ClaimResult, ExitResult } from "./l2-client.js";

export {
  computeDepositContentHash,
  computeWithdrawContentHash,
  generateSecretHash,
  sha256ToField,
  bigintToHex,
  hexToBigInt,
  bigintToBytes32,
  addressToBytes32,
} from "./content-hash.js";
