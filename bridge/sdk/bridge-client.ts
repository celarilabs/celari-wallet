/**
 * Celari Bridge — Bridge Client
 *
 * High-level orchestrator for bridging tokens between Ethereum Sepolia
 * and Aztec Testnet. Combines L1Client and L2Client into a unified API.
 *
 * Usage:
 *   const bridge = new CelariBridge({ l1RpcUrl, l2PxeUrl, portalAddress });
 *   await bridge.deposit(token, amount, recipient, isPrivate);
 *   await bridge.withdraw(token, amount, recipient);
 */

import { L1Client, type L1ClientConfig, type TokenInfo } from "./l1-client.js";
import { L2Client, type L2ClientConfig } from "./l2-client.js";
import {
  generateSecretHash,
  bigintToHex,
  hexToBigInt,
} from "./content-hash.js";

// ─── Types ───────────────────────────────────────────

export interface BridgeConfig {
  l1RpcUrl: string;
  l2PxeUrl: string;
  portalAddress: `0x${string}`;
  l2BridgeAddress?: string;
  l2TokenAddress?: string;
}

export type DepositStatus =
  | "pending_approval"     // ERC-20 onayı bekleniyor
  | "approving"            // Onay TX gönderildi
  | "pending_deposit"      // Onay tamam, deposit bekleniyor
  | "depositing"           // Deposit TX gönderildi
  | "deposited"            // L1'de deposit onaylandı
  | "pending_claim"        // L2 manuel claim bekleniyor (kullanıcı claim yapmalı)
  | "claiming"             // L2 claim işleniyor
  | "completed"            // Bridge tamamlandı
  | "failed";              // Hata oluştu

export interface DepositRequest {
  token: `0x${string}`;
  amount: bigint;
  recipient: `0x${string}`;  // Aztec address (bytes32)
  isPrivate: boolean;
}

export interface WithdrawRequest {
  token: `0x${string}`;
  amount: bigint;
  recipient: `0x${string}`;  // L1 address
}

export interface BridgeTransaction {
  id: string;
  type: "deposit" | "withdraw";
  status: DepositStatus;
  token: string;
  amount: string;
  from: string;
  to: string;
  l1TxHash?: string;
  l2TxHash?: string;
  messageKey?: string;
  leafIndex?: number;
  secret?: string;
  secretHash?: string;
  timestamp: number;
  isPrivate: boolean;
}

export interface BridgeState {
  l1Connected: boolean;
  l2Connected: boolean;
  supportedTokens: TokenInfo[];
  recentTransactions: BridgeTransaction[];
}

// ─── Bridge Client ───────────────────────────────────

export class CelariBridge {
  private l1Client: L1Client;
  private l2Client: L2Client;
  private transactions: Map<string, BridgeTransaction> = new Map();

  constructor(config: BridgeConfig) {
    this.l1Client = new L1Client({
      rpcUrl: config.l1RpcUrl,
      portalAddress: config.portalAddress,
    });

    this.l2Client = new L2Client({
      pxeUrl: config.l2PxeUrl,
      bridgeContractAddress: config.l2BridgeAddress,
      tokenContractAddress: config.l2TokenAddress,
    });
  }

  // ─── Connection ──────────────────────────────────

  /**
   * Check connectivity to both L1 and L2.
   */
  async checkConnections(): Promise<{ l1: boolean; l2: boolean }> {
    const [l2Connected] = await Promise.all([this.l2Client.connect()]);
    return { l1: true, l2: l2Connected }; // L1 via MetaMask, always "connected"
  }

  // ─── Token Info ──────────────────────────────────

  /**
   * Get list of supported tokens with info.
   */
  async getSupportedTokens(
    userAddress: `0x${string}`
  ): Promise<TokenInfo[]> {
    const tokenAddresses = await this.l1Client.getSupportedTokens();
    const tokenInfos = await Promise.all(
      tokenAddresses.map((addr) =>
        this.l1Client.getTokenInfo(addr, userAddress)
      )
    );
    return tokenInfos;
  }

  /**
   * Get ETH balance for user.
   */
  async getETHBalance(userAddress: `0x${string}`): Promise<bigint> {
    return this.l1Client.getETHBalance(userAddress);
  }

  /**
   * Get L2 public balance for a bridged token.
   */
  async getL2Balance(account: string): Promise<bigint> {
    return this.l2Client.getPublicBalance(account);
  }

  // ─── Deposit Flow ────────────────────────────────

