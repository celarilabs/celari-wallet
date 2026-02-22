/**
 * Unit tests for passkey utility functions.
 * These run without the Aztec sandbox — pure TypeScript logic.
 */

import { describe, it, expect } from "@jest/globals";
import {
  bytesToHex,
  hexToBytes,
  bytesToBase64Url,
  normalizeP256Signature,
  padTo32Bytes,
} from "../../utils/passkey.js";

describe("Passkey Utilities", () => {
  // ─── bytesToHex ──────────────────────────────────────

  describe("bytesToHex", () => {
    it("should convert empty bytes to 0x", () => {
      expect(bytesToHex(new Uint8Array([]))).toBe("0x");
    });

    it("should convert single byte", () => {
      expect(bytesToHex(new Uint8Array([0xff]))).toBe("0xff");
      expect(bytesToHex(new Uint8Array([0x00]))).toBe("0x00");
      expect(bytesToHex(new Uint8Array([0x0a]))).toBe("0x0a");
    });

    it("should convert 32-byte P256 coordinate", () => {
      const bytes = new Uint8Array(32);
      bytes[0] = 0xab;
      bytes[31] = 0xcd;
      const hex = bytesToHex(bytes);
      expect(hex).toMatch(/^0x[0-9a-f]{64}$/);
      expect(hex.startsWith("0xab")).toBe(true);
      expect(hex.endsWith("cd")).toBe(true);
    });

    it("should pad single-digit hex values with leading zero", () => {
      expect(bytesToHex(new Uint8Array([1, 2, 3]))).toBe("0x010203");
    });
  });

  // ─── hexToBytes ──────────────────────────────────────

  describe("hexToBytes", () => {
    it("should handle 0x prefix", () => {
      const bytes = hexToBytes("0xff00");
      expect(bytes).toEqual(new Uint8Array([0xff, 0x00]));
    });

    it("should handle without 0x prefix", () => {
      const bytes = hexToBytes("abcd");
      expect(bytes).toEqual(new Uint8Array([0xab, 0xcd]));
    });

    it("should round-trip with bytesToHex", () => {
      const original = new Uint8Array([1, 2, 3, 255, 0, 128]);
      const hex = bytesToHex(original);
      const restored = hexToBytes(hex);
      expect(Array.from(restored)).toEqual(Array.from(original));
    });

    it("should handle 32-byte key coordinate", () => {
      const hex = "0x" + "ab".repeat(32);
      const bytes = hexToBytes(hex);
      expect(bytes.length).toBe(32);
      expect(bytes.every(b => b === 0xab)).toBe(true);
    });
  });

  // ─── bytesToBase64Url ────────────────────────────────

  describe("bytesToBase64Url", () => {
    it("should encode without padding", () => {
      const result = bytesToBase64Url(new Uint8Array([0, 1, 2]));
      expect(result).not.toContain("=");
    });

    it("should use URL-safe characters", () => {
      // Encode bytes that would produce + and / in standard base64
      const bytes = new Uint8Array([0xff, 0xff, 0xff, 0xff]);
      const result = bytesToBase64Url(bytes);
      expect(result).not.toContain("+");
      expect(result).not.toContain("/");
    });

    it("should encode empty array", () => {
      expect(bytesToBase64Url(new Uint8Array([]))).toBe("");
    });
  });

  // ─── normalizeP256Signature ──────────────────────────

  describe("normalizeP256Signature", () => {
    it("should pass through raw 64-byte signatures", () => {
      const raw = new Uint8Array(64);
      crypto.getRandomValues(raw);
      const result = normalizeP256Signature(raw);
      expect(result.length).toBe(64);
      expect(Array.from(result)).toEqual(Array.from(raw));
    });

    it("should normalize DER-encoded signature (32+32 bytes)", () => {
      const r = new Uint8Array(32);
      const s = new Uint8Array(32);
      crypto.getRandomValues(r);
      crypto.getRandomValues(s);

      const der = new Uint8Array([
        0x30, 2 + 2 + 32 + 32,  // SEQUENCE
        0x02, 32, ...r,          // INTEGER r
        0x02, 32, ...s,          // INTEGER s
      ]);

      const result = normalizeP256Signature(der);
      expect(result.length).toBe(64);
      expect(Array.from(result.slice(0, 32))).toEqual(Array.from(r));
      expect(Array.from(result.slice(32, 64))).toEqual(Array.from(s));
    });

    it("should handle DER with leading zero padding (33-byte r)", () => {
      const r = new Uint8Array(32);
      const s = new Uint8Array(32);
      r[0] = 0x80; // High bit set → DER adds 0x00 prefix
      crypto.getRandomValues(s);

      const der = new Uint8Array([
        0x30, 2 + 2 + 33 + 32,     // SEQUENCE
        0x02, 33, 0x00, ...r,       // INTEGER r (with leading zero)
        0x02, 32, ...s,             // INTEGER s
      ]);

      const result = normalizeP256Signature(der);
      expect(result.length).toBe(64);
      expect(Array.from(result.slice(0, 32))).toEqual(Array.from(r));
      expect(Array.from(result.slice(32, 64))).toEqual(Array.from(s));
    });

    it("should handle short r component (left-pad with zeros)", () => {
      const r = new Uint8Array([0x01, 0x02, 0x03]); // 3 bytes
      const s = new Uint8Array(32);
      crypto.getRandomValues(s);

      const der = new Uint8Array([
        0x30, 2 + 2 + 3 + 32,
        0x02, 3, ...r,
        0x02, 32, ...s,
      ]);

      const result = normalizeP256Signature(der);
      expect(result.length).toBe(64);
      // r should be left-padded with 29 zeros
      expect(result[28]).toBe(0);
      expect(result[29]).toBe(0x01);
      expect(result[30]).toBe(0x02);
      expect(result[31]).toBe(0x03);
    });

    it("should throw on invalid format", () => {
      expect(() => normalizeP256Signature(new Uint8Array([0x99, 0x00]))).toThrow();
    });
  });

  // ─── padTo32Bytes ────────────────────────────────────

  describe("padTo32Bytes", () => {
    it("should copy exactly 32 bytes", () => {
      const src = new Uint8Array(32).fill(0xaa);
      const dest = new Uint8Array(64);
      padTo32Bytes(src, dest, 0);
      expect(dest[0]).toBe(0xaa);
      expect(dest[31]).toBe(0xaa);
    });

    it("should strip leading zero from 33-byte input", () => {
      const src = new Uint8Array([0x00, ...new Uint8Array(32).fill(0xbb)]);
      const dest = new Uint8Array(64);
      padTo32Bytes(src, dest, 32);
      expect(dest[32]).toBe(0xbb);
      expect(dest[63]).toBe(0xbb);
    });

    it("should left-pad short input", () => {
      const src = new Uint8Array([0x01, 0x02]);
      const dest = new Uint8Array(32);
      padTo32Bytes(src, dest, 0);
      expect(dest[29]).toBe(0);
      expect(dest[30]).toBe(0x01);
      expect(dest[31]).toBe(0x02);
    });

    it("should throw on unexpected length", () => {
      const src = new Uint8Array(34);
      const dest = new Uint8Array(64);
      expect(() => padTo32Bytes(src, dest, 0)).toThrow();
    });
  });
});
