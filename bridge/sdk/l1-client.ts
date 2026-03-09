/**
 * Celari Bridge — L1 Client (Sepolia)
 *
 * Handles all Ethereum L1 interactions using viem:
 * - ERC-20 approval and deposit to portal
 * - ETH wrapping and deposit
 * - Withdrawal from portal (consuming Outbox messages)
 * - Transaction status tracking
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Hash,
  type PublicClient,
  type WalletClient,
  type Chain,
  parseAbi,
  encodeFunctionData,
} from "viem";
import { sepolia } from "viem/chains";

// ─── Contract ABIs ───────────────────────────────────

const PORTAL_ABI = parseAbi([
  "function initialize(address registry, bytes32 l2Bridge, address weth) external",
  "function depositToAztecPublic(address token, bytes32 to, uint256 amount, bytes32 secretHash) external returns (bytes32, uint256)",
  "function depositToAztecPrivate(address token, uint256 amount, bytes32 secretHash) external returns (bytes32, uint256)",
  "function depositETHToAztecPublic(bytes32 to, bytes32 secretHash) external payable returns (bytes32, uint256)",
  "function withdraw(address token, address recipient, uint256 amount, bool withCaller, uint256 blockNumber, uint256 leafIndex, bytes32[] path) external",
  "function supportedTokens(address) external view returns (bool)",
  "function getSupportedTokens() external view returns (address[])",
  "function getLockedBalance(address token) external view returns (uint256)",
  "function depositCount() external view returns (uint256)",
  "function getDepositContentHash(address token, uint256 amount, bytes32 to, bytes32 secretHash) external pure returns (bytes32)",
  "event DepositToAztecPublic(address indexed token, bytes32 indexed to, uint256 amount, bytes32 secretHash, bytes32 key, uint256 index)",
  "event DepositToAztecPrivate(address indexed token, uint256 amount, bytes32 secretHash, bytes32 key, uint256 index)",
  "event WithdrawFromAztec(address indexed token, address indexed recipient, uint256 amount)",
]);

const ERC20_ABI = parseAbi([
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint8)",
]);

// ─── Types ───────────────────────────────────────────

export interface L1ClientConfig {
  rpcUrl: string;
  portalAddress: Address;
  chain?: Chain;
}

export interface DepositResult {
  txHash: Hash;
  messageKey: string;
  leafIndex: number;
}

export interface TokenInfo {
  address: Address;
  symbol: string;
  decimals: number;
  balance: bigint;
}

// ─── L1 Client ───────────────────────────────────────

export class L1Client {
  private publicClient: PublicClient;
  private portalAddress: Address;
  private chain: Chain;

  constructor(config: L1ClientConfig) {
    this.chain = config.chain || sepolia;
    this.portalAddress = config.portalAddress;

    this.publicClient = createPublicClient({
      chain: this.chain,
      transport: http(config.rpcUrl),
    });
  }

  // ─── Read Operations ─────────────────────────────

  /**
   * Get the list of supported tokens on the portal.
   */
  async getSupportedTokens(): Promise<Address[]> {
    const tokens = await this.publicClient.readContract({
      address: this.portalAddress,
      abi: PORTAL_ABI,
      functionName: "getSupportedTokens",
    });
    return tokens as Address[];
  }

  /**
   * Check if a token is supported by the portal.
   */
  async isTokenSupported(token: Address): Promise<boolean> {
    return (await this.publicClient.readContract({
      address: this.portalAddress,
      abi: PORTAL_ABI,
      functionName: "supportedTokens",
      args: [token],
    })) as boolean;
  }

  /**
   * Get the locked balance of a token in the portal.
   */
  async getLockedBalance(token: Address): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.portalAddress,
      abi: PORTAL_ABI,
      functionName: "getLockedBalance",
      args: [token],
    })) as bigint;
  }

  /**
   * Get token info (symbol, decimals, balance).
   */
  async getTokenInfo(token: Address, account: Address): Promise<TokenInfo> {
    const [symbol, decimals, balance] = await Promise.all([
      this.publicClient.readContract({
        address: token,
        abi: ERC20_ABI,
        functionName: "symbol",
      }),
      this.publicClient.readContract({
        address: token,
        abi: ERC20_ABI,
        functionName: "decimals",
      }),
      this.publicClient.readContract({
        address: token,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [account],
      }),
    ]);

    return {
      address: token,
      symbol: symbol as string,
      decimals: decimals as number,
      balance: balance as bigint,
    };
  }

  /**
   * Get the total number of deposits.
   */
  async getDepositCount(): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.portalAddress,
      abi: PORTAL_ABI,
      functionName: "depositCount",
    })) as bigint;
  }

  /**
   * Get the ETH balance of an account.
   */
  async getETHBalance(account: Address): Promise<bigint> {
    return this.publicClient.getBalance({ address: account });
  }

  /**
   * Get the current allowance for the portal to spend tokens.
   */
  async getAllowance(token: Address, owner: Address): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: token,
      abi: ERC20_ABI,
      functionName: "allowance",
      args: [owner, this.portalAddress],
    })) as bigint;
  }

  /**
   * Wait for a transaction to be confirmed.
   */
  async waitForTransaction(txHash: Hash) {
    return this.publicClient.waitForTransactionReceipt({ hash: txHash });
  }

  // ─── Calldata Generation ─────────────────────────
  // These methods generate transaction calldata that can be sent
  // via MetaMask or other wallet providers in the extension.

  /**
   * Generate calldata for ERC-20 approval.
   */
  getApproveCalldata(token: Address, amount: bigint): {
    to: Address;
    data: `0x${string}`;
  } {
    return {
      to: token,
      data: encodeFunctionData({
        abi: ERC20_ABI,
        functionName: "approve",
        args: [this.portalAddress, amount],
      }),
    };
  }

  /**
   * Generate calldata for public deposit.
   */
  getDepositPublicCalldata(
    token: Address,
    to: `0x${string}`,
    amount: bigint,
    secretHash: `0x${string}`
  ): { to: Address; data: `0x${string}` } {
    return {
      to: this.portalAddress,
      data: encodeFunctionData({
        abi: PORTAL_ABI,
        functionName: "depositToAztecPublic",
        args: [token, to as `0x${string}`, amount, secretHash as `0x${string}`],
      }),
    };
  }

  /**
   * Generate calldata for private deposit.
   */
  getDepositPrivateCalldata(
    token: Address,
    amount: bigint,
    secretHash: `0x${string}`
  ): { to: Address; data: `0x${string}` } {
    return {
      to: this.portalAddress,
      data: encodeFunctionData({
        abi: PORTAL_ABI,
        functionName: "depositToAztecPrivate",
        args: [token, amount, secretHash as `0x${string}`],
      }),
    };
  }

  /**
   * Generate calldata for ETH deposit.
   */
  getDepositETHCalldata(
    to: `0x${string}`,
    secretHash: `0x${string}`
  ): { to: Address; data: `0x${string}`; value: bigint } {
    return {
      to: this.portalAddress,
      data: encodeFunctionData({
        abi: PORTAL_ABI,
        functionName: "depositETHToAztecPublic",
        args: [to as `0x${string}`, secretHash as `0x${string}`],
      }),
      value: BigInt(0), // Set by caller
    };
  }

  /**
   * Generate calldata for withdrawal.
   */
  getWithdrawCalldata(
    token: Address,
    recipient: Address,
    amount: bigint,
    withCaller: boolean,
    blockNumber: bigint,
    leafIndex: bigint,
    path: `0x${string}`[]
  ): { to: Address; data: `0x${string}` } {
    return {
      to: this.portalAddress,
      data: encodeFunctionData({
        abi: PORTAL_ABI,
        functionName: "withdraw",
        args: [
          token,
          recipient,
          amount,
          withCaller,
          blockNumber,
          leafIndex,
          path,
        ],
      }),
    };
  }

  /**
   * Compute the deposit content hash (for verification).
   */
  async getDepositContentHash(
    token: Address,
    amount: bigint,
    to: `0x${string}`,
    secretHash: `0x${string}`
  ): Promise<`0x${string}`> {
    return (await this.publicClient.readContract({
      address: this.portalAddress,
      abi: PORTAL_ABI,
      functionName: "getDepositContentHash",
      args: [token, amount, to, secretHash],
    })) as `0x${string}`;
  }
}
