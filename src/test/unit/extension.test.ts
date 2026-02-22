/**
 * Chrome Extension Message Routing Tests
 *
 * Tests the extension's core logic with mocked Chrome APIs.
 * Covers: sender validation, message whitelist, state management.
 */

import { describe, it, expect, beforeEach } from "@jest/globals";

// ─── Chrome API Mock ─────────────────────────────────────

function createChromeMock() {
  const storage: Record<string, any> = {};
  const alarms: Record<string, any> = {};
  const alarmListeners: Function[] = [];

  return {
    runtime: {
      id: "test-extension-id",
      sendMessage: (_msg: any, cb?: Function) => cb?.({ success: true }),
      onMessage: {
        addListener: () => {},
      },
      onInstalled: {
        addListener: (cb: Function) => cb(),
      },
      getURL: (path: string) => `chrome-extension://test-id/${path}`,
    },
    storage: {
      local: {
        get: (key: string | string[], cb?: Function) => {
          if (typeof key === "string") {
            const result = { [key]: storage[key] };
            if (cb) cb(result);
            return Promise.resolve(result);
          }
          const result: Record<string, any> = {};
          (Array.isArray(key) ? key : [key]).forEach(k => { result[k] = storage[k]; });
          if (cb) cb(result);
          return Promise.resolve(result);
        },
        set: (data: Record<string, any>, cb?: Function) => {
          Object.assign(storage, data);
          if (cb) cb();
          return Promise.resolve();
        },
        remove: (keys: string | string[], cb?: Function) => {
          (Array.isArray(keys) ? keys : [keys]).forEach(k => delete storage[k]);
          if (cb) cb();
          return Promise.resolve();
        },
      },
    },
    alarms: {
      create: (name: string, opts: any) => { alarms[name] = opts; },
      onAlarm: {
        addListener: (cb: Function) => alarmListeners.push(cb),
      },
    },
    action: {
      openPopup: () => {},
    },
    _storage: storage,
    _alarms: alarms,
    _alarmListeners: alarmListeners,
  };
}

// ─── Background Logic (extracted for testing) ────────────

// These replicate the background.js logic so we can test it
const NETWORKS: Record<string, { name: string; url: string }> = {
  local: { name: "Local Sandbox", url: "http://localhost:8080" },
  devnet: { name: "Aztec Devnet", url: "https://devnet-6.aztec-labs.com/" },
  testnet: { name: "Aztec Testnet", url: "https://rpc.testnet.aztec-labs.com/" },
};

function createBackgroundState() {
  return {
    connected: false,
    nodeUrl: "https://rpc.testnet.aztec-labs.com/",
    network: "testnet",
    nodeInfo: null as any,
    accounts: [] as any[],
    activeAccountIndex: 0,
  };
}

function handleMessage(
  state: ReturnType<typeof createBackgroundState>,
  message: any,
  senderId: string,
  extensionId: string,
) {
  // Sender validation
  if (senderId !== extensionId) {
    return { success: false, error: "Unauthorized sender" };
  }

  switch (message.type) {
    case "GET_STATE":
      return { success: true, state };

    case "GET_NETWORKS":
      return { success: true, networks: NETWORKS };

    case "SET_NETWORK": {
      const preset = NETWORKS[message.network];
      if (preset) {
        state.nodeUrl = preset.url;
        state.network = message.network;
      } else if (message.nodeUrl) {
        state.nodeUrl = message.nodeUrl;
        state.network = "custom";
      }
      state.connected = false;
      state.nodeInfo = null;
      return { success: true, state };
    }

    case "SAVE_ACCOUNT":
      state.accounts.push(message.account);
      return { success: true };

    case "GET_ACCOUNTS":
      return { success: true, accounts: state.accounts };

    case "SET_ACTIVE_ACCOUNT":
      state.activeAccountIndex = message.index;
      return { success: true };

    case "UPDATE_ACCOUNT": {
      const idx = message.index ?? state.activeAccountIndex;
      if (state.accounts[idx]) {
        Object.assign(state.accounts[idx], message.updates);
        return { success: true, account: state.accounts[idx] };
      }
      return { success: false, error: "Account not found" };
    }

    default:
      return { success: false, error: "Unknown message type" };
  }
}

// ─── Content Script Logic (message whitelist) ────────────

const ALLOWED_DAPP_TYPES = [
  "DAPP_CONNECT",
  "DAPP_SIGN",
  "GET_ADDRESS",
  "GET_COMPLETE_ADDRESS",
  "GET_STATE",
  "CREATE_AUTHWIT",
];

function isAllowedDappMessage(type: string): boolean {
  return ALLOWED_DAPP_TYPES.includes(type);
}

// ─── Tests ───────────────────────────────────────────────

describe("Background: Sender Validation", () => {
  let state: ReturnType<typeof createBackgroundState>;

  beforeEach(() => {
    state = createBackgroundState();
  });

  it("should accept messages from own extension", () => {
    const result = handleMessage(state, { type: "GET_STATE" }, "ext-id", "ext-id");
    expect(result.success).toBe(true);
  });

  it("should reject messages from other extensions", () => {
    const result = handleMessage(state, { type: "GET_STATE" }, "other-ext", "ext-id");
    expect(result.success).toBe(false);
    expect(result.error).toBe("Unauthorized sender");
  });

  it("should reject messages with empty sender", () => {
    const result = handleMessage(state, { type: "GET_STATE" }, "", "ext-id");
    expect(result.success).toBe(false);
  });
});

