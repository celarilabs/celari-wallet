/**
 * Celari Wallet — Content Script
 *
 * Injected into every web page.
 * Bridges communication between:
 *   dApp page ↔ content script ↔ background service worker
 *
 * Injects `window.celari` provider for dApp interaction.
 */

// Inject the inpage provider script
const script = document.createElement("script");
script.src = chrome.runtime.getURL("src/inpage.js");
script.type = "module";
(document.head || document.documentElement).appendChild(script);
script.onload = () => script.remove();

// ─── Wallet-SDK Protocol: Discovery + Method Relay ─────
// Implements the @aztec/wallet-sdk extension protocol for standard dApp integration.
// Messages are JSON strings sent via window.postMessage (per wallet-sdk convention).

const CELARI_WALLET_ID = "celari-wallet";
const CELARI_WALLET_INFO = {
  id: CELARI_WALLET_ID,
  name: "Celari Wallet",
  icon: chrome.runtime.getURL("icons/icon-48.png"),
  version: "0.3.0",
};

window.addEventListener("message", async (event) => {
  if (event.source !== window) return;
  if (typeof event.data !== "string") {
    // Not a wallet-sdk JSON message — check legacy protocol below
    handleLegacyMessage(event);
    return;
  }

  // wallet-sdk sends JSON-stringified messages
  let data;
  try {
    data = JSON.parse(event.data);
  } catch {
    return; // Not valid JSON, ignore
  }

  // --- Discovery Protocol ---
  if (data.type === "aztec-wallet-discovery" && data.requestId) {
    // Respond with wallet info so dApps can find Celari
    const response = JSON.stringify({
      type: "aztec-wallet-discovery-response",
      requestId: data.requestId,
      walletInfo: CELARI_WALLET_INFO,
    });
    window.postMessage(response, "*");
    return;
  }

  // --- Wallet Method Call Protocol ---
  if (data.messageId && data.walletId === CELARI_WALLET_ID && data.type) {
    try {
      // Forward the raw JSON string to background → offscreen for Aztec-typed deserialization
      const result = await chrome.runtime.sendMessage({
        type: "WALLET_METHOD_CALL",
        rawMessage: event.data,
      });

      if (result.error) {
        // Send error response to dApp
        const errorResponse = JSON.stringify({
          messageId: data.messageId,
          error: result.error,
          walletId: CELARI_WALLET_ID,
        });
        window.postMessage(errorResponse, "*");
      } else {
        // Send serialized result directly (already JSON from offscreen)
        window.postMessage(result.rawResponse, "*");
      }
    } catch (error) {
      const errorResponse = JSON.stringify({
        messageId: data.messageId,
        error: error.message,
        walletId: CELARI_WALLET_ID,
      });
      window.postMessage(errorResponse, "*");
    }
    return;
  }
});

// ─── Legacy Protocol: celari-content/celari-inpage ─────
// Keeps backward compatibility with existing window.celari API.

function handleLegacyMessage(event) {
  if (event.data?.target !== "celari-content") return;

  const ALLOWED_DAPP_TYPES = [
    "DAPP_CONNECT",
    "DAPP_SIGN",
    "GET_ADDRESS",
    "GET_COMPLETE_ADDRESS",
    "GET_STATE",
    "CREATE_AUTHWIT",
  ];
  if (!ALLOWED_DAPP_TYPES.includes(event.data.type)) return;

  const { type, payload, requestId } = event.data;

  chrome.runtime.sendMessage({ type, payload }).then(response => {
    window.postMessage({
      target: "celari-inpage",
      requestId,
      response,
    }, window.location.origin);
  }).catch(error => {
    window.postMessage({
      target: "celari-inpage",
      requestId,
      response: { success: false, error: error.message },
    }, window.location.origin);
  });
}

// Listen for messages from background (e.g., transaction results)
chrome.runtime.onMessage.addListener((message) => {
  if (message.target === "content") {
    window.postMessage({
      target: "celari-inpage",
      ...message,
    }, window.location.origin);
  }
});

console.log("[Celari] Content script loaded");
