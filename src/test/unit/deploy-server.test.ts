/**
 * Deploy Server HTTP Layer Tests
 *
 * Tests CORS headers, HTTP routing, and error responses
 * without starting a real server or connecting to Aztec.
 */

import { describe, it, expect } from "@jest/globals";
import { IncomingMessage, ServerResponse } from "http";
import { Socket } from "net";
import { Writable } from "stream";

// ─── HTTP Mock Helpers ────────────────────────────────────

function createMockRequest(method: string, url: string, headers: Record<string, string> = {}): IncomingMessage {
  const socket = new Socket();
  const req = new IncomingMessage(socket);
  req.method = method;
  req.url = url;
  req.headers = { ...headers };
  return req;
}

function createMockResponse(): ServerResponse & { _headers: Record<string, string>; _statusCode: number; _body: string } {
  const socket = new Socket();
  const res = new ServerResponse(createMockRequest("GET", "/")) as any;

  // Track what gets written
  res._headers = {};
  res._statusCode = 200;
  res._body = "";

  const origSetHeader = res.setHeader.bind(res);
  res.setHeader = (name: string, value: string) => {
    res._headers[name.toLowerCase()] = value;
    return origSetHeader(name, value);
  };

  const origWriteHead = res.writeHead.bind(res);
  res.writeHead = (statusCode: number, headers?: Record<string, string>) => {
    res._statusCode = statusCode;
    if (headers) {
      Object.entries(headers).forEach(([k, v]) => {
        res._headers[k.toLowerCase()] = v;
      });
    }
    return origWriteHead(statusCode, headers);
  };

  const origEnd = res.end.bind(res);
  res.end = (data?: string | Buffer) => {
    if (data) res._body = data.toString();
    return origEnd(data);
  };

  return res;
}

// ─── CORS Logic (same as deploy-server.ts) ───────────────

const CORS_ALLOWED_PATTERNS: RegExp[] = [
  /^chrome-extension:\/\/.+$/,
  /^http:\/\/localhost(:\d+)?$/,
];

function isOriginAllowed(origin: string): boolean {
  const envOrigins = process.env.CORS_ORIGIN;
  if (envOrigins && envOrigins.split(",").map(o => o.trim()).includes(origin)) return true;
  return CORS_ALLOWED_PATTERNS.some((pattern) => pattern.test(origin));
}

