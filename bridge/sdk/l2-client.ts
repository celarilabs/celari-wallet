/**
 * Celari Bridge — L2 Client (Aztec Testnet)
 *
 * Handles all Aztec L2 interactions using @aztec/aztec.js:
 * - Claiming deposited tokens (public and private)
 * - Initiating withdrawals back to L1
 * - Balance queries
 * - Transaction status tracking
 */

import type { AztecAddress, PXE, Wallet, Fr } from "@aztec/aztec.js";

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

// ─── L2 Client ───────────────────────────────────────

export class L2Client {
  private pxeUrl: string;
  private bridgeAddress: string | null;
  private tokenAddress: string | null;
  private pxe: PXE | null = null;

  constructor(config: L2ClientConfig) {
    this.pxeUrl = config.pxeUrl;
    this.bridgeAddress = config.bridgeContractAddress || null;
    this.tokenAddress = config.tokenContractAddress || null;
  }

  /**
   * Connect to the PXE node.
   */
  async connect(): Promise<boolean> {
    try {
      const response = await fetch(`${this.pxeUrl}/api/node-info`, {
        signal: AbortSignal.timeout(5000),
      });
      return response.ok;
    } catch {
      return false;
    }
  }

  /**
   * Get L2 public balance for a bridged token.
   */
  async getPublicBalance(account: string): Promise<bigint> {
    if (!this.tokenAddress) return BigInt(0);

    try {
      const response = await fetch(`${this.pxeUrl}/api/view`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contractAddress: this.tokenAddress,
          functionName: "balance_of_public",
          args: [account],
        }),
      });

      if (response.ok) {
        const result = await response.json();
        return BigInt(result.value || "0");
      }
    } catch {
      // Fall through
    }
    return BigInt(0);
  }

  /**
   * Get total supply of bridged token.
   */
  async getTotalSupply(): Promise<bigint> {
    if (!this.tokenAddress) return BigInt(0);

    try {
      const response = await fetch(`${this.pxeUrl}/api/view`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contractAddress: this.tokenAddress,
          functionName: "total_supply",
          args: [],
        }),
      });

      if (response.ok) {
        const result = await response.json();
        return BigInt(result.value || "0");
      }
    } catch {
      // Fall through
    }
    return BigInt(0);
  }

  /**
   * Check if the PXE node is connected and accessible.
   */
  async getNodeInfo(): Promise<{
    connected: boolean;
    chainId?: number;
    version?: string;
  }> {
    try {
      const response = await fetch(`${this.pxeUrl}/api/node-info`, {
        signal: AbortSignal.timeout(5000),
      });
      if (response.ok) {
        const info = await response.json();
        return {
          connected: true,
          chainId: info.l1ChainId,
          version: info.nodeVersion,
        };
      }
    } catch {
      // Fall through
    }
    return { connected: false };
  }

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
