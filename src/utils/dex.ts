import { AztecAddress } from "@aztec/aztec.js";

export interface SwapQuote {
  tokenIn: string;
  tokenOut: string;
  amountIn: bigint;
  amountOut: bigint;
  priceImpact: number;
  estimatedGas: bigint;
  expiresAt: number;
}

export interface TokenPair {
  tokenA: string;
  tokenB: string;
  liquidity: bigint;
}

/** Default pairs — will be replaced with on-chain query when DEX contract is live. */
const DEFAULT_PAIRS: TokenPair[] = [
  { tokenA: "ETH", tokenB: "zkUSD", liquidity: 0n },
  { tokenA: "ETH", tokenB: "DAI", liquidity: 0n },
  { tokenA: "zkUSD", tokenB: "DAI", liquidity: 0n },
];

/**
 * Client for interacting with DEX contracts on Aztec.
 *
 * When constructed without a contract address, all trading methods throw
 * "DEX contract not configured". This allows the UI to gracefully show
 * "DEX not available" instead of crashing.
 *
 * When a contract address is provided, methods will interact with the
 * on-chain AMM (not yet implemented — requires deployed DEX contract).
 */
export class DexClient {
  private nodeUrl: string;
  private contractAddress: string | undefined;

  constructor(nodeUrl: string, dexContractAddress?: string) {
    this.nodeUrl = nodeUrl;
    this.contractAddress = dexContractAddress;
  }

  /** Whether a DEX contract is configured and trading is possible. */
  isAvailable(): boolean {
    return this.contractAddress !== undefined;
  }

  /**
   * Get a swap quote from the DEX.
   * Throws if no contract address is configured.
   */
  async getQuote(
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    slippage: number = 0.01
  ): Promise<SwapQuote> {
    if (!this.contractAddress) {
      throw new Error("DEX contract not configured");
    }
    const slippageBps = BigInt(Math.floor(slippage * 10000));
    const estimatedOut = amountIn * (10000n - slippageBps) / 10000n;
    return {
      tokenIn,
      tokenOut,
      amountIn,
      amountOut: estimatedOut,
      priceImpact: slippage,
      estimatedGas: 500000n,
      expiresAt: Date.now() + 30000,
    };
  }

  /**
   * Execute a swap through the DEX contract.
   * Throws if no contract address is configured.
   */
  async executeSwap(quote: SwapQuote, walletAddress: string): Promise<string> {
    if (!this.contractAddress) {
      throw new Error("DEX contract not configured");
    }
    throw new Error("DEX swap execution not yet implemented — awaiting contract deployment");
  }

  /**
   * Get available trading pairs.
   * Returns hardcoded defaults when contract is configured, empty otherwise.
   */
  async getSupportedPairs(): Promise<TokenPair[]> {
    if (!this.contractAddress) {
      return [];
    }
    return DEFAULT_PAIRS;
  }
}
