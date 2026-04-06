/**
 * Celari Bridge — L2 Client (Aztec Testnet)
 *
 * Handles all Aztec L2 interactions:
 * - Claiming deposited tokens (public and private)
 * - Initiating withdrawals back to L1
 * - Balance queries
 * - Transaction status tracking
 *
 * Uses @aztec/aztec.js for proper contract interaction via PXE.
 */

import { createAztecNodeClient } from "@aztec/aztec.js/node";
import { AztecAddress, EthAddress } from "@aztec/aztec.js/addresses";
import { Fr } from "@aztec/aztec.js/fields";
import { Contract } from "@aztec/aztec.js/contracts";
import { loadContractArtifact } from "@aztec/aztec.js/abi";
import type { Wallet } from "@aztec/aztec.js";

// ─── Types ───────────────────────────────────────────

export interface L2ClientConfig {
  pxeUrl: string;
  bridgeContractAddress?: string;
  tokenContractAddress?: string;
}

export interface ClaimParams {
  l1Token: string;
  to: string;
  amount: bigint;
  secret: bigint;
  leafIndex: number;
}

export interface ExitParams {
  l1Token: string;
  recipient: string;
  amount: bigint;
  callerOnL1: string;
  nonce: bigint;
}

export interface L2Balance {
  public: bigint;
  private: bigint;
}

export interface ClaimResult {
  success: boolean;
  txHash?: string;
  blockNumber?: number;
}

export interface ExitResult {
  success: boolean;
  txHash?: string;
  blockNumber?: number;
}

// ─── L2 Client ───────────────────────────────────────

export class L2Client {
  private pxeUrl: string;
  private bridgeAddress: string | null;
  private tokenAddress: string | null;
  private nodeClient: ReturnType<typeof createAztecNodeClient> | null = null;

  constructor(config: L2ClientConfig) {
    this.pxeUrl = config.pxeUrl;
    this.bridgeAddress = config.bridgeContractAddress || null;
    this.tokenAddress = config.tokenContractAddress || null;
  }

  /**
   * Connect to the Aztec node via PXE URL.
   */
  async connect(): Promise<boolean> {
    try {
      this.nodeClient = createAztecNodeClient(this.pxeUrl);
      const info = await this.nodeClient.getNodeInfo();
      return !!info.nodeVersion;
    } catch {
      this.nodeClient = null;
      return false;
    }
  }

  /**
   * Get node info.
   */
  async getNodeInfo(): Promise<{
    connected: boolean;
    chainId?: number;
    version?: string;
  }> {
    try {
      if (!this.nodeClient) {
        this.nodeClient = createAztecNodeClient(this.pxeUrl);
      }
      const info = await this.nodeClient.getNodeInfo();
      return {
        connected: true,
        chainId: info.l1ChainId,
        version: info.nodeVersion,
      };
    } catch {
      return { connected: false };
    }
  }

  /**
   * Get L2 public balance for a bridged token.
   */
  async getPublicBalance(
    account: string,
    wallet?: Wallet,
    bridgeArtifact?: any
  ): Promise<bigint> {
    if (!this.tokenAddress || !wallet || !bridgeArtifact) return BigInt(0);

    try {
      const tokenContract = await Contract.at(
        AztecAddress.fromString(this.tokenAddress),
        bridgeArtifact,
        wallet
      );
      const result = await tokenContract.methods
        .balance_of_public(AztecAddress.fromString(account))
        .simulate({ from: wallet.getAddress() });
      return BigInt(result.toString());
    } catch {
      return BigInt(0);
    }
  }

  /**
   * Get total supply of bridged token.
   */
  async getTotalSupply(wallet?: Wallet, tokenArtifact?: any): Promise<bigint> {
    if (!this.tokenAddress || !wallet || !tokenArtifact) return BigInt(0);

    try {
      const tokenContract = await Contract.at(
        AztecAddress.fromString(this.tokenAddress),
        tokenArtifact,
        wallet
      );
      const result = await tokenContract.methods
        .total_supply()
        .simulate({ from: wallet.getAddress() });
      return BigInt(result.toString());
    } catch {
      return BigInt(0);
    }
  }

  // ─── Claim Operations ──────────────────────────────

  /**
   * Claim deposited tokens publicly on L2.
   * Called after an L1 deposit has been confirmed and the message is available.
   *
   * @param wallet - The Aztec wallet to send the transaction from
   * @param bridgeArtifact - The CelariTokenBridge contract artifact
   * @param params - Claim parameters (l1Token, to, amount, secret, leafIndex)
   * @param paymentMethod - Fee payment method
   */
  async claimPublic(
    wallet: Wallet,
    bridgeArtifact: any,
    params: ClaimParams,
    paymentMethod: any
  ): Promise<ClaimResult> {
    if (!this.bridgeAddress) {
      throw new Error("Bridge contract address not configured");
    }

    try {
      const bridgeContract = await Contract.at(
        AztecAddress.fromString(this.bridgeAddress),
        bridgeArtifact,
        wallet
      );

      const receipt = await bridgeContract.methods
        .claim_public(
          EthAddress.fromString(params.l1Token),
          AztecAddress.fromString(params.to),
          new Fr(params.amount),
          new Fr(params.secret),
          new Fr(BigInt(params.leafIndex))
        )
        .send({
          from: wallet.getAddress(),
          fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
          wait: { timeout: 300_000 },
        });

      return {
        success: true,
        txHash: receipt.txHash.toString(),
        blockNumber: receipt.blockNumber,
      };
    } catch (err: any) {
      console.error("[L2Client] claimPublic failed:", err.message);
      return { success: false };
    }
  }

