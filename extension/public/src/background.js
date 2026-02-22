/**
 * Celari Wallet -- Background Service Worker
 *
 * Runs in the extension's background context.
 * Manages:
 * - PXE connection state
 * - Account registry
 * - Transaction queue
 * - dApp communication (via content script)
 */

// --- Network Presets -------------------------------------------------

const NETWORKS = {
  "local": {
    name: "Local Sandbox",
    url: "http://localhost:8080",
  },
  "devnet": {
    name: "Aztec Devnet",
    url: "https://devnet-6.aztec-labs.com/",
  },
  "testnet": {
    name: "Aztec Testnet",
    url: "https://rpc.testnet.aztec-labs.com/",
  },
};

// --- Offscreen Document (PXE WASM Engine) ----------------------------

let offscreenReady = false;

async function ensureOffscreen() {
  // Always verify the offscreen document actually exists (Chrome may close it when idle)
  try {
    const contexts = await chrome.runtime.getContexts({
      contextTypes: ["OFFSCREEN_DOCUMENT"],
    });
    if (contexts.length > 0) {
      offscreenReady = true;
      return;
    }
    // Document doesn't exist — reset flag and recreate
    offscreenReady = false;
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["WORKERS"],
      justification: "Aztec PXE WASM proving engine for zero-knowledge proofs",
    });
    offscreenReady = true;
    console.log("Offscreen document ready");
  } catch (e) {
    offscreenReady = false;
    console.error("Offscreen creation failed:", e.message);
  }
}

/**
 * Send a message to the offscreen PXE document and await response.
 */
async function sendToPXE(msg) {
  await ensureOffscreen();
  // Tag message with target so the background's own onMessage handler can skip it
  const taggedMsg = { ...msg, _target: "offscreen" };
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(taggedMsg, (response) => {
      if (chrome.runtime.lastError) {
        // Offscreen may have been closed — reset flag so it's recreated on next call
        offscreenReady = false;
        reject(new Error(chrome.runtime.lastError.message));
      } else if (response?.error) {
        reject(new Error(response.error));
      } else {
        resolve(response);
      }
    });
  });
}

// --- Pending dApp sign requests (awaiting user confirmation) ---------

const pendingSignRequests = new Map();

// --- State -----------------------------------------------------------

let state = {
  connected: false,
  nodeUrl: "https://rpc.testnet.aztec-labs.com/",
  network: "testnet",
  nodeInfo: null, // { nodeVersion, l1ChainId, protocolVersion, ... }
  accounts: [],
  activeAccountIndex: 0,
};

