import { describe, it, expect } from "@jest/globals";
import {
  sha256ToField,
  bigintToBytes32,
  addressToBytes32,
  computeDepositContentHash,
  computeWithdrawContentHash,
  generateSecretHash,
  hexToBigInt,
  bigintToHex,
} from "../content-hash.js";

describe("Content Hash Utilities", () => {
  describe("sha256ToField", () => {
    it("should zero the MSB (byte 0) for BN254 compatibility", () => {
      const hash = new Uint8Array(32);
      hash[0] = 0xff;
      hash[1] = 0x01;
      const field = sha256ToField(hash);
      expect(field).toBe(BigInt("0x01") << BigInt(240));
    });

    it("should produce deterministic output", () => {
      const hash = new Uint8Array(32).fill(0xab);
      const a = sha256ToField(hash);
      const b = sha256ToField(hash);
      expect(a).toBe(b);
    });
  });

  describe("bigintToBytes32", () => {
    it("should encode zero as 32 zero bytes", () => {
      const bytes = bigintToBytes32(0n);
      expect(bytes.length).toBe(32);
      expect(bytes.every(b => b === 0)).toBe(true);
    });

    it("should encode 1 as last byte = 1", () => {
      const bytes = bigintToBytes32(1n);
      expect(bytes[31]).toBe(1);
      expect(bytes[30]).toBe(0);
    });

    it("should roundtrip with hexToBigInt", () => {
      const original = 123456789n;
      const bytes = bigintToBytes32(original);
      const hex = "0x" + Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
      expect(hexToBigInt(hex)).toBe(original);
    });
  });

  describe("addressToBytes32", () => {
    it("should right-align 20-byte address in 32 bytes", () => {
      const bytes = addressToBytes32("0x" + "ff".repeat(20));
      for (let i = 0; i < 12; i++) expect(bytes[i]).toBe(0);
      for (let i = 12; i < 32; i++) expect(bytes[i]).toBe(0xff);
    });

    it("should handle address without 0x prefix", () => {
      const bytes = addressToBytes32("aa".repeat(20));
      expect(bytes[12]).toBe(0xaa);
    });
  });

  describe("computeDepositContentHash", () => {
    it("should produce a field element (< 2^254)", async () => {
      const hash = await computeDepositContentHash(
        "0x" + "11".repeat(20),
        1000n,
        42n,
        99n,
      );
      expect(hash).toBeGreaterThan(0n);
      expect(hash).toBeLessThan(2n ** 254n);
    });

    it("should be deterministic", async () => {
      const args = ["0x" + "ab".repeat(20), 500n, 1n, 2n] as const;
      const a = await computeDepositContentHash(...args);
      const b = await computeDepositContentHash(...args);
      expect(a).toBe(b);
    });
  });

  describe("computeWithdrawContentHash", () => {
    it("should produce a field element", async () => {
      const hash = await computeWithdrawContentHash(
        "0x" + "11".repeat(20),
        1000n,
        "0x" + "22".repeat(20),
        "0x" + "33".repeat(20),
      );
      expect(hash).toBeGreaterThan(0n);
      expect(hash).toBeLessThan(2n ** 254n);
    });
  });

  describe("generateSecretHash", () => {
    it("should produce secret and secretHash as bigints", async () => {
      const { secret, secretHash } = await generateSecretHash();
      expect(typeof secret).toBe("bigint");
      expect(typeof secretHash).toBe("bigint");
      expect(secret).toBeGreaterThan(0n);
      expect(secretHash).toBeGreaterThan(0n);
    });

    it("should produce unique secrets", async () => {
      const a = await generateSecretHash();
      const b = await generateSecretHash();
      expect(a.secret).not.toBe(b.secret);
    });
  });

  describe("hex conversion", () => {
    it("hexToBigInt should parse 0x prefix", () => {
      expect(hexToBigInt("0xff")).toBe(255n);
    });

    it("hexToBigInt should parse without prefix", () => {
      expect(hexToBigInt("ff")).toBe(255n);
    });

    it("bigintToHex should produce 64-char padded hex", () => {
      const hex = bigintToHex(255n);
      expect(hex).toBe("0x" + "0".repeat(62) + "ff");
      expect(hex.length).toBe(66);
    });
  });
});