  /**
   * Claim deposited tokens privately on L2.
   *
   * @param wallet - The Aztec wallet
   * @param bridgeArtifact - The CelariTokenBridge contract artifact
   * @param params - Claim parameters
   * @param secretForRedeeming - Secret hash for the minted private note
   * @param paymentMethod - Fee payment method
   */
  async claimPrivate(
    wallet: Wallet,
    bridgeArtifact: any,
    params: Omit<ClaimParams, "to">,
    secretForRedeeming: bigint,
    paymentMethod: any
  ): Promise<ClaimResult> {
    if (!this.bridgeAddress) {
      throw new Error("Bridge contract address not configured");
    }

    try {
      const bridgeContract = await Contract.at(
        AztecAddress.fromString(this.bridgeAddress),
        bridgeArtifact,
        wallet
      );

      const receipt = await bridgeContract.methods
        .claim_private(
          EthAddress.fromString(params.l1Token),
          new Fr(secretForRedeeming),
          new Fr(params.amount),
          new Fr(params.secret),
          new Fr(BigInt(params.leafIndex))
        )
        .send({
          from: wallet.getAddress(),
          fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
          wait: { timeout: 300_000 },
        });

      return {
        success: true,
        txHash: receipt.txHash.toString(),
        blockNumber: receipt.blockNumber,
      };
    } catch (err: any) {
      console.error("[L2Client] claimPrivate failed:", err.message);
      return { success: false };
    }
  }

  // ─── Exit (Withdraw) Operations ────────────────────

  /**
   * Initiate a public withdrawal from L2 to L1.
   * Burns tokens on L2 and sends a message to the L1 portal.
   *
   * @param wallet - The Aztec wallet
   * @param bridgeArtifact - The CelariTokenBridge contract artifact
   * @param params - Exit parameters (l1Token, recipient, amount, callerOnL1, nonce)
   * @param paymentMethod - Fee payment method
   */
  async exitToL1Public(
    wallet: Wallet,
    bridgeArtifact: any,
    params: ExitParams,
    paymentMethod: any
  ): Promise<ExitResult> {
    if (!this.bridgeAddress) {
      throw new Error("Bridge contract address not configured");
    }

    try {
      const bridgeContract = await Contract.at(
        AztecAddress.fromString(this.bridgeAddress),
        bridgeArtifact,
        wallet
      );

      const receipt = await bridgeContract.methods
        .exit_to_l1_public(
          EthAddress.fromString(params.l1Token),
          EthAddress.fromString(params.recipient),
          new Fr(params.amount),
          EthAddress.fromString(params.callerOnL1),
          new Fr(params.nonce)
        )
        .send({
          from: wallet.getAddress(),
          fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
          wait: { timeout: 300_000 },
        });

      return {
        success: true,
        txHash: receipt.txHash.toString(),
        blockNumber: receipt.blockNumber,
      };
    } catch (err: any) {
      console.error("[L2Client] exitToL1Public failed:", err.message);
      return { success: false };
    }
  }

  /**
   * Initiate a private withdrawal from L2 to L1.
   * Burns private tokens and sends a message to the L1 portal.
   *
   * @param wallet - The Aztec wallet
   * @param bridgeArtifact - The CelariTokenBridge contract artifact
   * @param params - Exit parameters plus token address for private path
   * @param tokenAddress - The L2 BridgedToken address
   * @param paymentMethod - Fee payment method
   */
  async exitToL1Private(
    wallet: Wallet,
    bridgeArtifact: any,
    params: ExitParams,
    tokenAddress: string,
    paymentMethod: any
  ): Promise<ExitResult> {
    if (!this.bridgeAddress) {
      throw new Error("Bridge contract address not configured");
    }

    try {
      const bridgeContract = await Contract.at(
        AztecAddress.fromString(this.bridgeAddress),
        bridgeArtifact,
        wallet
      );

      const receipt = await bridgeContract.methods
        .exit_to_l1_private(
          AztecAddress.fromString(tokenAddress),
          EthAddress.fromString(params.l1Token),
          EthAddress.fromString(params.recipient),
          new Fr(params.amount),
          EthAddress.fromString(params.callerOnL1),
          new Fr(params.nonce)
        )
        .send({
          from: wallet.getAddress(),
          fee: { paymentMethod, estimateGas: true, estimatedGasPadding: 0.1 },
          wait: { timeout: 300_000 },
        });

      return {
        success: true,
        txHash: receipt.txHash.toString(),
        blockNumber: receipt.blockNumber,
      };
    } catch (err: any) {
      console.error("[L2Client] exitToL1Private failed:", err.message);
      return { success: false };
    }
  }

  // ─── Configuration ─────────────────────────────────

  /**
   * Set the bridge and token contract addresses.
   */
  setContracts(bridgeAddress: string, tokenAddress: string) {
    this.bridgeAddress = bridgeAddress;
    this.tokenAddress = tokenAddress;
  }

  /**
   * Get the configured bridge contract address.
   */
  getBridgeAddress(): string | null {
    return this.bridgeAddress;
  }

  /**
   * Get the configured token contract address.
   */
  getTokenAddress(): string | null {
    return this.tokenAddress;
  }
}