describe("Background: State Management", () => {
  let state: ReturnType<typeof createBackgroundState>;
  const extId = "ext-id";

  beforeEach(() => {
    state = createBackgroundState();
  });

  it("should return initial state", () => {
    const result = handleMessage(state, { type: "GET_STATE" }, extId, extId);
    expect(result.success).toBe(true);
    expect(result.state?.network).toBe("testnet");
    expect(result.state?.connected).toBe(false);
    expect(result.state?.accounts).toEqual([]);
  });

  it("should return all network presets", () => {
    const result = handleMessage(state, { type: "GET_NETWORKS" }, extId, extId);
    expect(result.success).toBe(true);
    expect(Object.keys(result.networks!)).toEqual(["local", "devnet", "testnet"]);
  });

  it("should switch to known network", () => {
    const result = handleMessage(state, { type: "SET_NETWORK", network: "devnet" }, extId, extId);
    expect(result.success).toBe(true);
    expect(state.network).toBe("devnet");
    expect(state.nodeUrl).toBe("https://devnet-6.aztec-labs.com/");
    expect(state.connected).toBe(false); // reset on switch
  });

  it("should switch to custom network", () => {
    handleMessage(state, { type: "SET_NETWORK", nodeUrl: "http://custom:1234" }, extId, extId);
    expect(state.network).toBe("custom");
    expect(state.nodeUrl).toBe("http://custom:1234");
  });

  it("should reject unknown message types", () => {
    const result = handleMessage(state, { type: "HACK_WALLET" }, extId, extId);
    expect(result.success).toBe(false);
    expect(result.error).toBe("Unknown message type");
  });
});

describe("Background: Account Management", () => {
  let state: ReturnType<typeof createBackgroundState>;
  const extId = "ext-id";

  beforeEach(() => {
    state = createBackgroundState();
  });

  it("should save account", () => {
    const account = { address: "0x123", type: "passkey", label: "Test" };
    const result = handleMessage(state, { type: "SAVE_ACCOUNT", account }, extId, extId);
    expect(result.success).toBe(true);
    expect(state.accounts).toHaveLength(1);
    expect(state.accounts[0].address).toBe("0x123");
  });

  it("should get accounts", () => {
    state.accounts = [{ address: "0x1" }, { address: "0x2" }];
    const result = handleMessage(state, { type: "GET_ACCOUNTS" }, extId, extId);
    expect(result.accounts).toHaveLength(2);
  });

  it("should set active account index", () => {
    state.accounts = [{ address: "0x1" }, { address: "0x2" }];
    handleMessage(state, { type: "SET_ACTIVE_ACCOUNT", index: 1 }, extId, extId);
    expect(state.activeAccountIndex).toBe(1);
  });

  it("should update account fields", () => {
    state.accounts = [{ address: "0x1", deployed: false }];
    const result = handleMessage(state, {
      type: "UPDATE_ACCOUNT",
      index: 0,
      updates: { deployed: true, txHash: "0xabc" },
    }, extId, extId);

    expect(result.success).toBe(true);
    expect(state.accounts[0].deployed).toBe(true);
    expect(state.accounts[0].txHash).toBe("0xabc");
  });

  it("should fail to update non-existent account", () => {
    const result = handleMessage(state, {
      type: "UPDATE_ACCOUNT",
      index: 5,
      updates: { deployed: true },
    }, extId, extId);

    expect(result.success).toBe(false);
    expect(result.error).toBe("Account not found");
  });
});

describe("Content Script: Message Type Whitelist", () => {
  it("should allow legitimate dApp message types", () => {
    expect(isAllowedDappMessage("DAPP_CONNECT")).toBe(true);
    expect(isAllowedDappMessage("DAPP_SIGN")).toBe(true);
    expect(isAllowedDappMessage("GET_ADDRESS")).toBe(true);
    expect(isAllowedDappMessage("GET_COMPLETE_ADDRESS")).toBe(true);
    expect(isAllowedDappMessage("GET_STATE")).toBe(true);
    expect(isAllowedDappMessage("CREATE_AUTHWIT")).toBe(true);
  });

  it("should block internal message types from dApps", () => {
    expect(isAllowedDappMessage("SAVE_ACCOUNT")).toBe(false);
    expect(isAllowedDappMessage("UPDATE_ACCOUNT")).toBe(false);
    expect(isAllowedDappMessage("SET_NETWORK")).toBe(false);
    expect(isAllowedDappMessage("GET_DEPLOY_INFO")).toBe(false);
    expect(isAllowedDappMessage("SAVE_DEPLOY_INFO")).toBe(false);
    expect(isAllowedDappMessage("VERIFY_ACCOUNT")).toBe(false);
    expect(isAllowedDappMessage("GET_BLOCK_NUMBER")).toBe(false);
  });

  it("should block unknown/malicious message types", () => {
    expect(isAllowedDappMessage("HACK")).toBe(false);
    expect(isAllowedDappMessage("")).toBe(false);
    expect(isAllowedDappMessage("STEAL_KEYS")).toBe(false);
  });
});

describe("Chrome API Mock", () => {
  it("should provide working storage mock", async () => {
    const chrome = createChromeMock();

    await chrome.storage.local.set({ key: "value" });
    const result = await chrome.storage.local.get("key");
    expect(result.key).toBe("value");

    await chrome.storage.local.remove("key");
    const after = await chrome.storage.local.get("key");
    expect(after.key).toBeUndefined();
  });

  it("should provide working alarms mock", () => {
    const chrome = createChromeMock();
    chrome.alarms.create("test", { periodInMinutes: 1 });
    expect(chrome._alarms.test).toBeDefined();
    expect(chrome._alarms.test.periodInMinutes).toBe(1);
  });
});