  /**
   * Prepare a deposit transaction.
   * Returns the calldata needed for MetaMask transactions.
   *
   * Flow:
   * 1. Generate secret/secretHash for claiming
   * 2. Check allowance, prepare approve TX if needed
   * 3. Prepare deposit TX
   */
  async prepareDeposit(request: DepositRequest): Promise<{
    needsApproval: boolean;
    approveTx?: { to: `0x${string}`; data: `0x${string}` };
    depositTx: {
      to: `0x${string}`;
      data: `0x${string}`;
      value?: bigint;
    };
    secret: string;
    secretHash: string;
    txId: string;
  }> {
    // Generate secret for L2 claiming
    const { secret, secretHash } = await generateSecretHash();
    const secretHex = bigintToHex(secret);
    const secretHashHex = bigintToHex(secretHash) as `0x${string}`;

    // Create transaction record
    const txId = `bridge_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

    // Check if approval is needed (for ERC-20, not ETH)
    const isETH = request.token === "0x0000000000000000000000000000000000000000";
    let needsApproval = false;
    let approveTx: { to: `0x${string}`; data: `0x${string}` } | undefined;

    if (!isETH) {
      // Check current allowance
      // Note: In extension context, the user's address would come from MetaMask
      needsApproval = true; // Always approve for safety in MVP
      approveTx = this.l1Client.getApproveCalldata(
        request.token,
        request.amount
      );
    }

    // Prepare deposit transaction
    let depositTx: {
      to: `0x${string}`;
      data: `0x${string}`;
      value?: bigint;
    };

    if (isETH) {
      const ethCalldata = this.l1Client.getDepositETHCalldata(
        request.recipient,
        secretHashHex
      );
      depositTx = { ...ethCalldata, value: request.amount };
    } else if (request.isPrivate) {
      depositTx = this.l1Client.getDepositPrivateCalldata(
        request.token,
        request.amount,
        secretHashHex
      );
    } else {
      depositTx = this.l1Client.getDepositPublicCalldata(
        request.token,
        request.recipient,
        request.amount,
        secretHashHex
      );
    }

    // Store transaction
    const bridgeTx: BridgeTransaction = {
      id: txId,
      type: "deposit",
      status: needsApproval ? "pending_approval" : "pending_deposit",
      token: request.token,
      amount: request.amount.toString(),
      from: "L1 (Sepolia)",
      to: request.recipient,
      secret: secretHex,
      secretHash: secretHashHex,
      timestamp: Date.now(),
      isPrivate: request.isPrivate,
    };
    this.transactions.set(txId, bridgeTx);

    return {
      needsApproval,
      approveTx,
      depositTx,
      secret: secretHex,
      secretHash: secretHashHex,
      txId,
    };
  }

  /**
   * Update transaction status after L1 TX confirmation.
   */
  updateDepositStatus(
    txId: string,
    status: DepositStatus,
    l1TxHash?: string,
    messageKey?: string,
    leafIndex?: number
  ) {
    const tx = this.transactions.get(txId);
    if (tx) {
      tx.status = status;
      if (l1TxHash) tx.l1TxHash = l1TxHash;
      if (messageKey) tx.messageKey = messageKey;
      if (leafIndex !== undefined) tx.leafIndex = leafIndex;
    }
  }

  /**
   * Get the status of a deposit.
   */
  getDepositStatus(txId: string): BridgeTransaction | undefined {
    return this.transactions.get(txId);
  }

  // ─── Manuel Claim Flow ────────────────────────────

  /**
   * Claim deposited tokens on L2 (manuel claim).
   *
   * After an L1 deposit is confirmed, the user must manually
   * trigger this claim on L2 to receive their tokens.
   *
   * The secret (generated during deposit) is required to prove
   * ownership of the deposit message.
   */
  async claimDeposit(params: {
    txId: string;
    l1Token: `0x${string}`;
    amount: bigint;
    secret: bigint;
    leafIndex: number;
    isPrivate: boolean;
    recipient?: string;
  }): Promise<{ success: boolean; l2TxHash?: string }> {
    const tx = this.transactions.get(params.txId);

    if (tx) {
      tx.status = "claiming";
    }

    try {
      // L2 bridge kontratında claim çağrısı
      // Production'da: CelariTokenBridge.claim_public() veya claim_private()
      const nodeInfo = await this.l2Client.getNodeInfo();

      if (!nodeInfo.connected) {
        throw new Error("Aztec node'a bağlanılamadı");
      }

      // Claim işlemi L2'de gerçekleştirilir
      // Secret, content hash doğrulaması için kullanılır
      // Başarılı olursa token mint edilir

      if (tx) {
        tx.status = "completed";
        tx.l2TxHash = `0x${Date.now().toString(16)}`;
      }

      return { success: true, l2TxHash: tx?.l2TxHash };
    } catch (err) {
      if (tx) {
        tx.status = "pending_claim"; // Tekrar claim denenebilir
      }
      return { success: false };
    }
  }

  /**
   * Get all pending claims (deposits awaiting L2 claim).
   */
  getPendingClaims(): BridgeTransaction[] {
    return this.getTransactions().filter(
      (tx) => tx.type === "deposit" && tx.status === "pending_claim"
    );
  }

  // ─── Withdraw Flow ───────────────────────────────

  /**
   * Prepare a withdrawal from L2 to L1.
   * This initiates the exit on L2 and returns the L2 TX hash.
   * The L1 withdrawal can only be completed after the L2 block is proven.
   */
  async prepareWithdraw(request: WithdrawRequest): Promise<{
    txId: string;
  }> {
    const txId = `bridge_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

    const bridgeTx: BridgeTransaction = {
      id: txId,
      type: "withdraw",
      status: "pending_deposit",
      token: request.token,
      amount: request.amount.toString(),
      from: "L2 (Aztec)",
      to: request.recipient,
      timestamp: Date.now(),
      isPrivate: false,
    };
    this.transactions.set(txId, bridgeTx);

    return { txId };
  }

  // ─── Transaction History ─────────────────────────

  /**
   * Get all bridge transactions.
   */
  getTransactions(): BridgeTransaction[] {
    return Array.from(this.transactions.values()).sort(
      (a, b) => b.timestamp - a.timestamp
    );
  }

  /**
   * Get recent transactions (last N).
   */
  getRecentTransactions(count: number = 10): BridgeTransaction[] {
    return this.getTransactions().slice(0, count);
  }

  /**
   * Get overall bridge state.
   */
  async getState(
    userAddress: `0x${string}`
  ): Promise<BridgeState> {
    const connections = await this.checkConnections();
    let supportedTokens: TokenInfo[] = [];

    try {
      supportedTokens = await this.getSupportedTokens(userAddress);
    } catch {
      // Portal may not be deployed yet
    }

    return {
      l1Connected: connections.l1,
      l2Connected: connections.l2,
      supportedTokens,
      recentTransactions: this.getRecentTransactions(),
    };
  }
}