// --- Message Handler -------------------------------------------------

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // Skip messages tagged for offscreen document (prevents routing loop)
  if (message._target === "offscreen") return false;

  // Only accept messages from our own extension
  if (sender.id !== chrome.runtime.id) {
    sendResponse({ success: false, error: "Unauthorized sender" });
    return;
  }

  switch (message.type) {
    case "GET_STATE":
      sendResponse({ success: true, state });
      break;

    case "GET_NETWORKS": {
      chrome.storage.local.get("celari_custom_networks", (result) => {
        const customNetworks = result.celari_custom_networks || [];
        sendResponse({ success: true, networks: NETWORKS, customNetworks });
      });
      return true;
    }

    case "SET_NETWORK": {
      const preset = NETWORKS[message.network];
      if (preset) {
        state.nodeUrl = preset.url;
        state.network = message.network;
      } else if (message.nodeUrl) {
        state.nodeUrl = message.nodeUrl;
        state.network = message.networkId || "custom";
      }
      state.connected = false;
      state.nodeInfo = null;

      // Save config
      chrome.storage.local.set({
        celari_config: { nodeUrl: state.nodeUrl, network: state.network },
      });

      checkConnection().then(() => sendResponse({ success: true, state }));
      return true; // async response
    }

    case "SAVE_CUSTOM_NETWORK": {
      chrome.storage.local.get("celari_custom_networks", (result) => {
        const networks = result.celari_custom_networks || [];
        // Prevent duplicate URLs
        const exists = networks.find(n => n.url === message.networkData.url);
        if (exists) {
          sendResponse({ success: false, error: "Network URL already exists" });
          return;
        }
        networks.push(message.networkData);
        chrome.storage.local.set({ celari_custom_networks: networks });
        sendResponse({ success: true, networks });
      });
      return true;
    }

    case "DELETE_CUSTOM_NETWORK": {
      chrome.storage.local.get("celari_custom_networks", (result) => {
        const networks = (result.celari_custom_networks || []).filter(n => n.id !== message.networkId);
        chrome.storage.local.set({ celari_custom_networks: networks });
        // If the deleted network was active, switch to testnet
        if (state.network === message.networkId) {
          state.nodeUrl = NETWORKS.testnet.url;
          state.network = "testnet";
          state.connected = false;
          state.nodeInfo = null;
          chrome.storage.local.set({
            celari_config: { nodeUrl: state.nodeUrl, network: state.network },
          });
          checkConnection();
        }
        sendResponse({ success: true, networks, state });
      });
      return true;
    }

    case "CONNECT":
      checkConnection().then((connected) => {
        sendResponse({ success: true, connected, nodeInfo: state.nodeInfo });
      });
      return true;

    case "SAVE_ACCOUNT":
      state.accounts.push(message.account);
      chrome.storage.local.set({ celari_accounts: state.accounts });
      sendResponse({ success: true });
      break;

    case "GET_ACCOUNTS":
      sendResponse({ success: true, accounts: state.accounts });
      break;

    case "SET_ACTIVE_ACCOUNT":
      state.activeAccountIndex = message.index;
      sendResponse({ success: true });
      break;

    case "UPDATE_ACCOUNT": {
      // Update account fields (e.g. deployed address, deployment status)
      const idx = message.index ?? state.activeAccountIndex;
      if (state.accounts[idx]) {
        Object.assign(state.accounts[idx], message.updates);
        chrome.storage.local.set({ celari_accounts: state.accounts });
        sendResponse({ success: true, account: state.accounts[idx] });
      } else {
        sendResponse({ success: false, error: "Account not found" });
      }
      break;
    }

    case "RENAME_ACCOUNT": {
      const idx = message.index ?? state.activeAccountIndex;
      if (state.accounts[idx] && message.label) {
        state.accounts[idx].label = message.label.slice(0, 24);
        chrome.storage.local.set({ celari_accounts: state.accounts });
        sendResponse({ success: true, account: state.accounts[idx] });
      } else {
        sendResponse({ success: false, error: "Account not found or missing label" });
      }
      break;
    }

    case "DELETE_ACCOUNT": {
      const idx = message.index;
      if (idx >= 0 && idx < state.accounts.length && state.accounts.length > 1) {
        const deleted = state.accounts.splice(idx, 1)[0];
        if (state.activeAccountIndex >= state.accounts.length) {
          state.activeAccountIndex = state.accounts.length - 1;
        }
        chrome.storage.local.set({ celari_accounts: state.accounts });
        // Tell PXE to remove the account from its registry
        if (deleted.address) {
          sendToPXE({ type: "PXE_DELETE_ACCOUNT", data: { address: deleted.address } }).catch(() => {});
        }
        sendResponse({ success: true, accounts: state.accounts, activeAccountIndex: state.activeAccountIndex });
      } else {
        sendResponse({ success: false, error: "Cannot delete: invalid index or last account" });
      }
      break;
    }

    case "GET_BACKUP_DATA": {
      // Collect sensitive key data from session storage for encrypted backup
      chrome.storage.session.get(["celari_keys", "celari_secret", "celari_private_key"], (session) => {
        const backupData = {
          accounts: state.accounts,
          keys: session.celari_keys || null,
          secret: session.celari_secret || null,
          privateKey: session.celari_private_key || null,
          network: state.network,
          nodeUrl: state.nodeUrl,
          exportedAt: new Date().toISOString(),
          version: 1,
        };
        sendResponse({ success: true, data: backupData });
      });
      return true;
    }

    case "IMPORT_BACKUP": {
      // Import decrypted backup data: merge accounts and keys
      const imported = message.data;
      if (!imported?.accounts?.length) {
        sendResponse({ success: false, error: "No accounts in backup" });
        break;
      }
      for (const acc of imported.accounts) {
        const exists = state.accounts.some(a => a.address && a.address === acc.address);
        if (!exists) {
          state.accounts.push(acc);
        }
      }
      chrome.storage.local.set({ celari_accounts: state.accounts });
      // Restore session keys if present
      const sessionData = {};
      if (imported.keys) sessionData.celari_keys = imported.keys;
      if (imported.secret) sessionData.celari_secret = imported.secret;
      if (imported.privateKey) sessionData.celari_private_key = imported.privateKey;
      if (Object.keys(sessionData).length) chrome.storage.session.set(sessionData);
      // Register imported accounts with PXE
      for (const acc of imported.accounts) {
        if (acc.deployed && acc.secretKey && acc.salt) {
          sendToPXE({
            type: "PXE_REGISTER_ACCOUNT",
            data: {
              publicKeyX: acc.publicKeyX || "",
              publicKeyY: acc.publicKeyY || "",
              secretKey: acc.secretKey,
              salt: acc.salt,
              privateKeyPkcs8: acc.privateKeyPkcs8 || "",
            },
          }).catch(() => {});
        }
      }
      sendResponse({ success: true, accounts: state.accounts });
      break;
    }

    case "GET_DEPLOY_INFO": {
      // Check if a .celari-passkey-account.json was saved by CLI deploy
      chrome.storage.local.get("celari_deploy_info", (result) => {
        sendResponse({ success: true, deployInfo: result.celari_deploy_info || null });
      });
      return true;
    }

    case "SAVE_DEPLOY_INFO":
      chrome.storage.local.set({ celari_deploy_info: message.deployInfo });
      sendResponse({ success: true });
      break;

    case "VERIFY_ACCOUNT": {
      const addr = message.address;
      if (!addr) {
        sendResponse({ success: false, error: "No address" });
        break;
      }
      verifyAccount(addr).then((result) => {
        sendResponse({ success: true, ...result });
      }).catch((e) => {
        sendResponse({ success: false, error: e.message });
      });
      return true;
    }

    case "GET_BLOCK_NUMBER": {
      getBlockNumber().then((blockNumber) => {
        sendResponse({ success: true, blockNumber });
      }).catch((e) => {
        sendResponse({ success: false, error: e.message });
      });
      return true;
    }

    case "FAUCET_REQUEST": {
      sendToPXE({ type: "PXE_FAUCET", data: { address: message.address } })
        .then((result) => sendResponse({ success: true, ...result }))
        .catch((e) => sendResponse({ success: false, error: e.message }));
      return true;
    }

    // WalletConnect relay: offscreen → popup
    case "WC_SESSION_PROPOSAL": {
      // Relay WalletConnect session proposal to popup for user approval
      chrome.runtime.sendMessage({
        type: "WC_SESSION_PROPOSAL",
        proposal: message.proposal,
      }).catch(() => {});
      sendResponse({ success: true });
      break;
    }

    case "WC_SESSION_REQUEST": {
      // Relay WalletConnect session request to popup for user confirmation
      chrome.runtime.sendMessage({
        type: "WC_SESSION_REQUEST",
        request: message.request,
        topic: message.topic,
      }).catch(() => {});
      sendResponse({ success: true });
      break;
    }

    // dApp requests (forwarded from content script)
    case "DAPP_CONNECT":
      chrome.action.openPopup();
      sendResponse({ success: true, pending: true });
      break;

    case "DAPP_SIGN": {
      // Store the pending sign request and open a confirmation popup
      const signRequestId = `sign_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      pendingSignRequests.set(signRequestId, {
        payload: message.payload,
        origin: sender.origin || sender.tab?.url || "unknown",
        tabId: sender.tab?.id,
        sendResponse,
      });

      // Open confirmation popup
      chrome.windows.create({
        url: `popup.html?confirm=${signRequestId}`,
        type: "popup",
        width: 380,
        height: 560,
        focused: true,
      });

      return true; // async response — will be sent when user approves/rejects
    }

    case "GET_SIGN_REQUEST": {
      // Popup asks for the pending request details to display confirmation UI
      const reqId = message.requestId;
      const pending = pendingSignRequests.get(reqId);
      if (pending) {
        sendResponse({
          success: true,
          request: {
            id: reqId,
            origin: pending.origin,
            payload: pending.payload,
          },
        });
      } else {
        sendResponse({ success: false, error: "No pending request" });
      }
      break;
    }

    case "SIGN_APPROVE": {
      const pending = pendingSignRequests.get(message.requestId);
      if (pending) {
        pendingSignRequests.delete(message.requestId);
        // Forward the approved sign request back to the content script
        if (pending.tabId) {
          chrome.tabs.sendMessage(pending.tabId, {
            target: "content",
            type: "SIGN_APPROVED",
            payload: pending.payload,
          });
        }
        pending.sendResponse({ success: true, approved: true });
        // Also respond to the popup that sent SIGN_APPROVE
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: "Request not found or expired" });
      }
      break;
    }

    case "SIGN_REJECT": {
      const pending = pendingSignRequests.get(message.requestId);
      if (pending) {
        pendingSignRequests.delete(message.requestId);
        pending.sendResponse({ success: false, error: "User rejected the transaction" });
      } else {
        sendResponse({ success: false, error: "Request not found or expired" });
      }
      break;
    }

    // Wallet-SDK protocol: forward wallet method calls to offscreen PXE
    case "WALLET_METHOD_CALL": {
      sendToPXE({
        type: "PXE_WALLET_METHOD",
        rawMessage: message.rawMessage,
      })
        .then((result) => sendResponse(result))
        .catch((e) => sendResponse({ error: e.message }));
      return true; // async response
    }

    default:
      // Forward PXE_* messages to offscreen document
      if (message.type?.startsWith("PXE_")) {
        sendToPXE(message)
          .then((result) => sendResponse({ success: true, ...result }))
          .catch((e) => sendResponse({ success: false, error: e.message }));
        return true; // async response
      }
      sendResponse({ success: false, error: "Unknown message type" });
  }
});

// --- Connection Check ------------------------------------------------

async function checkConnection() {
  try {
    const url = state.nodeUrl.replace(/\/$/, "");

    // Try JSON-RPC first (devnet/testnet)
    const rpcResponse = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "node_getNodeInfo",
        params: [],
        id: 1,
      }),
      signal: AbortSignal.timeout(12000),
    });

    if (rpcResponse.ok) {
      const rpcData = await rpcResponse.json();
      if (rpcData.result) {
        state.connected = true;
        state.nodeInfo = {
          nodeVersion: rpcData.result.nodeVersion || "unknown",
          l1ChainId: rpcData.result.l1ChainId,
          protocolVersion: rpcData.result.protocolVersion || rpcData.result.rollupVersion,
        };
        return true;
      }
    }

    // Fallback: REST API (sandbox)
    const restResponse = await fetch(`${url}/api/node-info`, {
      method: "GET",
      signal: AbortSignal.timeout(5000),
    });
    if (restResponse.ok) {
      const info = await restResponse.json();
      state.connected = true;
      state.nodeInfo = {
        nodeVersion: info.nodeVersion || info.sandboxVersion || "unknown",
        l1ChainId: info.l1ChainId,
        protocolVersion: info.protocolVersion,
      };
      return true;
    }
  } catch (e) {
    state.connected = false;
    state.nodeInfo = null;
  }
  return false;
}

// --- Account Verification --------------------------------------------

async function verifyAccount(address) {
  const url = state.nodeUrl.replace(/\/$/, "");
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "node_getContract",
        params: [address],
        id: 1,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (res.ok) {
      const data = await res.json();
      if (data.result) {
        return { verified: true, contractData: data.result };
      }
    }
  } catch {}

  // Fallback: node responded but contract query unavailable — cannot confirm deployment
  try {
    const blockNum = await getBlockNumber();
    return { verified: false, blockNumber: blockNum, note: "Node responded but contract query unavailable — cannot confirm deployment" };
  } catch {}

  return { verified: false };
}

async function getBlockNumber() {
  const url = state.nodeUrl.replace(/\/$/, "");
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "node_getBlockNumber",
      params: [],
      id: 1,
    }),
    signal: AbortSignal.timeout(10000),
  });
  const data = await res.json();
  return data.result ?? null;
}

// --- Initialization --------------------------------------------------

// Restore state on every service worker wake-up (not just onInstalled)
async function restoreState() {
  const stored = await chrome.storage.local.get("celari_accounts");
  if (stored.celari_accounts) {
    state.accounts = stored.celari_accounts;
  }

  const config = await chrome.storage.local.get("celari_config");
  if (config.celari_config) {
    state.nodeUrl = config.celari_config.nodeUrl || state.nodeUrl;
    state.network = config.celari_config.network || state.network;
  }
}

async function initPXEAndAccounts() {
  await ensureOffscreen();
  if (state.connected) {
    sendToPXE({ type: "PXE_INIT", nodeUrl: state.nodeUrl })
      .then(async (res) => {
        console.log("PXE initialized:", res);
        for (const account of state.accounts) {
          if (account.deployed && account.secretKey && account.salt) {
            try {
              const regRes = await sendToPXE({
                type: "PXE_REGISTER_ACCOUNT",
                data: {
                  publicKeyX: account.publicKeyX,
                  publicKeyY: account.publicKeyY,
                  secretKey: account.secretKey,
                  salt: account.salt,
                  privateKeyPkcs8: account.privateKeyPkcs8 || "",
                },
              });
              console.log(`PXE account registered: ${account.address?.slice(0, 16)}...`, regRes);
            } catch (e) {
              console.warn(`PXE account registration failed for ${account.address?.slice(0, 16)}:`, e.message);
            }
          }
        }
      })
      .catch((e) => console.warn("PXE init deferred:", e.message));
  }
}

// Run on every SW startup (module top-level IIFE)
(async () => {
  try {
    await restoreState();
    await checkConnection();
    await initPXEAndAccounts();
  } catch (e) {
    console.error("Celari: initialization failed —", e.message || e);
  }
})();

chrome.runtime.onInstalled.addListener(() => {
  console.log("Celari Wallet installed");
});

// Replace setInterval with chrome.alarms for MV3 reliability
chrome.alarms.create("keepAlive", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === "keepAlive") {
    try {
      await checkConnection();
      await ensureOffscreen();
    } catch (e) {
      console.warn("Celari: keep-alive cycle failed —", e.message || e);
    }
  }
});
