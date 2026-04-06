import { describe, it, expect } from "@jest/globals";
import { DexClient } from "../../utils/dex.js";

describe("DexClient", () => {
  describe("without contract address", () => {
    const client = new DexClient("https://rpc.testnet.aztec-labs.com/");

    it("getQuote should throw DexNotAvailable", async () => {
      await expect(
        client.getQuote("0xtoken1", "0xtoken2", 1000n)
      ).rejects.toThrow("DEX contract not configured");
    });

    it("executeSwap should throw DexNotAvailable", async () => {
      await expect(
        client.executeSwap(
          { tokenIn: "0x1", tokenOut: "0x2", amountIn: 100n, amountOut: 99n, priceImpact: 0.01, estimatedGas: 500000n, expiresAt: Date.now() + 30000 },
          "0xwallet"
        )
      ).rejects.toThrow("DEX contract not configured");
    });

    it("getSupportedPairs should return empty array", async () => {
      const pairs = await client.getSupportedPairs();
      expect(pairs).toEqual([]);
    });

    it("isAvailable should return false", () => {
      expect(client.isAvailable()).toBe(false);
    });
  });

  describe("with contract address", () => {
    const client = new DexClient(
      "https://rpc.testnet.aztec-labs.com/",
      "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    );

    it("isAvailable should return true", () => {
      expect(client.isAvailable()).toBe(true);
    });

    it("getSupportedPairs should return hardcoded pairs", async () => {
      const pairs = await client.getSupportedPairs();
      expect(pairs.length).toBeGreaterThan(0);
      expect(pairs[0]).toHaveProperty("tokenA");
      expect(pairs[0]).toHaveProperty("tokenB");
    });
  });
});
