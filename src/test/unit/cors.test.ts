/**
 * CORS origin validation tests for the deploy server.
 */

import { describe, it, expect, beforeEach, afterEach } from "@jest/globals";
import { isOriginAllowed, getAllowedOrigins, CORS_ALLOWED_PATTERNS } from "../../../scripts/lib/cors.js";

describe("CORS Origin Validation", () => {
  const originalEnv = process.env.CORS_ORIGIN;

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.CORS_ORIGIN = originalEnv;
    } else {
      delete process.env.CORS_ORIGIN;
    }
  });

  describe("CORS_ALLOWED_PATTERNS", () => {
    it("should have patterns for chrome-extension and localhost", () => {
      expect(CORS_ALLOWED_PATTERNS.length).toBe(2);
    });
  });

  describe("isOriginAllowed — chrome-extension origins", () => {
    it("should allow chrome-extension with any ID", () => {
      expect(isOriginAllowed("chrome-extension://abcdefghijklmnop")).toBe(true);
      expect(isOriginAllowed("chrome-extension://abc123def456ghi")).toBe(true);
    });

    it("should reject chrome-extension without ID", () => {
      expect(isOriginAllowed("chrome-extension://")).toBe(false);
    });

    it("should reject non-chrome extension schemes", () => {
      expect(isOriginAllowed("moz-extension://abcdef")).toBe(false);
      expect(isOriginAllowed("safari-extension://abcdef")).toBe(false);
    });
  });

  describe("isOriginAllowed — localhost origins", () => {
    it("should allow http://localhost without port", () => {
      expect(isOriginAllowed("http://localhost")).toBe(true);
    });

    it("should allow http://localhost with any port", () => {
      expect(isOriginAllowed("http://localhost:3000")).toBe(true);
      expect(isOriginAllowed("http://localhost:8080")).toBe(true);
      expect(isOriginAllowed("http://localhost:3456")).toBe(true);
    });

    it("should reject https://localhost", () => {
      expect(isOriginAllowed("https://localhost")).toBe(false);
      expect(isOriginAllowed("https://localhost:3000")).toBe(false);
    });

    it("should reject localhost subdomains", () => {
      expect(isOriginAllowed("http://sub.localhost:3000")).toBe(false);
    });
  });

  describe("isOriginAllowed — blocked origins", () => {
    it("should reject random domains", () => {
      expect(isOriginAllowed("https://evil.com")).toBe(false);
      expect(isOriginAllowed("http://attacker.io")).toBe(false);
    });

    it("should reject wildcard", () => {
      expect(isOriginAllowed("*")).toBe(false);
    });

    it("should reject empty string", () => {
      expect(isOriginAllowed("")).toBe(false);
    });

    it("should reject data: and file: schemes", () => {
      expect(isOriginAllowed("data:text/html")).toBe(false);
      expect(isOriginAllowed("file:///etc/passwd")).toBe(false);
    });
  });

  describe("getAllowedOrigins — env var", () => {
    it("should return empty array when CORS_ORIGIN not set", () => {
      delete process.env.CORS_ORIGIN;
      expect(getAllowedOrigins()).toEqual([]);
    });

    it("should parse single origin", () => {
      process.env.CORS_ORIGIN = "https://app.celari.io";
      expect(getAllowedOrigins()).toEqual(["https://app.celari.io"]);
    });

    it("should parse comma-separated origins", () => {
      process.env.CORS_ORIGIN = "https://app.celari.io, https://staging.celari.io";
      expect(getAllowedOrigins()).toEqual(["https://app.celari.io", "https://staging.celari.io"]);
    });
  });

  describe("isOriginAllowed — with CORS_ORIGIN env", () => {
    it("should allow env-whitelisted origins", () => {
      process.env.CORS_ORIGIN = "https://app.celari.io";
      expect(isOriginAllowed("https://app.celari.io")).toBe(true);
    });

    it("should still allow built-in patterns when env is set", () => {
      process.env.CORS_ORIGIN = "https://app.celari.io";
      expect(isOriginAllowed("chrome-extension://abc123")).toBe(true);
      expect(isOriginAllowed("http://localhost:3000")).toBe(true);
    });

    it("should reject origins not in env and not matching patterns", () => {
      process.env.CORS_ORIGIN = "https://app.celari.io";
      expect(isOriginAllowed("https://evil.com")).toBe(false);
    });
  });
});
