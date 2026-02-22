/**
 * Celari Wallet — Inpage Provider
 *
 * Injected into the page as `window.celari`.
 * dApps use this to interact with the wallet:
 *
 *   await window.celari.connect()
 *   await window.celari.sendTransaction(...)
 *   await window.celari.getAddress()
 */

(() => {
  let requestCounter = 0;
  const pendingRequests = new Map();

  // Listen for responses from content script
  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    if (event.data?.target !== "celari-inpage") return;

    const { requestId, response } = event.data;
    const pending = pendingRequests.get(requestId);
    if (pending) {
      pendingRequests.delete(requestId);
      if (response?.success) {
        pending.resolve(response);
      } else {
        pending.reject(new Error(response?.error || "Request failed"));
      }
    }
  });

  function sendRequest(type, payload) {
    return new Promise((resolve, reject) => {
      const requestId = `celari_${++requestCounter}_${Date.now()}`;
      pendingRequests.set(requestId, { resolve, reject });

      window.postMessage({
        target: "celari-content",
        type,
        payload,
        requestId,
      }, window.location.origin);

      // Timeout after 5 minutes
      setTimeout(() => {
        if (pendingRequests.has(requestId)) {
          pendingRequests.delete(requestId);
          reject(new Error("Request timed out"));
        }
      }, 300000);
    });
  }

  // ─── Public API ──────────────────────────────────────

  window.celari = {
    isCelari: true,
    version: "0.3.0",
    walletSdkId: "celari-wallet", // Aztec wallet-sdk discovery identifier

    /** Request wallet connection */
    async connect() {
      return sendRequest("DAPP_CONNECT", {
        origin: window.location.origin,
        title: document.title,
      });
    },

    /** Get connected account address */
    async getAddress() {
      return sendRequest("GET_ADDRESS", {});
    },

    /** Get account's complete address (for note encryption) */
    async getCompleteAddress() {
      return sendRequest("GET_COMPLETE_ADDRESS", {});
    },

    /** Request a private transaction signing */
    async sendTransaction(tx) {
      return sendRequest("DAPP_SIGN", { transaction: tx });
    },

    /** Request authorization witness creation */
    async createAuthWit(messageHash) {
      return sendRequest("CREATE_AUTHWIT", { messageHash });
    },

    /** Check if wallet is connected */
    async isConnected() {
      const result = await sendRequest("GET_STATE", {});
      return result.state?.connected || false;
    },

    /** Listen for account/network changes */
    on(event, callback) {
      window.addEventListener("message", (e) => {
        if (e.data?.target === "celari-inpage" && e.data?.event === event) {
          callback(e.data.payload);
        }
      });
    },
  };

  // Announce provider availability
  window.dispatchEvent(new Event("celari#initialized"));
  console.log("[Celari] Provider injected: window.celari");
})();