function cors(req: IncomingMessage, res: ServerResponse) {
  const origin = req.headers.origin as string | undefined;
  if (origin && isOriginAllowed(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function json(req: IncomingMessage, res: ServerResponse, status: number, data: unknown) {
  cors(req, res);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

// ─── Tests ───────────────────────────────────────────────

describe("Deploy Server: CORS Headers", () => {
  it("should set CORS headers for allowed chrome-extension origin", () => {
    const req = createMockRequest("GET", "/api/health", {
      origin: "chrome-extension://abcdef123456",
    });
    const res = createMockResponse();

    cors(req, res);

    expect(res._headers["access-control-allow-origin"]).toBe("chrome-extension://abcdef123456");
    expect(res._headers["access-control-allow-methods"]).toBe("GET, POST, OPTIONS");
    expect(res._headers["access-control-allow-headers"]).toBe("Content-Type");
  });

  it("should set CORS headers for localhost origin", () => {
    const req = createMockRequest("GET", "/api/health", {
      origin: "http://localhost:3000",
    });
    const res = createMockResponse();

    cors(req, res);

    expect(res._headers["access-control-allow-origin"]).toBe("http://localhost:3000");
  });

  it("should NOT set Access-Control-Allow-Origin for disallowed origin", () => {
    const req = createMockRequest("GET", "/api/health", {
      origin: "https://evil.com",
    });
    const res = createMockResponse();

    cors(req, res);

    expect(res._headers["access-control-allow-origin"]).toBeUndefined();
    // But should still set Methods and Headers
    expect(res._headers["access-control-allow-methods"]).toBe("GET, POST, OPTIONS");
  });

  it("should NOT set Access-Control-Allow-Origin when no origin header", () => {
    const req = createMockRequest("GET", "/api/health");
    const res = createMockResponse();

    cors(req, res);

    expect(res._headers["access-control-allow-origin"]).toBeUndefined();
  });
});

describe("Deploy Server: JSON Response Helper", () => {
  it("should set correct status code and content type", () => {
    const req = createMockRequest("GET", "/", { origin: "http://localhost:3000" });
    const res = createMockResponse();

    json(req, res, 200, { status: "ok" });

    expect(res._statusCode).toBe(200);
    expect(res._headers["content-type"]).toBe("application/json");
    expect(JSON.parse(res._body)).toEqual({ status: "ok" });
  });

  it("should handle error status codes", () => {
    const req = createMockRequest("POST", "/api/deploy");
    const res = createMockResponse();

    json(req, res, 503, { error: "Server starting" });

    expect(res._statusCode).toBe(503);
    expect(JSON.parse(res._body).error).toBe("Server starting");
  });

  it("should handle 404 responses", () => {
    const req = createMockRequest("GET", "/unknown");
    const res = createMockResponse();

    json(req, res, 404, { error: "Not found" });

    expect(res._statusCode).toBe(404);
  });
});

describe("Deploy Server: Route Matching", () => {
  // Simulate the router logic from deploy-server.ts
  function route(req: IncomingMessage, res: ServerResponse, walletReady: boolean) {
    const url = req.url || "/";

    if (req.method === "OPTIONS") {
      cors(req, res);
      res.writeHead(204);
      res.end();
      return "preflight";
    }

    if (url === "/api/health" && req.method === "GET") {
      json(req, res, 200, {
        status: walletReady ? "ready" : "connecting",
        nodeUrl: "https://rpc.testnet.aztec-labs.com/",
      });
      return "health";
    }

    if (url === "/api/deploy" && req.method === "POST") {
      if (!walletReady) {
        json(req, res, 503, { error: "Server starting, try again in a few seconds" });
        return "deploy-not-ready";
      }
      json(req, res, 200, { address: "0x123" });
      return "deploy";
    }

    json(req, res, 404, { error: "Not found" });
    return "not-found";
  }

  it("should handle OPTIONS preflight", () => {
    const req = createMockRequest("OPTIONS", "/api/deploy", {
      origin: "chrome-extension://abc",
    });
    const res = createMockResponse();

    const result = route(req, res, true);

    expect(result).toBe("preflight");
    expect(res._statusCode).toBe(204);
    expect(res._headers["access-control-allow-origin"]).toBe("chrome-extension://abc");
  });

  it("should handle GET /api/health when ready", () => {
    const req = createMockRequest("GET", "/api/health");
    const res = createMockResponse();

    route(req, res, true);

    expect(res._statusCode).toBe(200);
    expect(JSON.parse(res._body).status).toBe("ready");
  });

  it("should handle GET /api/health when connecting", () => {
    const req = createMockRequest("GET", "/api/health");
    const res = createMockResponse();

    route(req, res, false);

    expect(JSON.parse(res._body).status).toBe("connecting");
  });

  it("should reject POST /api/deploy when not ready", () => {
    const req = createMockRequest("POST", "/api/deploy");
    const res = createMockResponse();

    const result = route(req, res, false);

    expect(result).toBe("deploy-not-ready");
    expect(res._statusCode).toBe(503);
  });

  it("should accept POST /api/deploy when ready", () => {
    const req = createMockRequest("POST", "/api/deploy");
    const res = createMockResponse();

    const result = route(req, res, true);

    expect(result).toBe("deploy");
    expect(res._statusCode).toBe(200);
  });

  it("should return 404 for unknown routes", () => {
    const req = createMockRequest("GET", "/unknown");
    const res = createMockResponse();

    const result = route(req, res, true);

    expect(result).toBe("not-found");
    expect(res._statusCode).toBe(404);
  });

  it("should return 404 for wrong method on known route", () => {
    const req = createMockRequest("DELETE", "/api/deploy");
    const res = createMockResponse();

    const result = route(req, res, true);

    expect(result).toBe("not-found");
  });
});
