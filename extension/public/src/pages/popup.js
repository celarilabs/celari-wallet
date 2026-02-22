/**
 * Celari Wallet — Popup UI
 *
 * Complete wallet interface rendered in the extension popup.
 * Art Deco dark theme with burgundy/copper palette.
 *
 * Security: All dynamic content is sanitized via escapeHtml() before
 * being inserted into innerHTML. Toast messages use textContent.
 *
 * Screens:
 * 1. Onboarding → Create wallet with passkey
 * 2. Dashboard  → Balance, tokens, actions
 * 3. Send       → Private transfer form + passkey signing
 * 4. Receive    → Address display + QR
 * 5. Activity   → Transaction history
 * 6. Settings   → Network, account, passkey management
 */

// ─── Security: HTML Escaping ──────────────────────────

function escapeHtml(str) {
  if (typeof str !== "string") return String(str ?? "");
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// ─── Security: Error Sanitization ─────────────────────

function sanitizeError(e) {
  const msg = typeof e === "string" ? e : e?.message || "";
  const safe = {
    "NetworkError": "Network connection error",
    "AbortError": "Request timed out",
    "TypeError": "Connection failed",
  };
  if (e?.name && safe[e.name]) return safe[e.name];
  if (msg.includes("Failed to fetch")) return "Server unreachable";
  if (msg.includes("timed out")) return "Request timed out";
  if (msg.length > 100) return "An unexpected error occurred";
  return msg.replace(/[<>"'&]/g, "");
}

// ─── Security: Input Validation ───────────────────────

function isValidAddress(addr) {
  return typeof addr === "string" && /^0x[a-fA-F0-9]{40,}$/.test(addr);
}

function isValidAmount(amount) {
  const num = parseFloat(amount.replace(/,/g, ""));
  return !isNaN(num) && num > 0 && num < 1e15 && isFinite(num);
}

// ─── State Management ─────────────────────────────────

const store = {
  screen: "loading",
  connected: false,
  network: "local",
  nodeUrl: "http://localhost:8080",
  nodeInfo: null,
  accounts: [],
  activeAccountIndex: 0,
  tokens: [],
  customTokens: [],
  activities: [],
  sendForm: { to: "", amount: "", token: "zkUSD" },
  toast: null,
  loading: false,
  deploying: false,
  pendingSignRequestId: null,
  pendingSignRequest: null,
  tokenAddresses: {},
  customNetworks: [],
  deployServerUrl: "",
  // Phase 3: NFT
  nfts: [],
  customNftContracts: [],
  nftDetail: null,
  // Phase 4: WalletConnect
  wcSessions: [],
  wcProposal: null,
};

function setState(updates) {
  Object.assign(store, updates);
  // Clear sync polling when leaving dashboard
  if (updates.screen && updates.screen !== "dashboard") {
    clearSyncInterval();
  }
  render();
}

function getActiveAccount() {
  return store.accounts[store.activeAccountIndex] || null;
}

function isDemo() {
  return getActiveAccount()?.type === "demo";
}

const DEFAULT_TOKENS = [
  { name: "Celari USD", symbol: "zkUSD", balance: "0.00", value: "$0.00", icon: "C", color: "#C87941" },
  { name: "Wrapped ETH", symbol: "zkETH", balance: "0.000", value: "$0.00", icon: "E", color: "#8B2D3A" },
  { name: "Privacy Token", symbol: "ZKP", balance: "0", value: "$0.00", icon: "Z", color: "#9A7B5B" },
];

function getEmptyTokens() {
  return DEFAULT_TOKENS.map(t => ({ ...t }));
}

function getTokenList() {
  const defaults = DEFAULT_TOKENS.map(t => ({ ...t }));
  const custom = store.customTokens.map(t => ({
    name: t.name,
    symbol: t.symbol,
    balance: "0",
    value: "$0.00",
    icon: (t.symbol || "?")[0].toUpperCase(),
    color: "#9A7B5B",
    contractAddress: t.contractAddress,
    decimals: t.decimals,
    isCustom: true,
  }));
  return [...defaults, ...custom];
}

function getEmptyActivities() {
  return [];
}

// ─── Initialize ───────────────────────────────────────

async function init() {
  // Check if opened for dApp transaction confirmation
  const urlParams = new URLSearchParams(window.location.search);
  const confirmId = urlParams.get("confirm");
  if (confirmId) {
    store.pendingSignRequestId = confirmId;
    try {
      const res = await chrome.runtime.sendMessage({ type: "GET_SIGN_REQUEST", requestId: confirmId });
      if (res?.success) {
        store.pendingSignRequest = res.request;
        store.screen = "confirm-tx";
        render();
        return;
      }
    } catch (e) {}
    // If request not found, close the popup
    window.close();
    return;
  }

  try {
    const response = await chrome.runtime.sendMessage({ type: "GET_STATE" });
    if (response?.success) {
      store.connected = response.state.connected;
      store.network = response.state.network;
      store.nodeUrl = response.state.nodeUrl;
      store.nodeInfo = response.state.nodeInfo;
      store.accounts = response.state.accounts || [];
    }
  } catch (e) {
    console.warn("Background not ready, using defaults");
  }

  try {
    const stored = await chrome.storage.local.get("celari_accounts");
    if (stored.celari_accounts?.length) {
      store.accounts = stored.celari_accounts;
    }
  } catch (e) {}

  // Load custom tokens from storage
  try {
    const tokenData = await chrome.storage.local.get("celari_custom_tokens");
    if (tokenData.celari_custom_tokens?.length) {
      store.customTokens = tokenData.celari_custom_tokens;
    }
  } catch (e) {}

  // Load custom networks from storage
  try {
    const netData = await chrome.storage.local.get("celari_custom_networks");
    if (netData.celari_custom_networks?.length) {
      store.customNetworks = netData.celari_custom_networks;
    }
  } catch (e) {}

  // Load deploy server URL from storage
  try {
    const dsData = await chrome.storage.local.get("celari_deploy_server");
    if (dsData.celari_deploy_server) {
      store.deployServerUrl = dsData.celari_deploy_server;
    }
  } catch (e) {}

  // Load custom NFT contracts from storage
  try {
    const nftData = await chrome.storage.local.get("celari_custom_nft_contracts");
    if (nftData.celari_custom_nft_contracts?.length) {
      store.customNftContracts = nftData.celari_custom_nft_contracts;
    }
  } catch (e) {}

  store.screen = store.accounts.length > 0 ? "dashboard" : "onboarding";

  if (store.accounts.length > 0) {
    if (isDemo()) {
      store.tokens = getDemoTokens();
      store.activities = getDemoActivities();
    } else {
      store.tokens = getTokenList();
      store.activities = getEmptyActivities();
      fetchRealBalances();
    }
  }

  render();
}

// ─── Demo Data ────────────────────────────────────────

function getDemoTokens() {
  return [
    { name: "Celari USD", symbol: "zkUSD", balance: "1,250.00", value: "$1,250.00", icon: "C", color: "#C87941" },
    { name: "Wrapped ETH", symbol: "zkETH", balance: "0.842", value: "$2,231.70", icon: "E", color: "#8B2D3A" },
    { name: "Privacy Token", symbol: "ZKP", balance: "5,000", value: "$150.00", icon: "Z", color: "#9A7B5B" },
  ];
}

function getDemoActivities() {
  return [
    { type: "receive", label: "Salary received", from: "0x1a2b...9f3e", amount: "+1,250.00 zkUSD", time: "2 hours ago", private: true },
    { type: "send", label: "Card payment", to: "0x4c5d...8a1b", amount: "-45.00 zkUSD", time: "5 hours ago", private: true },
    { type: "send", label: "Transfer", to: "0x7e8f...2c3d", amount: "-200.00 zkUSD", time: "1 day ago", private: true },
    { type: "receive", label: "Bridge deposit", from: "L1 to L2", amount: "+0.842 zkETH", time: "2 days ago", private: false },
  ];
}

// ─── Balance Computation ──────────────────────────────

function computeTotalValue() {
  let total = 0;
  for (const t of store.tokens) {
    const val = parseFloat((t.value || "$0").replace(/[$,]/g, ""));
    if (!isNaN(val)) total += val;
  }
  return "$" + total.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

async function fetchRealBalances() {
  const account = getActiveAccount();
  if (!account || !account.deployed || !account.address) return;

  try {
    const res = await fetch(getDeployServer() + "/api/balances", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ address: account.address }),
      signal: AbortSignal.timeout(30000),
    });

    if (res.ok) {
      const data = await res.json();
      if (data.tokenAddresses) {
        store.tokenAddresses = data.tokenAddresses;
      }
      if (data.tokens?.length) {
        const serverTokens = data.tokens.map(t => ({
          name: t.name || t.symbol || "Unknown",
          symbol: t.symbol || "???",
          balance: t.balance || "0",
          value: "$" + (parseFloat(t.usdValue || "0")).toFixed(2),
          icon: (t.symbol || "?")[0].toUpperCase(),
          color: t.symbol === "CLR" ? "#C87941" : t.symbol === "zkETH" ? "#8B2D3A" : "#9A7B5B",
        }));
        // Append custom tokens that aren't in server response
        const serverSymbols = new Set(serverTokens.map(t => t.symbol));
        const customExtras = store.customTokens
          .filter(ct => !serverSymbols.has(ct.symbol))
          .map(ct => ({
            name: ct.name,
            symbol: ct.symbol,
            balance: "0",
            value: "$0.00",
            icon: (ct.symbol || "?")[0].toUpperCase(),
            color: "#9A7B5B",
            contractAddress: ct.contractAddress,
            decimals: ct.decimals,
            isCustom: true,
          }));
        store.tokens = [...serverTokens, ...customExtras];
        render();
        return;
      }
    }
  } catch (e) {
    console.log("[Celari] Balance fetch unavailable:", e.message || e);
  }
}

// ─── Faucet Request ──────────────────────────────────

async function handleFaucet() {
  const account = getActiveAccount();
  if (!account?.address || !account.deployed) {
    showToast("Deploy your account first", "error");
    return;
  }

  const btn = document.getElementById("btn-faucet");
  if (btn) {
    btn.style.opacity = "0.5";
    btn.style.pointerEvents = "none";
  }

  showToast("Requesting tokens... This may take a few minutes on first use.", "success");

  try {
    const data = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage(
        { type: "FAUCET_REQUEST", address: account.address },
        (response) => {
          if (chrome.runtime.lastError) {
            reject(new Error(chrome.runtime.lastError.message));
          } else if (!response?.success) {
            reject(new Error(response?.error || "Faucet request failed"));
          } else {
            resolve(response);
          }
        },
      );
    });

    showToast(`Received ${data.amount} ${data.symbol}!`, "success");

    // Auto-add faucet token to custom tokens if not already known
    if (data.tokenAddress && !store.tokenAddresses?.CLR) {
      store.tokenAddresses.CLR = data.tokenAddress;
    }

    fetchRealBalances();
  } catch (e) {
    showToast("Faucet: " + sanitizeError(e), "error");
  } finally {
    if (btn) {
      btn.style.opacity = "1";
      btn.style.pointerEvents = "auto";
    }
  }
}

// ─── SVG Icons ────────────────────────────────────────

const LOGO_SVG = `<svg width="22" height="24" viewBox="0 0 100 110" fill="none">
  <path d="M50 8 L92 34 L92 76 L50 102 L8 76 L8 34 Z" fill="#1C1616" stroke="#2A2222" stroke-width="1.5"/>
  <circle cx="50" cy="38" r="11" stroke="#C87941" stroke-width="2" fill="none"/>
  <circle cx="50" cy="38" r="4" fill="#C87941"/>
  <path d="M46 44 L44 66 L50 70 L56 66 L54 44" fill="#C87941" opacity="0.8"/>
</svg>`;

const LOGO_LARGE = `<svg width="70" height="77" viewBox="0 0 100 110" fill="none">
  <path d="M50 0 L100 30 L100 80 L50 110 L0 80 L0 30 Z" stroke="#C87941" stroke-width="0.8" fill="none" opacity="0.2"/>
  <path d="M50 8 L92 34 L92 76 L50 102 L8 76 L8 34 Z" fill="#151111" stroke="#2A2222" stroke-width="0.5"/>
  <rect x="25" y="65" width="50" height="6" fill="none" stroke="#C87941" stroke-width="0.8" opacity="0.4"/>
  <rect x="30" y="56" width="40" height="6" fill="none" stroke="#C87941" stroke-width="0.8" opacity="0.5"/>
  <rect x="35" y="47" width="30" height="6" fill="none" stroke="#C87941" stroke-width="0.8" opacity="0.6"/>
  <circle cx="50" cy="36" r="10" stroke="#C87941" stroke-width="1.2" fill="none"/>
  <circle cx="50" cy="36" r="3.5" fill="#C87941"/>
  <path d="M47 42 L45 62 L50 66 L55 62 L53 42" fill="#C87941" opacity="0.8"/>
  <rect x="48" y="3" width="4" height="4" fill="#8B2D3A" transform="rotate(45 50 5)" opacity="0.4"/>
</svg>`;

const icons = {
  send: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C87941" stroke-width="1.5"><path d="M12 5l0 14M5 12l7-7 7 7"/></svg>`,
  download: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C87941" stroke-width="1.5"><path d="M12 19l0-14M19 12l-7 7-7-7"/></svg>`,
  shield: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C87941" stroke-width="1.5"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>`,
  copy: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>`,
  back: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>`,
  settings: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>`,
  lock: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0110 0v4"/></svg>`,
  check: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C87941" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>`,
};

// ─── Render Engine ────────────────────────────────────
// Note: All dynamic user/external data is passed through escapeHtml()
// before insertion. Static HTML structure uses innerHTML for performance.

function render() {
  const root = document.getElementById("root");
  switch (store.screen) {
    case "loading":
      root.innerHTML = renderLoading();
      break;
    case "onboarding":
      root.innerHTML = renderOnboarding();
      bindOnboarding();
      break;
    case "dashboard":
      root.innerHTML = renderDashboard();
      bindDashboard();
      break;
    case "send":
      root.innerHTML = renderSend();
      bindSend();
      break;
    case "receive":
      root.innerHTML = renderReceive();
      bindReceive();
      break;
    case "activity":
      root.innerHTML = renderActivity();
      bindActivity();
      break;
    case "settings":
      root.innerHTML = renderSettings();
      bindSettings();
      break;
    case "add-token":
      root.innerHTML = renderAddToken();
      bindAddToken();
      break;
    case "confirm-tx":
      root.innerHTML = renderConfirmTx();
      bindConfirmTx();
      break;
    case "add-account":
      root.innerHTML = renderAddAccount();
      bindAddAccount();
      break;
    case "backup":
      root.innerHTML = renderBackup();
      bindBackup();
      break;
    case "restore":
      root.innerHTML = renderRestore();
      bindRestore();
      break;
    case "nft-detail":
      root.innerHTML = renderNftDetail();
      bindNftDetail();
      break;
    case "add-nft-contract":
      root.innerHTML = renderAddNftContract();
      bindAddNftContract();
      break;
    case "walletconnect":
      root.innerHTML = renderWalletConnect();
      bindWalletConnect();
      break;
    case "wc-approve":
      root.innerHTML = renderWcApprove();
      bindWcApprove();
      break;
    default:
      root.innerHTML = renderDashboard();
  }
}

// ─── Screen: Loading ──────────────────────────────────

function renderLoading() {
  return `
    <div class="onboarding">
      <div class="spinner" style="width:32px;height:32px;border-width:3px;margin-bottom:12px"></div>
      <p style="color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:9px;letter-spacing:3px">LOADING</p>
    </div>`;
}

// ─── Screen: Onboarding ───────────────────────────────

function renderOnboarding() {
  return `
    <div class="onboarding">
      <div class="onboarding-icon">${LOGO_LARGE}</div>
      <h2>Celari</h2>
      <div class="deco-separator">
        <div class="line"></div>
        <div class="diamond"></div>
        <div class="line"></div>
      </div>
      <div class="subtitle">celāre — to hide, to conceal</div>
      <p>Privacy-first wallet on Aztec. No seed phrases — just your fingerprint.</p>

      <div class="feature-list">
        <div class="feature-item">
          <div class="icon"><span>${icons.shield}</span></div>
          <span class="text"><strong>Private by Default</strong> — balance, amount, address hidden</span>
        </div>
        <div class="feature-item">
          <div class="icon"><span>${icons.lock}</span></div>
          <span class="text"><strong>Passkey Auth</strong> — Face ID / fingerprint</span>
        </div>
        <div class="feature-item">
          <div class="icon"><span>${icons.send}</span></div>
          <span class="text"><strong>Cross-chain</strong> — ETH, L2, Aztec bridge</span>
        </div>
      </div>

      <button id="btn-create-passkey" class="btn btn-passkey" style="margin-bottom:10px">
        Create Wallet
      </button>
      <button id="btn-demo" class="btn btn-secondary" style="font-size:9px;letter-spacing:2px">
        Demo Mode
      </button>
    </div>`;
}

function bindOnboarding() {
  document.getElementById("btn-create-passkey")?.addEventListener("click", handleCreatePasskey);
  document.getElementById("btn-demo")?.addEventListener("click", handleDemoMode);
}

async function handleCreatePasskey() {
  const btn = document.getElementById("btn-create-passkey");
  btn.disabled = true;
  btn.textContent = "Creating passkey...";

  try {
    if (!window.PublicKeyCredential) {
      throw new Error("This browser does not support Passkey");
    }

    const userId = crypto.getRandomValues(new Uint8Array(32));
    const createOptions = {
      publicKey: {
        rp: { name: "Celari Wallet", id: location.hostname },
        user: { id: userId, name: "Celari User", displayName: "Celari User" },
        challenge: crypto.getRandomValues(new Uint8Array(32)),
        pubKeyCredParams: [
          { type: "public-key", alg: -7 },
          { type: "public-key", alg: -257 },
        ],
        authenticatorSelection: {
          authenticatorAttachment: "platform",
          residentKey: "required",
          userVerification: "required",
        },
        timeout: 60000,
        attestation: "none",
      },
    };

    const credential = await navigator.credentials.create(createOptions);
    if (!credential) throw new Error("Passkey creation cancelled");

    const response = credential.response;
    const spki = new Uint8Array(response.getPublicKey());

    let offset = -1;
    for (let i = 0; i < spki.length - 64; i++) {
      if (spki[i] === 0x04 && i + 65 <= spki.length) { offset = i; break; }
    }
    if (offset === -1) throw new Error("Could not extract public key");

    const pubKeyX = Array.from(spki.slice(offset + 1, offset + 33)).map(b => b.toString(16).padStart(2, "0")).join("");
    const pubKeyY = Array.from(spki.slice(offset + 33, offset + 65)).map(b => b.toString(16).padStart(2, "0")).join("");

    // Address will be determined on deployment — show placeholder until then
    const address = "0x" + "0".repeat(40) + "_pending";

    const accountNum = store.accounts.length + 1;
    const account = {
      address,
      credentialId: credential.id,
      publicKeyX: "0x" + pubKeyX,
      publicKeyY: "0x" + pubKeyY,
      type: "passkey",
      label: accountNum === 1 ? "Main Wallet" : `Wallet ${accountNum}`,
      deployed: false,
      createdAt: new Date().toISOString(),
    };

    store.accounts.push(account);
    store.activeAccountIndex = store.accounts.length - 1;
    await chrome.storage.local.set({ celari_accounts: store.accounts });
    chrome.runtime.sendMessage({ type: "SAVE_ACCOUNT", account });

    // Store keys in session storage (cleared on browser close) for security
    await chrome.storage.session.set({
      celari_keys: {
        publicKeyX: account.publicKeyX,
        publicKeyY: account.publicKeyY,
        credentialId: account.credentialId,
      }
    });

    store.tokens = getEmptyTokens();
    store.activities = getEmptyActivities();
    setState({ screen: "dashboard" });
    showToast("Passkey wallet created!", "success");

  } catch (e) {
    console.error("Passkey error:", e);
    btn.disabled = false;
    btn.textContent = "Create Wallet";
    showToast(sanitizeError(e), "error");
  }
}

function handleDemoMode() {
  const address = "0x" + Array.from(crypto.getRandomValues(new Uint8Array(20))).map(b => b.toString(16).padStart(2, "0")).join("");
  const account = {
    address,
    credentialId: "demo",
    publicKeyX: "0x" + "ab".repeat(32),
    publicKeyY: "0x" + "cd".repeat(32),
    type: "demo",
    label: "Demo Wallet",
    createdAt: new Date().toISOString(),
  };
  store.accounts = [account];
  store.tokens = getDemoTokens();
  store.activities = getDemoActivities();
  chrome.storage.local.set({ celari_accounts: store.accounts });
  setState({ screen: "dashboard" });
  showToast("Running in demo mode", "success");
}

// ─── Deploy Banner ────────────────────────────────────

function getDeployServer() {
  return store.deployServerUrl.replace(/\/$/, "");
}

function validateDeployResponse(info) {
  if (!info || typeof info !== "object") return false;
  if (typeof info.address !== "string" || !isValidAddress(info.address)) return false;
  return true;
}

function applyDeployInfo(info) {
  if (!validateDeployResponse(info)) {
    showToast("Invalid deploy response", "error");
    return;
  }
  const account = getActiveAccount();
  if (!account) return;
  // Do NOT store secretKey in local storage — only non-sensitive fields
  const updates = {
    deployed: true,
    address: info.address,
    publicKeyX: info.publicKeyX || account.publicKeyX,
    publicKeyY: info.publicKeyY || account.publicKeyY,
    salt: info.salt,
    network: info.network,
    txHash: info.txHash,
    blockNumber: info.blockNumber,
    deployedAt: info.deployedAt,
  };
  // Store sensitive keys ONLY in session storage (cleared when browser closes)
  if (info.secretKey) {
    chrome.storage.session.set({ celari_secret: info.secretKey });
  }
  if (info.privateKeyPkcs8) {
    chrome.storage.session.set({ celari_private_key: info.privateKeyPkcs8 });
  }
  // Register account with client-side PXE (offscreen document)
  if (info.secretKey && info.salt && info.publicKeyX && info.publicKeyY && info.privateKeyPkcs8) {
    chrome.runtime.sendMessage({
      type: "PXE_REGISTER_ACCOUNT",
      data: {
        publicKeyX: info.publicKeyX,
        publicKeyY: info.publicKeyY,
        secretKey: info.secretKey,
        salt: info.salt,
        privateKeyPkcs8: info.privateKeyPkcs8,
      },
    }, (res) => {
      if (res?.success) {
        console.log("Account registered in PXE:", res.address);
      } else {
        console.warn("PXE account registration deferred:", res?.error);
      }
    });
  }
  Object.assign(account, updates);
  chrome.storage.local.set({ celari_accounts: store.accounts });
  chrome.runtime.sendMessage({
    type: "UPDATE_ACCOUNT",
    index: store.activeAccountIndex,
    updates,
  });
  store.deploying = false;
  setState({});
  showToast("Account deployed successfully!", "success");
}

function renderDeployBanner() {
  const networkName = store.network === "devnet" ? "Devnet" : "Testnet";
  return `
    <div style="margin:0 16px 12px;padding:14px;background:var(--bg-card);border:1px solid var(--border);position:relative">
      <div style="position:absolute;top:6px;left:6px;width:12px;height:12px;border-top:1px solid var(--border-warm);border-left:1px solid var(--border-warm);opacity:0.5"></div>
      <div style="position:absolute;bottom:6px;right:6px;width:12px;height:12px;border-bottom:1px solid var(--border-warm);border-right:1px solid var(--border-warm);opacity:0.5"></div>
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
        ${icons.shield}
        <span style="font-family:IBM Plex Mono,monospace;font-size:8px;font-weight:500;letter-spacing:3px;color:var(--copper);text-transform:uppercase">Account Deploy</span>
      </div>
      <p style="font-size:11px;color:var(--text-dim);margin:0 0 10px;line-height:1.5">
        Deploy your account on ${escapeHtml(networkName)}. This may take 30-120 seconds.
      </p>
      <div id="deploy-status" style="display:none;margin-bottom:10px;padding:8px 10px;font-family:IBM Plex Mono,monospace;font-size:9px;line-height:1.6;border:1px solid var(--border)"></div>
      <div style="display:flex;gap:8px">
        <button id="btn-deploy-account" style="flex:1;padding:10px;border:1px solid rgba(200,121,65,0.3);background:rgba(200,121,65,0.08);color:var(--copper);font-family:IBM Plex Mono,monospace;font-size:9px;cursor:pointer;font-weight:500;letter-spacing:2px;text-transform:uppercase">
          Deploy
        </button>
        <button id="btn-import-deployed" style="padding:10px 14px;border:1px solid var(--border);background:var(--bg-elevated);color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:9px;cursor:pointer;letter-spacing:1px;text-transform:uppercase">
          JSON
        </button>
      </div>
      <input type="file" id="file-import-deploy" accept=".json" style="display:none">
    </div>`;
}

// ─── Sync Bar ────────────────────────────────────────

function renderSyncBar() {
  return `
    <div id="sync-bar" style="margin:0 16px 8px;padding:8px 10px;background:var(--bg-card);border:1px solid var(--border);display:flex;align-items:center;gap:8px;font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);letter-spacing:1px">
      <div id="sync-dot" style="width:5px;height:5px;border-radius:50%;background:var(--green)"></div>
      <span id="sync-text">Checking sync...</span>
    </div>`;
}

function startSyncPolling() {
  const update = () => {
    chrome.runtime.sendMessage({ type: "PXE_SYNC_STATUS" }, (res) => {
      const dot = document.getElementById("sync-dot");
      const text = document.getElementById("sync-text");
      if (!dot || !text) return;
      if (res?.success && res.synced) {
        dot.style.background = "var(--green)";
        text.textContent = `Synced · Block ${res.nodeBlock} · ${res.accountCount || 0} account(s)`;
      } else if (res?.success) {
        dot.style.background = "var(--copper)";
        text.textContent = "PXE not ready";
      } else {
        dot.style.background = "var(--text-faint)";
        text.textContent = "Sync unavailable";
      }
    });
  };
  update();
  return setInterval(update, 10000);
}

// ─── Account Selector ────────────────────────────────

function renderAccountSelector() {
  return `
    <div style="margin:0 16px 8px;display:flex;gap:6px;overflow-x:auto">
      ${store.accounts.map((acc, i) => {
        const isActive = i === store.activeAccountIndex;
        const short = acc.address ? acc.address.slice(0, 6) + "..." + acc.address.slice(-4) : "New";
        const label = escapeHtml(acc.label || `Account ${i + 1}`);
        return `<button class="account-chip ${isActive ? 'active' : ''}" data-index="${i}" title="Double-click to rename" style="
          padding:6px 10px;border:1px solid ${isActive ? 'rgba(200,121,65,0.4)' : 'var(--border)'};
          background:${isActive ? 'rgba(200,121,65,0.08)' : 'var(--bg-elevated)'};
          color:${isActive ? 'var(--copper)' : 'var(--text-dim)'};
          font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;white-space:nowrap;letter-spacing:0.5px
        "><span class="chip-label">${label}</span> <span style="opacity:0.6">${escapeHtml(short)}</span></button>`;
      }).join("")}
      <button id="btn-add-account" style="padding:6px 10px;border:1px dashed var(--border);background:none;color:var(--text-faint);font-family:IBM Plex Mono,monospace;font-size:10px;cursor:pointer">+</button>
    </div>`;
}

// ─── Screen: Dashboard ────────────────────────────────

function renderDashboard() {
  const account = getActiveAccount();
  const shortAddr = account ? `${account.address.slice(0, 8)}...${account.address.slice(-6)}` : "";
  const totalValue = computeTotalValue();
  const isPasskey = account?.type === "passkey";
  const isDeployed = account?.deployed === true;
  const needsDeploy = isPasskey && !isDeployed && (store.network === "devnet" || store.network === "testnet");

  return `
    ${renderHeader()}

    <div class="balance-card">
      <div class="privacy-badge">${icons.lock} Shielded</div>
      <div class="balance-label">Total Balance</div>
      <div class="balance-amount">${escapeHtml(totalValue)}</div>
      <div class="balance-address">
        ${isDeployed || !isPasskey ? `<code>${escapeHtml(shortAddr)}</code>
        <button class="copy-btn" id="btn-copy-addr" title="Copy address">${icons.copy}</button>` : `<code style="color:var(--text-faint)">Deploy to get address</code>`}
        <span style="margin-left:4px;font-family:IBM Plex Mono,monospace;font-size:8px;letter-spacing:2px;color:${isDeployed ? 'var(--green)' : isPasskey ? 'var(--copper)' : 'var(--text-dim)'}">${isDeployed ? 'DEPLOYED' : isPasskey ? 'PENDING' : 'DEMO'}</span>
      </div>
    </div>

    ${needsDeploy ? renderDeployBanner() : ''}
    ${!needsDeploy && isDeployed ? renderSyncBar() : ''}

    ${renderAccountSelector()}

    <div class="actions">
      <button class="action-btn" id="btn-send">
        <div class="icon">${icons.send}</div>
        Send
      </button>
      <button class="action-btn" id="btn-receive">
        <div class="icon">${icons.download}</div>
        Receive
      </button>
      ${store.network === "testnet" || store.network === "devnet" ? `
      <button class="action-btn" id="btn-faucet">
        <div class="icon">${icons.download}</div>
        Faucet
      </button>` : `
      <button class="action-btn" id="btn-bridge">
        <div class="icon">${icons.send}</div>
        Bridge
      </button>`}
      <button class="action-btn" id="btn-card">
        <div class="icon">${icons.shield}</div>
        Shield
      </button>
    </div>

    <div class="tabs">
      <div class="tab active" id="tab-tokens">Tokens</div>
      <div class="tab" id="tab-nfts">NFTs</div>
      <div class="tab" id="tab-activity">Activity</div>
      <button id="btn-add-token" title="Add custom token" style="background:none;border:none;color:var(--text-dim);cursor:pointer;padding:4px 8px;font-size:16px;font-family:IBM Plex Mono,monospace;transition:color 0.2s;margin-left:auto">+</button>
    </div>

    <div class="token-list" id="content-area">
      ${renderTokenList()}
    </div>`;
}

function renderTokenList() {
  if (store.tokens.length === 0) {
    return `<div style="text-align:center;padding:32px 16px;color:var(--text-dim)">
      <div style="font-size:24px;margin-bottom:8px;opacity:0.3">◇</div>
      <p style="font-size:10px;letter-spacing:2px;text-transform:uppercase;margin:0">No tokens found</p>
    </div>`;
  }
  return store.tokens.map((t, idx) => {
    const hasPrivate = t.privateBalance && t.privateBalance !== "0" && t.privateBalance !== "—";
    const hasPublic = t.publicBalance && t.publicBalance !== "—";
    return `
    <div class="token-item">
      <div class="token-icon" style="border-color:${escapeHtml(t.color)}"><span style="transform:rotate(-45deg);color:${escapeHtml(t.color)};font-family:Poiret One,cursive;font-size:14px">${escapeHtml(t.icon)}</span></div>
      <div class="token-info">
        <div class="token-name">${escapeHtml(t.name)}</div>
        <div class="token-symbol">${escapeHtml(t.symbol)}${t.isCustom ? ' <span style="color:var(--text-faint);font-size:7px">CUSTOM</span>' : ''}</div>
      </div>
      <div class="token-balance" style="display:flex;align-items:center;gap:6px">
        <div>
          <div class="amount">${escapeHtml(t.balance)}</div>
          ${hasPublic || hasPrivate ? `<div style="font-size:8px;font-family:IBM Plex Mono,monospace;color:var(--text-faint);margin-top:2px">
            ${hasPublic ? `<span title="Public balance">P:${escapeHtml(t.publicBalance)}</span>` : ''}
            ${hasPrivate ? `<span style="color:var(--green);margin-left:4px" title="Private balance">S:${escapeHtml(t.privateBalance)}</span>` : ''}
          </div>` : `<div class="value">${escapeHtml(t.value)}</div>`}
        </div>
        ${t.isCustom ? `<button class="btn-remove-token" data-symbol="${escapeHtml(t.symbol)}" title="Remove token" style="background:none;border:none;color:var(--text-faint);cursor:pointer;font-size:14px;padding:2px 4px;transition:color 0.2s">&times;</button>` : ''}
      </div>
    </div>`;
  }).join("");
}

function renderActivityList() {
  if (store.activities.length === 0) {
    return `<div style="text-align:center;padding:32px 16px;color:var(--text-dim)">
      <div style="font-size:24px;margin-bottom:8px;opacity:0.3">◇</div>
      <p style="font-size:10px;letter-spacing:2px;text-transform:uppercase;margin:0">No transactions yet</p>
    </div>`;
  }
  return store.activities.map(a => `
    <div class="activity-item">
      <div class="activity-icon ${escapeHtml(a.type)}"><span style="transform:rotate(-45deg)">${a.type === "send" ? "↗" : "↙"}</span></div>
      <div class="activity-info">
        <div class="activity-type">${escapeHtml(a.label)} ${a.private ? '<span style="color:var(--green);font-size:9px">●</span>' : ''}</div>
        <div class="activity-detail">${escapeHtml(a.time)}</div>
      </div>
      <div class="activity-amount ${a.type === "send" ? "negative" : "positive"}">${escapeHtml(a.amount)}</div>
    </div>
  `).join("");
}

let syncInterval = null;

function clearSyncInterval() {
  if (syncInterval) {
    clearInterval(syncInterval);
    syncInterval = null;
  }
}

function bindDashboard() {
  // Start sync polling if deployed
  const account = getActiveAccount();
  clearSyncInterval();
  if (account?.deployed) {
    syncInterval = startSyncPolling();
  }

  document.getElementById("btn-send")?.addEventListener("click", () => setState({ screen: "send" }));
  document.getElementById("btn-receive")?.addEventListener("click", () => setState({ screen: "receive" }));
  document.getElementById("btn-add-token")?.addEventListener("click", () => setState({ screen: "add-token" }));
  document.getElementById("btn-bridge")?.addEventListener("click", () => showToast("Bridge — coming soon", "success"));
  document.getElementById("btn-faucet")?.addEventListener("click", handleFaucet);
  document.getElementById("btn-card")?.addEventListener("click", () => {
    store.sendForm.transferType = "shield";
    setState({ screen: "send" });
  });
  document.getElementById("btn-copy-addr")?.addEventListener("click", () => {
    const account = getActiveAccount();
    if (account) {
      navigator.clipboard.writeText(account.address);
      showToast("Address copied", "success");
    }
  });
  document.getElementById("btn-settings")?.addEventListener("click", () => setState({ screen: "settings" }));

  // Deploy
  document.getElementById("btn-deploy-account")?.addEventListener("click", async () => {
    if (store.deploying) return;
    store.deploying = true;

    const btn = document.getElementById("btn-deploy-account");
    const statusEl = document.getElementById("deploy-status");
    if (!btn || !statusEl) return;

    btn.disabled = true;
    btn.style.opacity = "0.5";
    btn.textContent = "DEPLOYING...";
    statusEl.style.display = "block";
    statusEl.style.color = "var(--copper)";
    statusEl.textContent = "Initializing PXE...";

    try {
      // --- Try client-side deploy first (fully decentralized) ---
      let deployed = false;
      try {
        // 1. Ensure PXE is ready
        statusEl.textContent = "Starting PXE engine...";
        await new Promise((resolve, reject) => {
          chrome.runtime.sendMessage({ type: "PXE_STATUS" }, (res) => {
            if (res?.success && res.ready) resolve();
            else reject(new Error("PXE not ready"));
          });
        });

        // 2. Generate P256 key pair in browser
        statusEl.textContent = "Generating keys (WebCrypto)...";
        const keys = await new Promise((resolve, reject) => {
          chrome.runtime.sendMessage({ type: "PXE_GENERATE_KEYS" }, (res) => {
            if (res?.success && res.pubKeyX) resolve(res);
            else reject(new Error(res?.error || "Key generation failed"));
          });
        });

        // 3. Deploy account on-chain via client-side PXE
        statusEl.textContent = "Deploying account on-chain (60-180s)...";
        const deployResult = await new Promise((resolve, reject) => {
          chrome.runtime.sendMessage({
            type: "PXE_DEPLOY_ACCOUNT",
            data: {
              publicKeyX: keys.pubKeyX,
              publicKeyY: keys.pubKeyY,
              privateKeyPkcs8: keys.privateKeyPkcs8,
            },
          }, (res) => {
            if (res?.success && res.address) resolve(res);
            else reject(new Error(res?.error || "Deploy failed"));
          });
        });

        // 4. Apply deploy info
        applyDeployInfo({
          address: deployResult.address,
          publicKeyX: keys.pubKeyX,
          publicKeyY: keys.pubKeyY,
          secretKey: deployResult.secretKey,
          salt: deployResult.salt,
          privateKeyPkcs8: keys.privateKeyPkcs8,
          network: store.network,
          nodeUrl: store.nodeUrl,
          txHash: deployResult.txHash,
          blockNumber: deployResult.blockNumber,
          deployedAt: new Date().toISOString(),
        });
        deployed = true;
      } catch (pxeErr) {
        console.warn("Client-side deploy failed, falling back to server:", pxeErr.message);
        statusEl.textContent = "Client deploy failed, trying server...";
      }

      // --- Fallback: server-side deploy ---
      if (!deployed) {
        statusEl.textContent = "Connecting to deploy server...";
        const health = await fetch(getDeployServer() + "/api/health", {
          signal: AbortSignal.timeout(10000),
        }).catch(() => null);

        if (!health || !health.ok) {
          throw new Error("Deploy server unreachable and client-side deploy failed");
        }

        const status = await health.json();
        if (status.status !== "ready") {
          statusEl.textContent = "Server preparing...";
          await new Promise(r => setTimeout(r, 3000));
        }

        statusEl.textContent = "Deploying via server... (30-120s)";
        const res = await fetch(getDeployServer() + "/api/deploy", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
          signal: AbortSignal.timeout(300000),
        });

        if (!res.ok) {
          const err = await res.json().catch(() => ({ error: "Unknown error" }));
          throw new Error(err.error || "HTTP " + res.status);
        }

        const info = await res.json();
        applyDeployInfo(info);
      }
    } catch (e) {
      statusEl.style.color = "var(--red)";
      statusEl.textContent = sanitizeError(e);
      btn.disabled = false;
      btn.style.opacity = "1";
      btn.textContent = "RETRY";
      store.deploying = false;
    }
  });

  // Account selector chips — click to switch, dblclick to rename
  document.querySelectorAll(".account-chip").forEach(chip => {
    chip.addEventListener("click", () => {
      const idx = parseInt(chip.dataset.index);
      if (idx !== store.activeAccountIndex) {
        store.activeAccountIndex = idx;
        chrome.runtime.sendMessage({ type: "SET_ACTIVE_ACCOUNT", index: idx });
        const acct = store.accounts[idx];
        if (acct?.address) {
          chrome.runtime.sendMessage({ type: "PXE_SET_ACTIVE_ACCOUNT", data: { address: acct.address } });
        }
        fetchRealBalances();
        setState({});
      }
    });

    chip.addEventListener("dblclick", (e) => {
      e.preventDefault();
      const idx = parseInt(chip.dataset.index);
      const labelSpan = chip.querySelector(".chip-label");
      if (!labelSpan) return;

      const currentLabel = store.accounts[idx]?.label || `Account ${idx + 1}`;
      const input = document.createElement("input");
      input.type = "text";
      input.value = currentLabel;
      input.maxLength = 24;
      input.className = "account-chip-edit";
      input.style.cssText = "width:60px;padding:2px 4px;border:1px solid var(--copper);background:var(--bg);color:var(--copper);font-family:IBM Plex Mono,monospace;font-size:8px;outline:none";

      const finishRename = () => {
        const newLabel = input.value.trim();
        if (newLabel && newLabel !== currentLabel) {
          store.accounts[idx].label = newLabel;
          chrome.runtime.sendMessage({ type: "RENAME_ACCOUNT", index: idx, label: newLabel });
        }
        render();
      };

      input.addEventListener("blur", finishRename);
      input.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter") input.blur();
        if (ev.key === "Escape") { input.value = currentLabel; input.blur(); }
      });

      labelSpan.replaceWith(input);
      input.focus();
      input.select();
    });
  });

  // Add account button
  document.getElementById("btn-add-account")?.addEventListener("click", () => {
    setState({ screen: "add-account" });
  });

  // JSON import
  document.getElementById("btn-import-deployed")?.addEventListener("click", () => {
    document.getElementById("file-import-deploy")?.click();
  });
  document.getElementById("file-import-deploy")?.addEventListener("change", (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const info = JSON.parse(reader.result);
        if (!validateDeployResponse(info)) {
          showToast("Invalid JSON: no valid address found", "error");
          return;
        }
        applyDeployInfo(info);
      } catch {
        showToast("Could not parse JSON", "error");
      }
    };
    reader.readAsText(file);
    e.target.value = "";
  });

  // Tabs
  document.getElementById("tab-tokens")?.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    document.getElementById("tab-tokens").classList.add("active");
    document.getElementById("content-area").innerHTML = renderTokenList();
    bindTokenRemoveButtons();
  });

  document.getElementById("tab-nfts")?.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    document.getElementById("tab-nfts").classList.add("active");
    document.getElementById("content-area").innerHTML = renderNftList();
    bindNftItems();
    fetchNftBalances();
  });

  document.getElementById("tab-activity")?.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    document.getElementById("tab-activity").classList.add("active");
    document.getElementById("content-area").innerHTML = renderActivityList();
  });

  // WalletConnect header icon
  document.getElementById("btn-walletconnect")?.addEventListener("click", () => setState({ screen: "walletconnect" }));

  bindTokenRemoveButtons();
}

function bindTokenRemoveButtons() {
  document.querySelectorAll(".btn-remove-token").forEach(btn => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const symbol = btn.dataset.symbol;
      if (!confirm(`Remove ${symbol} from your token list?`)) return;
      store.customTokens = store.customTokens.filter(t => t.symbol !== symbol);
      chrome.storage.local.set({ celari_custom_tokens: store.customTokens });
      store.tokens = store.tokens.filter(t => !(t.isCustom && t.symbol === symbol));
      render();
      showToast(`${symbol} removed`, "success");
    });
  });
}

// ─── Screen: Send ─────────────────────────────────────

function renderSend() {
  return `
    ${renderSubHeader("Send", "dashboard")}

    <div class="send-form">
      <div class="form-group">
        <label class="form-label">Transfer Type</label>
        <div style="display:flex;gap:6px;margin-bottom:4px" id="transfer-type-group">
          <button class="transfer-type-btn active" data-type="private" style="flex:1;padding:8px 4px;border:1px solid rgba(74,222,128,0.3);background:rgba(74,222,128,0.08);color:var(--green);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">PRIVATE</button>
          <button class="transfer-type-btn" data-type="public" style="flex:1;padding:8px 4px;border:1px solid var(--border);background:var(--bg-elevated);color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">PUBLIC</button>
          <button class="transfer-type-btn" data-type="shield" style="flex:1;padding:8px 4px;border:1px solid var(--border);background:var(--bg-elevated);color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">SHIELD</button>
          <button class="transfer-type-btn" data-type="unshield" style="flex:1;padding:8px 4px;border:1px solid var(--border);background:var(--bg-elevated);color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">UNSHIELD</button>
        </div>
      </div>

      <div class="form-group">
        <label class="form-label">Token</label>
        <select class="form-input" id="send-token" style="cursor:pointer;background:var(--bg-input);color:var(--text-warm)">
          ${store.tokens.map(t => {
            const pub = t.publicBalance || t.balance || "0";
            const priv = t.privateBalance || "0";
            return `<option value="${escapeHtml(t.symbol)}">${escapeHtml(t.icon)} ${escapeHtml(t.symbol)} — Pub: ${escapeHtml(pub)} / Priv: ${escapeHtml(priv)}</option>`;
          }).join("")}
        </select>
      </div>

      <div class="form-group" style="position:relative">
        <label class="form-label">Amount</label>
        <input type="text" class="form-input amount" id="send-amount" placeholder="0.00" autocomplete="off" />
        <button class="max-btn" id="btn-max">MAX</button>
      </div>

      <div class="form-group">
        <label class="form-label">Recipient Address</label>
        <input type="text" class="form-input" id="send-to" placeholder="0x..." autocomplete="off" />
      </div>

      <div id="transfer-info-box" style="background:var(--green-glow);border:1px solid rgba(74,222,128,0.15);padding:10px 12px;margin-bottom:16px;display:flex;align-items:center;gap:8px">
        <span style="color:var(--green)">${icons.lock}</span>
        <span style="font-size:10px;color:var(--green);font-family:IBM Plex Mono,monospace;letter-spacing:0.5px">Fully private transfer — invisible to observers</span>
      </div>

      <button id="btn-confirm-send" class="btn btn-passkey" ${store.loading ? "disabled" : ""}>
        ${store.loading ? '<div class="spinner"></div> Signing...' : 'Sign & Send'}
      </button>
    </div>`;
}

function bindSend() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));
  document.getElementById("btn-max")?.addEventListener("click", () => {
    // Read actual balance of selected token
    const selectedSymbol = document.getElementById("send-token")?.value;
    const token = store.tokens.find(t => t.symbol === selectedSymbol);
    const balance = token?.balance?.replace(/,/g, "") || "0";
    document.getElementById("send-amount").value = balance;
  });
  document.getElementById("btn-confirm-send")?.addEventListener("click", handleSendConfirm);

  // Transfer type toggle
  const transferTypeDescs = {
    private: { text: "Fully private transfer — invisible to observers", color: "var(--green)", icon: icons.lock },
    public: { text: "Public transfer — visible on-chain (like Ethereum)", color: "var(--copper)", icon: icons.send },
    shield: { text: "Shield — move public balance into private notes", color: "var(--green)", icon: icons.shield },
    unshield: { text: "Unshield — move private notes to public balance", color: "var(--copper)", icon: icons.shield },
  };

  document.querySelectorAll(".transfer-type-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".transfer-type-btn").forEach(b => {
        b.classList.remove("active");
        b.style.borderColor = "var(--border)";
        b.style.background = "var(--bg-elevated)";
        b.style.color = "var(--text-dim)";
      });
      btn.classList.add("active");
      const type = btn.dataset.type;
      const desc = transferTypeDescs[type];
      if (type === "private" || type === "shield") {
        btn.style.borderColor = "rgba(74,222,128,0.3)";
        btn.style.background = "rgba(74,222,128,0.08)";
        btn.style.color = "var(--green)";
      } else {
        btn.style.borderColor = "rgba(200,121,65,0.3)";
        btn.style.background = "rgba(200,121,65,0.08)";
        btn.style.color = "var(--copper)";
      }
      store.sendForm.transferType = type;
      const infoBox = document.getElementById("transfer-info-box");
      if (infoBox && desc) {
        infoBox.style.borderColor = type === "private" || type === "shield" ? "rgba(74,222,128,0.15)" : "rgba(200,121,65,0.15)";
        infoBox.style.background = type === "private" || type === "shield" ? "var(--green-glow)" : "rgba(200,121,65,0.05)";
        infoBox.innerHTML = `<span style="color:${desc.color}">${desc.icon}</span><span style="font-size:10px;color:${desc.color};font-family:IBM Plex Mono,monospace;letter-spacing:0.5px">${desc.text}</span>`;
      }
    });
  });
  store.sendForm.transferType = "private";
}

async function handleSendConfirm() {
  const to = document.getElementById("send-to")?.value?.trim();
  const amount = document.getElementById("send-amount")?.value?.trim();
  const tokenSymbol = document.getElementById("send-token")?.value;

  if (!to || !isValidAddress(to)) {
    showToast("Enter a valid address (0x...)", "error"); return;
  }
  if (!amount || !isValidAmount(amount)) {
    showToast("Enter a valid amount", "error"); return;
  }

  const btn = document.getElementById("btn-confirm-send");
  btn.disabled = true;
  btn.textContent = "Verifying passkey...";

  const account = getActiveAccount();

  try {
    // Passkey verification (biometric)
    if (account?.type === "passkey") {
      const challenge = crypto.getRandomValues(new Uint8Array(32));
      const assertion = await navigator.credentials.get({
        publicKey: {
          challenge,
          rpId: location.hostname,
          allowCredentials: [{ type: "public-key", id: base64UrlToBytes(account.credentialId) }],
          userVerification: "required",
          timeout: 60000,
        },
      });
      if (!assertion) throw new Error("Passkey verification cancelled");
    }

    // Find token address from store or custom tokens
    let tokenInfo = store.tokenAddresses?.[tokenSymbol];
    if (!tokenInfo) {
      // Try custom tokens
      const customToken = store.customTokens.find(t => t.symbol === tokenSymbol);
      if (customToken?.contractAddress) {
        tokenInfo = customToken.contractAddress;
      }
    }
    if (!tokenInfo) {
      throw new Error("Token address not found. Deploy your account and wait for balances to load.");
    }

    // Try client-side PXE first (WASM proving), fall back to deploy server
    let result;
    const hasPxeKeys = await new Promise((resolve) => {
      chrome.storage.session.get(["celari_private_key", "celari_secret"], (data) => {
        resolve(!!(data.celari_private_key && data.celari_secret));
      });
    });

    if (hasPxeKeys) {
      btn.textContent = "Proving locally (WASM)...";
      try {
        result = await new Promise((resolve, reject) => {
          chrome.runtime.sendMessage({
            type: "PXE_TRANSFER",
            data: { to, amount, tokenAddress: tokenInfo, transferType: store.sendForm.transferType || "private" },
          }, (res) => {
            if (res?.success && res.txHash) {
              resolve(res);
            } else {
              reject(new Error(res?.error || "PXE transfer failed"));
            }
          });
        });
        console.log("PXE transfer succeeded:", result.txHash);
      } catch (pxeErr) {
        console.warn("PXE transfer failed, falling back to server:", pxeErr.message);
        btn.textContent = "Sending via server...";
        result = null; // Fall through to server
      }
    }

    // Fallback: deploy server mint-based transfer
    if (!result) {
      btn.textContent = "Sending to network...";
      const res = await fetch(getDeployServer() + "/api/transfer", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          from: account.address,
          to,
          amount,
          tokenAddress: tokenInfo,
        }),
        signal: AbortSignal.timeout(300000),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "Transfer failed" }));
        throw new Error(err.error || "HTTP " + res.status);
      }

      result = await res.json();
    }

    store.activities.unshift({
      type: "send",
      label: "Transfer",
      to: to.slice(0, 8) + "...",
      amount: `-${amount} ${tokenSymbol}`,
      time: "Now",
      private: true,
      txHash: result.txHash,
    });

    // Refresh balances
    fetchRealBalances();

    setState({ screen: "dashboard" });
    showToast("Transfer successful! Block " + result.blockNumber, "success");

  } catch (e) {
    btn.disabled = false;
    btn.textContent = "Sign & Send";
    showToast(sanitizeError(e), "error");
  }
}

// ─── Screen: Receive ──────────────────────────────────

function renderReceive() {
  const account = getActiveAccount();
  const address = account?.address || "0x...";

  return `
    ${renderSubHeader("My Address", "dashboard")}

    <div style="padding:20px 16px;text-align:center">
      <div style="width:200px;height:200px;margin:0 auto 8px;background:#E8D8CC;display:flex;align-items:center;justify-content:center;position:relative">
        ${renderSimpleQR(address)}
        <div style="position:absolute;background:#1C1616;width:36px;height:36px;display:flex;align-items:center;justify-content:center;">
          <span style="font-family:Poiret One,cursive;font-size:18px;color:#C87941">C</span>
        </div>
      </div>
      <div style="font-family:IBM Plex Mono,monospace;font-size:7px;color:var(--text-faint);margin-bottom:12px;letter-spacing:1px;opacity:0.6">DECORATIVE ONLY — USE COPY BUTTON BELOW</div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;letter-spacing:4px;color:var(--text-faint);margin-bottom:8px;text-transform:uppercase">My Address on Aztec</div>

      <div style="background:var(--bg-card);border:1px solid var(--border);padding:12px;word-break:break-all;font-family:IBM Plex Mono,monospace;font-size:10px;color:var(--copper);margin-bottom:12px;text-align:left;letter-spacing:0.5px">
        ${escapeHtml(address)}
      </div>

      <button id="btn-copy-full" class="btn btn-primary" style="margin-bottom:10px">Copy Address</button>

      <div style="background:var(--green-glow);border:1px solid rgba(74,222,128,0.15);padding:10px;margin-top:8px">
        <div style="font-size:10px;color:var(--green);display:flex;align-items:center;gap:6px;justify-content:center;font-family:IBM Plex Mono,monospace;letter-spacing:0.5px">
          ${icons.lock} Incoming transfers are automatically shielded
        </div>
      </div>
    </div>`;
}

function bindReceive() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));
  document.getElementById("btn-copy-full")?.addEventListener("click", () => {
    const account = getActiveAccount();
    if (account) {
      navigator.clipboard.writeText(account.address);
      const btn = document.getElementById("btn-copy-full");
      btn.textContent = "Copied!";
      setTimeout(() => { btn.textContent = "Copy Address"; }, 2000);
    }
  });
}

// ─── Screen: Activity ─────────────────────────────────

function renderActivity() {
  return `
    ${renderSubHeader("Transaction History", "dashboard")}
    <div style="padding:12px 16px">
      ${store.activities.length === 0
        ? `<div style="text-align:center;padding:40px 0;color:var(--text-dim)">
            <p style="font-size:12px;font-family:IBM Plex Mono,monospace;letter-spacing:2px">NO TRANSACTIONS YET</p>
          </div>`
        : renderActivityList()}
    </div>`;
}

function bindActivity() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));
}

// ─── Screen: Add Token ───────────────────────────────

function renderAddToken() {
  return `
    ${renderSubHeader("Add Token", "dashboard")}
    <div style="padding:16px">
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:12px">Custom Token</div>

      <div class="form-group">
        <label class="form-label">Contract Address</label>
        <input type="text" class="form-input" id="token-address" placeholder="0x..." autocomplete="off" />
      </div>

      <div class="form-group">
        <label class="form-label">Token Name</label>
        <input type="text" class="form-input" id="token-name" placeholder="e.g. My Token" autocomplete="off" maxlength="32" />
      </div>

      <div style="display:flex;gap:10px">
        <div class="form-group" style="flex:1">
          <label class="form-label">Symbol</label>
          <input type="text" class="form-input" id="token-symbol" placeholder="e.g. MTK" autocomplete="off" maxlength="10" />
        </div>
        <div class="form-group" style="flex:1">
          <label class="form-label">Decimals</label>
          <input type="number" class="form-input" id="token-decimals" value="18" min="0" max="36" autocomplete="off" />
        </div>
      </div>

      <div id="token-validation-status" style="display:none;padding:10px 12px;margin-bottom:14px;font-family:IBM Plex Mono,monospace;font-size:9px;letter-spacing:0.5px"></div>

      <button id="btn-save-token" class="btn btn-primary">Add Token</button>

      ${store.customTokens.length > 0 ? `
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-top:20px;margin-bottom:8px">Custom Tokens (${store.customTokens.length})</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);overflow:hidden">
        ${store.customTokens.map(t => `
        <div style="padding:10px 12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border)">
          <div class="token-icon" style="width:24px;height:24px;border-color:#9A7B5B;font-size:11px"><span style="transform:rotate(-45deg);color:#9A7B5B;font-family:Poiret One,cursive">${escapeHtml((t.symbol || "?")[0])}</span></div>
          <div style="flex:1;min-width:0">
            <div style="font-size:11px;color:var(--text-warm)">${escapeHtml(t.name)}</div>
            <div style="font-size:8px;color:var(--text-dim);font-family:IBM Plex Mono,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escapeHtml(t.contractAddress)}</div>
          </div>
          <button class="btn-remove-custom-token" data-symbol="${escapeHtml(t.symbol)}" style="background:none;border:none;color:var(--text-faint);cursor:pointer;font-size:14px;padding:2px 6px;transition:color 0.2s">&times;</button>
        </div>`).join("")}
      </div>` : ''}
    </div>`;
}

function bindAddToken() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));

  document.getElementById("btn-save-token")?.addEventListener("click", () => {
    const address = document.getElementById("token-address")?.value?.trim();
    const name = document.getElementById("token-name")?.value?.trim();
    const symbol = document.getElementById("token-symbol")?.value?.trim().toUpperCase();
    const decimals = parseInt(document.getElementById("token-decimals")?.value || "18");

    // Validation
    if (!address || !isValidAddress(address)) {
      showValidationStatus("Enter a valid contract address (0x...)", true);
      return;
    }
    if (!name || name.length < 1) {
      showValidationStatus("Enter a token name", true);
      return;
    }
    if (!symbol || symbol.length < 1 || symbol.length > 10) {
      showValidationStatus("Enter a symbol (1-10 characters)", true);
      return;
    }
    if (isNaN(decimals) || decimals < 0 || decimals > 36) {
      showValidationStatus("Decimals must be 0-36", true);
      return;
    }

    // Check for duplicates
    const allSymbols = [...DEFAULT_TOKENS.map(t => t.symbol), ...store.customTokens.map(t => t.symbol)];
    if (allSymbols.includes(symbol)) {
      showValidationStatus(`Token "${symbol}" already exists`, true);
      return;
    }

    const dupAddress = store.customTokens.find(t => t.contractAddress.toLowerCase() === address.toLowerCase());
    if (dupAddress) {
      showValidationStatus(`Contract already added as ${dupAddress.symbol}`, true);
      return;
    }

    // Save token
    const newToken = { contractAddress: address, name, symbol, decimals };
    store.customTokens.push(newToken);
    chrome.storage.local.set({ celari_custom_tokens: store.customTokens });

    // Refresh tokens list
    store.tokens = getTokenList();

    showToast(`${symbol} added`, "success");
    setState({ screen: "dashboard" });
  });

  // Remove buttons in the custom token list
  document.querySelectorAll(".btn-remove-custom-token").forEach(btn => {
    btn.addEventListener("click", () => {
      const symbol = btn.dataset.symbol;
      if (!confirm(`Remove ${symbol}?`)) return;
      store.customTokens = store.customTokens.filter(t => t.symbol !== symbol);
      chrome.storage.local.set({ celari_custom_tokens: store.customTokens });
      store.tokens = store.tokens.filter(t => !(t.isCustom && t.symbol === symbol));
      render();
      showToast(`${symbol} removed`, "success");
    });
  });
}

function showValidationStatus(msg, isError) {
  const el = document.getElementById("token-validation-status");
  if (!el) return;
  el.style.display = "block";
  el.style.background = isError ? "rgba(239,68,68,0.05)" : "var(--green-glow)";
  el.style.border = isError ? "1px solid rgba(239,68,68,0.2)" : "1px solid rgba(74,222,128,0.15)";
  el.style.color = isError ? "var(--red)" : "var(--green)";
  el.textContent = msg;
}

function showRpcTestResult(msg, isError) {
  const el = document.getElementById("rpc-test-result");
  if (!el) return;
  el.style.display = "block";
  el.style.background = isError ? "rgba(239,68,68,0.05)" : "var(--green-glow)";
  el.style.border = isError ? "1px solid rgba(239,68,68,0.2)" : "1px solid rgba(74,222,128,0.15)";
  el.style.color = isError ? "var(--red)" : "var(--green)";
  el.textContent = msg;
}

// ─── Screen: Settings ─────────────────────────────────

function renderSettings() {
  const account = getActiveAccount();
  const isPasskey = account?.type === "passkey";

  return `
    ${renderSubHeader("Settings", "dashboard")}
    <div style="padding:12px 16px">
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px;margin-top:4px">Account</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;overflow:hidden">
        <div style="padding:12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border)">
          <div style="width:28px;height:28px;border:1px solid var(--border);transform:rotate(45deg);display:flex;align-items:center;justify-content:center">
            <span style="transform:rotate(-45deg);color:var(--copper);font-size:12px">${isPasskey ? icons.lock : "D"}</span>
          </div>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--text-warm)">${escapeHtml(account?.label || "Account")}</div>
            <div style="font-size:10px;color:var(--text-dim)">${isPasskey ? "Passkey (P256)" : "Demo mode"}</div>
          </div>
          <span style="font-size:8px;padding:3px 8px;font-family:IBM Plex Mono,monospace;letter-spacing:2px;background:${isPasskey ? 'var(--green-glow)' : 'rgba(200,121,65,0.08)'};color:${isPasskey ? 'var(--green)' : 'var(--copper)'};border:1px solid ${isPasskey ? 'rgba(74,222,128,0.15)' : 'rgba(200,121,65,0.2)'}">${isPasskey ? "ACTIVE" : "DEMO"}</span>
        </div>
        <div style="padding:12px;font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--text-dim);word-break:break-all;letter-spacing:0.5px">
          ${escapeHtml(account?.address || "")}
        </div>
      </div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Network</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;overflow:hidden">
        ${renderNetworkRow("local", "Local Sandbox", "localhost:8080")}
        ${renderNetworkRow("devnet", "Aztec Devnet", "devnet-6.aztec-labs.com")}
        ${renderNetworkRow("testnet", "Aztec Testnet", "rpc.testnet.aztec-labs.com")}
        ${store.customNetworks.map(n => {
          let host;
          try { host = new URL(n.url).host; } catch { host = n.url; }
          return renderNetworkRow(n.id, n.name, host, true);
        }).join("")}
      </div>

      <div id="custom-rpc-section" style="margin-bottom:16px">
        <button id="btn-toggle-add-rpc" style="width:100%;padding:10px;background:var(--bg-card);border:1px solid var(--border);color:var(--text-dim);cursor:pointer;font-family:IBM Plex Mono,monospace;font-size:9px;letter-spacing:2px;transition:all 0.2s">+ ADD CUSTOM RPC</button>
        <div id="add-rpc-form" style="display:none;background:var(--bg-card);border:1px solid var(--border);border-top:none;padding:12px">
          <div class="form-group" style="margin-bottom:8px">
            <label class="form-label">Name</label>
            <input type="text" class="form-input" id="rpc-name" placeholder="My Node" autocomplete="off" maxlength="24" style="padding:8px 10px;font-size:12px" />
          </div>
          <div class="form-group" style="margin-bottom:8px">
            <label class="form-label">RPC URL</label>
            <input type="text" class="form-input" id="rpc-url" placeholder="https://..." autocomplete="off" style="padding:8px 10px;font-size:12px" />
          </div>
          <div id="rpc-test-result" style="display:none;padding:8px 10px;margin-bottom:8px;font-family:IBM Plex Mono,monospace;font-size:9px;letter-spacing:0.5px"></div>
          <div style="display:flex;gap:8px">
            <button id="btn-test-rpc" class="btn btn-secondary" style="flex:1;padding:8px;font-size:8px">TEST</button>
            <button id="btn-save-rpc" class="btn btn-primary" style="flex:1;padding:8px;font-size:8px">SAVE</button>
          </div>
        </div>
      </div>
      ${store.connected && store.nodeInfo ? `
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;padding:10px 12px;font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--text-dim)">
        <div style="display:flex;justify-content:space-between;margin-bottom:4px"><span>Version</span><span style="color:var(--text-muted)">${escapeHtml(store.nodeInfo?.nodeVersion || '-')}</span></div>
        <div style="display:flex;justify-content:space-between"><span>Chain ID</span><span style="color:var(--text-muted)">${escapeHtml(String(store.nodeInfo?.l1ChainId || '-'))}</span></div>
      </div>` : ''}

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Deploy Server</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;padding:12px">
        <div class="form-group" style="margin-bottom:8px">
          <label class="form-label" style="font-size:9px;color:var(--text-dim)">Server URL</label>
          <input type="text" class="form-input" id="deploy-server-url" value="${escapeHtml(store.deployServerUrl)}" placeholder="http://localhost:3456" autocomplete="off" style="padding:8px 10px;font-size:11px;font-family:IBM Plex Mono,monospace" />
        </div>
        <button id="btn-save-deploy-server" class="btn btn-secondary" style="width:100%;padding:8px;font-size:8px">SAVE</button>
      </div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Security</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;overflow:hidden">
        <div style="padding:12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border)">
          <span style="color:var(--copper)">${icons.lock}</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--text-warm)">Passkey Management</div>
            <div style="font-size:10px;color:var(--text-dim)">Face ID / Fingerprint settings</div>
          </div>
        </div>
        <div style="padding:12px;display:flex;align-items:center;gap:10px">
          <span style="color:var(--copper)">${icons.shield}</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--text-warm)">Public Key</div>
            <div style="font-size:9px;color:var(--text-dim);word-break:break-all;font-family:IBM Plex Mono,monospace">${escapeHtml(account?.publicKeyX?.slice(0, 20) || "")}...</div>
          </div>
        </div>
      </div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Backup & Recovery</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;overflow:hidden">
        <div id="btn-backup-export" class="settings-row" style="padding:12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border);cursor:pointer">
          <span style="color:var(--copper)">${icons.shield}</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--text-warm)">Export Backup</div>
            <div style="font-size:10px;color:var(--text-dim)">Encrypted JSON file</div>
          </div>
        </div>
        <div id="btn-backup-import" class="settings-row" style="padding:12px;display:flex;align-items:center;gap:10px;cursor:pointer">
          <span style="color:var(--copper)">${icons.download}</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--text-warm)">Import Backup</div>
            <div style="font-size:10px;color:var(--text-dim)">Restore from encrypted file</div>
          </div>
        </div>
      </div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Actions</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);margin-bottom:16px;overflow:hidden">
        ${store.accounts.length > 1 ? `
        <div id="btn-delete-account" class="settings-row" style="padding:12px;display:flex;align-items:center;gap:10px;cursor:pointer;border-bottom:1px solid var(--border)">
          <span style="color:var(--red)">&times;</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--red)">Delete Account</div>
            <div style="font-size:10px;color:var(--text-dim)">Remove "${escapeHtml(account?.label || 'this account')}" permanently</div>
          </div>
        </div>` : ''}
        <div id="btn-logout" class="settings-row" style="padding:12px;display:flex;align-items:center;gap:10px;cursor:pointer">
          <span style="color:var(--red)">${icons.back}</span>
          <div style="flex:1">
            <div style="font-weight:400;font-size:12px;color:var(--red)">Log Out</div>
            <div style="font-size:10px;color:var(--text-dim)">Reset wallet and return to onboarding</div>
          </div>
        </div>
      </div>

      <div style="text-align:center;padding:12px 0;color:var(--text-faint);font-family:IBM Plex Mono,monospace;font-size:8px;letter-spacing:2px">
        CELARI v0.4.0 · AZTEC SDK v3 · PHASE 2<br/>
        <span style="font-family:Tenor Sans,serif;font-size:11px;font-style:italic;letter-spacing:0;color:var(--text-dim);margin-top:4px;display:block">celāre — to hide, to conceal</span>
      </div>
    </div>`;
}

function renderNetworkRow(id, name, url, isCustom = false) {
  const isActive = store.network === id;
  const isConnected = isActive && store.connected;
  const dotColor = isConnected ? "var(--green)" : isActive ? "var(--copper)" : "var(--border)";
  return `
    <div class="settings-row" id="btn-network-${escapeHtml(id)}" style="padding:12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border);cursor:pointer">
      <div style="width:6px;height:6px;border-radius:50%;background:${dotColor}"></div>
      <div style="flex:1">
        <div style="font-weight:400;font-size:11px;color:var(--text-warm)">${escapeHtml(name)}${isCustom ? ' <span style="color:var(--text-faint);font-size:7px;font-family:IBM Plex Mono,monospace">CUSTOM</span>' : ''}</div>
        <div style="font-size:9px;color:var(--text-dim);font-family:IBM Plex Mono,monospace">${escapeHtml(url)}</div>
      </div>
      ${isCustom && !isActive ? `<button class="btn-delete-network" data-network-id="${escapeHtml(id)}" style="background:none;border:none;color:var(--text-faint);cursor:pointer;font-size:14px;padding:2px 4px;transition:color 0.2s" title="Remove">&times;</button>` : ''}
      ${isActive ? `<span style="color:var(--copper)">${icons.check}</span>` : ""}
    </div>`;
}

function bindSettings() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));

  const switchNetwork = (network) => {
    chrome.runtime.sendMessage({ type: "SET_NETWORK", network }, (resp) => {
      if (resp?.success) {
        setState({
          network: resp.state.network,
          nodeUrl: resp.state.nodeUrl,
          connected: resp.state.connected,
          nodeInfo: resp.state.nodeInfo,
        });
        const name = network === "local" ? "Local Sandbox" : network === "devnet" ? "Devnet" : "Testnet";
        showToast(resp.state.connected ? `${name} connected` : `${name} connecting...`, resp.state.connected ? "success" : "error");
      }
    });
  };

  document.getElementById("btn-network-local")?.addEventListener("click", () => switchNetwork("local"));
  document.getElementById("btn-network-devnet")?.addEventListener("click", () => switchNetwork("devnet"));
  document.getElementById("btn-network-testnet")?.addEventListener("click", () => switchNetwork("testnet"));

  // Custom network click handlers
  store.customNetworks.forEach(n => {
    document.getElementById(`btn-network-${n.id}`)?.addEventListener("click", (e) => {
      if (e.target.closest(".btn-delete-network")) return;
      chrome.runtime.sendMessage({ type: "SET_NETWORK", nodeUrl: n.url, networkId: n.id }, (resp) => {
        if (resp?.success) {
          setState({
            network: resp.state.network,
            nodeUrl: resp.state.nodeUrl,
            connected: resp.state.connected,
            nodeInfo: resp.state.nodeInfo,
          });
          showToast(resp.state.connected ? `${n.name} connected` : `${n.name} connecting...`, resp.state.connected ? "success" : "error");
        }
      });
    });
  });

  // Delete custom network
  document.querySelectorAll(".btn-delete-network").forEach(btn => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const netId = btn.dataset.networkId;
      const netName = store.customNetworks.find(n => n.id === netId)?.name || netId;
      if (!confirm(`Remove "${netName}"?`)) return;
      chrome.runtime.sendMessage({ type: "DELETE_CUSTOM_NETWORK", networkId: netId }, (resp) => {
        if (resp?.success) {
          store.customNetworks = resp.networks;
          if (resp.state) {
            store.network = resp.state.network;
            store.nodeUrl = resp.state.nodeUrl;
            store.connected = resp.state.connected;
            store.nodeInfo = resp.state.nodeInfo;
          }
          render();
          showToast(`${netName} removed`, "success");
        }
      });
    });
  });

  // Toggle add-rpc form
  document.getElementById("btn-toggle-add-rpc")?.addEventListener("click", () => {
    const form = document.getElementById("add-rpc-form");
    if (form) form.style.display = form.style.display === "none" ? "block" : "none";
  });

  // Test RPC connection
  document.getElementById("btn-test-rpc")?.addEventListener("click", async () => {
    const url = document.getElementById("rpc-url")?.value?.trim();
    if (!url) { showRpcTestResult("Enter a URL", true); return; }

    try {
      new URL(url);
    } catch {
      showRpcTestResult("Invalid URL format", true);
      return;
    }

    showRpcTestResult("Testing connection...", false);
    const start = Date.now();
    try {
      const res = await fetch(url.replace(/\/$/, ""), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", method: "node_getNodeInfo", params: [], id: 1 }),
        signal: AbortSignal.timeout(10000),
      });
      const latency = Date.now() - start;
      if (res.ok) {
        const data = await res.json();
        if (data.result) {
          showRpcTestResult(`Connected (${latency}ms) — v${data.result.nodeVersion || "unknown"}`, false);
        } else {
          showRpcTestResult(`Response OK (${latency}ms) but no node info`, true);
        }
      } else {
        showRpcTestResult(`HTTP ${res.status} — check URL`, true);
      }
    } catch (e) {
      showRpcTestResult("Connection failed: " + sanitizeError(e), true);
    }
  });

  // Save custom RPC
  document.getElementById("btn-save-rpc")?.addEventListener("click", () => {
    const name = document.getElementById("rpc-name")?.value?.trim();
    const url = document.getElementById("rpc-url")?.value?.trim();
    if (!name || name.length < 1) { showRpcTestResult("Enter a name", true); return; }
    if (!url) { showRpcTestResult("Enter a URL", true); return; }
    try { new URL(url); } catch { showRpcTestResult("Invalid URL format", true); return; }

    const id = "custom_" + Date.now().toString(36);
    const networkData = { id, name, url };

    chrome.runtime.sendMessage({ type: "SAVE_CUSTOM_NETWORK", networkData }, (resp) => {
      if (resp?.success) {
        store.customNetworks = resp.networks;
        render();
        showToast(`${name} added`, "success");
      } else {
        showRpcTestResult(resp?.error || "Save failed", true);
      }
    });
  });

  // Save deploy server URL
  document.getElementById("btn-save-deploy-server")?.addEventListener("click", () => {
    const urlInput = document.getElementById("deploy-server-url");
    const url = urlInput?.value?.trim();
    if (!url) { showToast("Enter a server URL", "error"); return; }
    try { new URL(url); } catch { showToast("Invalid URL format", "error"); return; }
    store.deployServerUrl = url;
    chrome.storage.local.set({ celari_deploy_server: url });
    showToast("Deploy server saved", "success");
  });

  // Delete current account
  document.getElementById("btn-delete-account")?.addEventListener("click", () => {
    const account = getActiveAccount();
    if (!confirm(`Delete "${account?.label || 'this account'}"? This cannot be undone.`)) return;
    chrome.runtime.sendMessage({ type: "DELETE_ACCOUNT", index: store.activeAccountIndex }, (resp) => {
      if (resp?.success) {
        store.accounts = resp.accounts;
        store.activeAccountIndex = resp.activeAccountIndex;
        store.tokens = getTokenList();
        fetchRealBalances();
        setState({ screen: "dashboard" });
        showToast("Account deleted", "success");
      } else {
        showToast(resp?.error || "Delete failed", "error");
      }
    });
  });

  // Backup & Recovery
  document.getElementById("btn-backup-export")?.addEventListener("click", () => setState({ screen: "backup" }));
  document.getElementById("btn-backup-import")?.addEventListener("click", () => setState({ screen: "restore" }));

  document.getElementById("btn-logout")?.addEventListener("click", async () => {
    if (!confirm("Are you sure you want to reset the wallet? All data will be deleted.")) return;
    await chrome.storage.local.remove(["celari_accounts", "celari_deploy_info", "celari_custom_tokens", "celari_custom_networks", "celari_deploy_server", "celari_custom_nft_contracts"]);
    await chrome.storage.session.remove(["celari_keys", "celari_secret", "celari_private_key"]);
    store.accounts = [];
    store.tokens = [];
    store.customTokens = [];
    store.customNetworks = [];
    store.activities = [];
    store.nfts = [];
    store.customNftContracts = [];
    store.activeAccountIndex = 0;
    setState({ screen: "onboarding" });
    showToast("Wallet reset", "success");
  });
}

// ─── Shared Components ────────────────────────────────

function renderHeader() {
  return `
    <div class="header">
      <div class="header-logo">
        ${LOGO_SVG}
        <span>Celari</span>
      </div>
      <div style="display:flex;align-items:center;gap:8px">
        <div class="header-network" id="btn-network-toggle">
          <div class="network-dot ${store.connected ? '' : 'disconnected'}"></div>
          ${store.network === "devnet" ? "Devnet" : store.network === "testnet" ? "Testnet" : store.network === "local" ? "Sandbox" : escapeHtml(store.customNetworks.find(n => n.id === store.network)?.name || "Custom")}
        </div>
        <button id="btn-walletconnect" title="WalletConnect" style="background:none;border:none;color:${store.wcSessions.length ? 'var(--green)' : 'var(--text-dim)'};cursor:pointer;padding:4px;display:flex"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5.5 8.5c3.6-3.6 9.4-3.6 13 0"/><path d="M8 11c2.2-2.2 5.8-2.2 8 0"/><path d="M10.5 13.5c.8-.8 2.2-.8 3 0"/></svg></button>
        <button id="btn-settings" style="background:none;border:none;color:var(--text-dim);cursor:pointer;padding:4px;display:flex">${icons.settings}</button>
      </div>
    </div>`;
}

function renderSubHeader(title, backScreen) {
  return `
    <div class="header">
      <div style="display:flex;align-items:center;gap:8px">
        <button id="btn-back" class="back-btn">${icons.back}</button>
        <span style="font-family:Poiret One,cursive;font-size:14px;letter-spacing:4px;text-transform:uppercase">${escapeHtml(title)}</span>
      </div>
      <div class="header-logo">${LOGO_SVG}</div>
    </div>`;
}

function renderSimpleQR(data) {
  const size = 200;
  const cells = 15;
  const cellSize = size / cells;
  let rects = "";

  let hash = 0;
  for (let i = 0; i < data.length; i++) {
    hash = ((hash << 5) - hash + data.charCodeAt(i)) | 0;
  }

  for (let y = 0; y < cells; y++) {
    for (let x = 0; x < cells; x++) {
      const isCornerOuter = (x < 3 && y < 3) || (x >= cells - 3 && y < 3) || (x < 3 && y >= cells - 3);
      const isCornerInner = (x === 1 && y === 1) || (x === cells - 2 && y === 1) || (x === 1 && y === cells - 2);
      const isCornerBorder = isCornerOuter && !isCornerInner;
      const seed = (hash * (y * cells + x + 1)) >>> 0;
      const isData = !isCornerOuter && ((seed % 3) < 1);

      if (isCornerBorder || isCornerInner || isData) {
        rects += `<rect x="${x * cellSize}" y="${y * cellSize}" width="${cellSize - 1}" height="${cellSize - 1}" fill="#1C1616" rx="0"/>`;
      }
    }
  }

  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">${rects}</svg>`;
}

// ─── Toast Notifications ──────────────────────────────

function showToast(message, type = "success") {
  const existing = document.querySelector(".toast");
  if (existing) existing.remove();

  const toast = document.createElement("div");
  toast.className = `toast ${type}`;
  toast.textContent = message; // textContent prevents XSS
  document.body.appendChild(toast);

  setTimeout(() => toast.remove(), 3000);
}

// ─── Helpers ──────────────────────────────────────────

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function base64UrlToBytes(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// ─── Screen: Confirm Transaction (dApp) ───────────────

function renderConfirmTx() {
  const req = store.pendingSignRequest;
  if (!req) return renderLoading();

  const origin = escapeHtml(req.origin);
  const txData = req.payload?.transaction;
  const fnName = escapeHtml(txData?.functionName || txData?.method || "Unknown");
  const contract = escapeHtml(txData?.contractAddress || txData?.to || "Unknown");
  const shortContract = contract.length > 20
    ? contract.slice(0, 10) + "..." + contract.slice(-8)
    : contract;

  return `
    <div class="onboarding" style="padding:28px 20px;gap:16px">
      <div style="width:48px;height:48px;background:var(--burgundy);transform:rotate(45deg);display:flex;align-items:center;justify-content:center;margin-bottom:4px">
        <span style="transform:rotate(-45deg);font-size:22px;color:var(--copper)">⚡</span>
      </div>
      <h2 style="font-family:'Poiret One',serif;font-size:20px;color:var(--gold);letter-spacing:2px;margin:0">
        SIGN REQUEST
      </h2>
      <p style="font-size:10px;letter-spacing:2px;color:var(--text-dim);text-transform:uppercase;margin:0">
        A dApp is requesting your signature
      </p>

      <div style="width:100%;background:var(--surface);border:1px solid var(--border);padding:16px;margin:8px 0">
        <div style="display:flex;justify-content:space-between;margin-bottom:10px">
          <span style="font-size:10px;color:var(--text-dim);letter-spacing:1px">ORIGIN</span>
          <span style="font-size:11px;color:var(--text-primary);font-family:'IBM Plex Mono',monospace">${origin}</span>
        </div>
        <div style="display:flex;justify-content:space-between;margin-bottom:10px">
          <span style="font-size:10px;color:var(--text-dim);letter-spacing:1px">FUNCTION</span>
          <span style="font-size:11px;color:var(--copper);font-family:'IBM Plex Mono',monospace">${fnName}</span>
        </div>
        <div style="display:flex;justify-content:space-between">
          <span style="font-size:10px;color:var(--text-dim);letter-spacing:1px">CONTRACT</span>
          <span style="font-size:11px;color:var(--text-primary);font-family:'IBM Plex Mono',monospace" title="${contract}">${shortContract}</span>
        </div>
      </div>

      <p style="font-size:10px;color:var(--burgundy);text-align:center;margin:0;line-height:1.5">
        Review the details above carefully.<br>Only approve transactions from trusted dApps.
      </p>

      <div style="display:flex;gap:12px;width:100%;margin-top:8px">
        <button id="btnRejectTx" class="btn btn-secondary" style="flex:1">Reject</button>
        <button id="btnApproveTx" class="btn btn-primary" style="flex:1">Approve</button>
      </div>
    </div>`;
}

function bindConfirmTx() {
  document.getElementById("btnApproveTx")?.addEventListener("click", async () => {
    try {
      await chrome.runtime.sendMessage({
        type: "SIGN_APPROVE",
        requestId: store.pendingSignRequestId,
      });
    } catch (e) {}
    window.close();
  });

  document.getElementById("btnRejectTx")?.addEventListener("click", async () => {
    try {
      await chrome.runtime.sendMessage({
        type: "SIGN_REJECT",
        requestId: store.pendingSignRequestId,
      });
    } catch (e) {}
    window.close();
  });
}

// ─── Screen: Add Account (Phase 1) ────────────────────

function renderAddAccount() {
  return `
    ${renderSubHeader("Add Account", "dashboard")}
    <div class="onboarding" style="padding:24px">
      <div style="width:100%;margin-bottom:16px">
        <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:12px">Choose Method</div>

        <div id="btn-new-passkey-account" class="settings-row" style="background:var(--bg-card);border:1px solid var(--border);padding:16px;margin-bottom:10px;cursor:pointer;display:flex;align-items:center;gap:12px">
          <div style="width:36px;height:36px;border:1px solid var(--border);transform:rotate(45deg);display:flex;align-items:center;justify-content:center;flex-shrink:0">
            <span style="transform:rotate(-45deg);color:var(--copper)">${icons.lock}</span>
          </div>
          <div>
            <div style="font-weight:400;font-size:13px;color:var(--text-warm);margin-bottom:2px">New Passkey Account</div>
            <div style="font-size:10px;color:var(--text-dim)">Create with Face ID / fingerprint</div>
          </div>
        </div>

        <div id="btn-import-backup-account" class="settings-row" style="background:var(--bg-card);border:1px solid var(--border);padding:16px;cursor:pointer;display:flex;align-items:center;gap:12px">
          <div style="width:36px;height:36px;border:1px solid var(--border);transform:rotate(45deg);display:flex;align-items:center;justify-content:center;flex-shrink:0">
            <span style="transform:rotate(-45deg);color:var(--copper)">${icons.download}</span>
          </div>
          <div>
            <div style="font-weight:400;font-size:13px;color:var(--text-warm);margin-bottom:2px">Import from Backup</div>
            <div style="font-size:10px;color:var(--text-dim)">Restore encrypted JSON backup</div>
          </div>
        </div>
      </div>
    </div>`;
}

function bindAddAccount() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));
  document.getElementById("btn-new-passkey-account")?.addEventListener("click", () => {
    showToast("Creating new account...", "success");
    handleCreatePasskey();
  });
  document.getElementById("btn-import-backup-account")?.addEventListener("click", () => {
    setState({ screen: "restore" });
  });
}

// ─── Screen: Backup Export (Phase 2) ──────────────────

async function encryptBackup(data, password) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveKey"]);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 600000, hash: "SHA-256" },
    keyMaterial,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"],
  );
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(JSON.stringify(data)));
  return { v: 1, salt: Array.from(salt), iv: Array.from(iv), data: Array.from(new Uint8Array(encrypted)) };
}

async function decryptBackup(blob, password) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveKey"]);
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt: new Uint8Array(blob.salt), iterations: 600000, hash: "SHA-256" },
    keyMaterial,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"],
  );
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: new Uint8Array(blob.iv) },
    key,
    new Uint8Array(blob.data),
  );
  return JSON.parse(new TextDecoder().decode(decrypted));
}

function renderBackup() {
  const account = getActiveAccount();
  return `
    ${renderSubHeader("Export Backup", "settings")}
    <div style="padding:16px">
      <div style="background:rgba(239,68,68,0.05);border:1px solid rgba(239,68,68,0.15);padding:12px;margin-bottom:16px">
        <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--red);letter-spacing:2px;text-transform:uppercase;margin-bottom:4px">Warning</div>
        <div style="font-size:10px;color:var(--text-dim);line-height:1.5">This backup contains your private keys. Store it securely and never share it.</div>
      </div>

      <div style="background:var(--bg-card);border:1px solid var(--border);padding:12px;margin-bottom:16px">
        <div style="font-size:11px;color:var(--text-warm);margin-bottom:4px">${escapeHtml(account?.label || "Account")}</div>
        <div style="font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--text-dim);word-break:break-all">${escapeHtml(account?.address || "")}</div>
      </div>

      <div class="form-group">
        <label class="form-label">Encryption Password</label>
        <input type="password" class="form-input" id="backup-password" placeholder="Enter a strong password" autocomplete="new-password" />
      </div>
      <div class="form-group">
        <label class="form-label">Confirm Password</label>
        <input type="password" class="form-input" id="backup-password-confirm" placeholder="Repeat password" autocomplete="new-password" />
      </div>

      <div id="backup-status" style="display:none;padding:10px;margin-bottom:14px;font-family:IBM Plex Mono,monospace;font-size:9px"></div>

      <button id="btn-do-backup" class="btn btn-primary">Export Encrypted Backup</button>
    </div>`;
}

function bindBackup() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "settings" }));

  document.getElementById("btn-do-backup")?.addEventListener("click", async () => {
    const pw = document.getElementById("backup-password")?.value;
    const pw2 = document.getElementById("backup-password-confirm")?.value;
    const statusEl = document.getElementById("backup-status");

    if (!pw || pw.length < 8) {
      showBackupStatus(statusEl, "Password must be at least 8 characters", true);
      return;
    }
    if (pw !== pw2) {
      showBackupStatus(statusEl, "Passwords do not match", true);
      return;
    }

    const btn = document.getElementById("btn-do-backup");
    btn.disabled = true;
    btn.textContent = "ENCRYPTING...";
    showBackupStatus(statusEl, "Collecting account data...", false);

    try {
      const account = getActiveAccount();
      // Collect sensitive keys from session storage
      const sessionData = await chrome.storage.session.get(["celari_secret", "celari_private_key"]);

      const backupData = {
        version: 1,
        timestamp: new Date().toISOString(),
        label: account.label,
        address: account.address,
        publicKeyX: account.publicKeyX,
        publicKeyY: account.publicKeyY,
        secretKey: sessionData.celari_secret || account.secretKey,
        salt: account.salt,
        privateKeyPkcs8: sessionData.celari_private_key || account.privateKeyPkcs8,
        network: store.network,
        credentialId: account.credentialId,
      };

      if (!backupData.secretKey || !backupData.salt) {
        throw new Error("Account keys not available. Deploy your account first or ensure you have an active session.");
      }

      showBackupStatus(statusEl, "Encrypting with AES-256-GCM...", false);
      const encrypted = await encryptBackup(backupData, pw);

      // Download as file
      const blob = new Blob([JSON.stringify(encrypted)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `celari-backup-${account.label?.replace(/\s+/g, "-") || "account"}-${Date.now()}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);

      showBackupStatus(statusEl, "Backup exported successfully!", false);
      showToast("Backup saved", "success");
    } catch (e) {
      showBackupStatus(statusEl, sanitizeError(e), true);
    } finally {
      btn.disabled = false;
      btn.textContent = "EXPORT ENCRYPTED BACKUP";
    }
  });
}

function showBackupStatus(el, msg, isError) {
  if (!el) return;
  el.style.display = "block";
  el.style.background = isError ? "rgba(239,68,68,0.05)" : "var(--green-glow)";
  el.style.border = isError ? "1px solid rgba(239,68,68,0.2)" : "1px solid rgba(74,222,128,0.15)";
  el.style.color = isError ? "var(--red)" : "var(--green)";
  el.textContent = msg;
}

// ─── Screen: Restore from Backup (Phase 2) ────────────

function renderRestore() {
  return `
    ${renderSubHeader("Import Backup", store.accounts.length > 0 ? "settings" : "onboarding")}
    <div style="padding:16px">
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:12px">Encrypted Backup</div>

      <div id="restore-drop-zone" style="background:var(--bg-card);border:2px dashed var(--border);padding:24px;text-align:center;margin-bottom:16px;cursor:pointer;transition:border-color 0.3s">
        <div style="font-size:24px;margin-bottom:8px;opacity:0.3;color:var(--copper)">&#9671;</div>
        <div style="font-size:10px;color:var(--text-dim);letter-spacing:1px">Click or drop .celari-backup.json file</div>
        <input type="file" id="restore-file" accept=".json" style="display:none" />
      </div>

      <div id="restore-file-info" style="display:none;background:var(--bg-card);border:1px solid var(--border);padding:12px;margin-bottom:16px">
        <div style="font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--copper)" id="restore-filename"></div>
      </div>

      <div class="form-group">
        <label class="form-label">Decryption Password</label>
        <input type="password" class="form-input" id="restore-password" placeholder="Enter backup password" autocomplete="off" />
      </div>

      <div id="restore-status" style="display:none;padding:10px;margin-bottom:14px;font-family:IBM Plex Mono,monospace;font-size:9px"></div>

      <button id="btn-do-restore" class="btn btn-primary" disabled>Decrypt & Import</button>
    </div>`;
}

let restoreFileData = null;

function bindRestore() {
  const backScreen = store.accounts.length > 0 ? "settings" : "onboarding";
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: backScreen }));

  const dropZone = document.getElementById("restore-drop-zone");
  const fileInput = document.getElementById("restore-file");

  dropZone?.addEventListener("click", () => fileInput?.click());
  dropZone?.addEventListener("dragover", (e) => { e.preventDefault(); dropZone.style.borderColor = "var(--copper)"; });
  dropZone?.addEventListener("dragleave", () => { dropZone.style.borderColor = "var(--border)"; });
  dropZone?.addEventListener("drop", (e) => {
    e.preventDefault();
    dropZone.style.borderColor = "var(--border)";
    const file = e.dataTransfer.files[0];
    if (file) handleRestoreFile(file);
  });

  fileInput?.addEventListener("change", (e) => {
    if (e.target.files[0]) handleRestoreFile(e.target.files[0]);
  });

  document.getElementById("btn-do-restore")?.addEventListener("click", handleRestoreDecrypt);
}

function handleRestoreFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      restoreFileData = JSON.parse(reader.result);
      if (!restoreFileData.v || !restoreFileData.salt || !restoreFileData.iv || !restoreFileData.data) {
        throw new Error("Invalid backup format");
      }
      document.getElementById("restore-file-info").style.display = "block";
      document.getElementById("restore-filename").textContent = file.name;
      document.getElementById("btn-do-restore").disabled = false;
    } catch {
      showBackupStatus(document.getElementById("restore-status"), "Invalid backup file format", true);
      restoreFileData = null;
    }
  };
  reader.readAsText(file);
}

async function handleRestoreDecrypt() {
  if (!restoreFileData) return;
  const pw = document.getElementById("restore-password")?.value;
  const statusEl = document.getElementById("restore-status");

  if (!pw) {
    showBackupStatus(statusEl, "Enter the decryption password", true);
    return;
  }

  const btn = document.getElementById("btn-do-restore");
  btn.disabled = true;
  btn.textContent = "DECRYPTING...";
  showBackupStatus(statusEl, "Decrypting backup...", false);

  try {
    const data = await decryptBackup(restoreFileData, pw);

    if (!data.address || !data.publicKeyX || !data.publicKeyY) {
      throw new Error("Backup data is incomplete");
    }

    showBackupStatus(statusEl, "Registering account...", false);

    // Check for duplicate
    const exists = store.accounts.find(a => a.address === data.address);
    if (exists) {
      throw new Error("This account is already imported");
    }

    // Create account entry
    const accountNum = store.accounts.length + 1;
    const account = {
      address: data.address,
      credentialId: data.credentialId || "",
      publicKeyX: data.publicKeyX,
      publicKeyY: data.publicKeyY,
      type: "passkey",
      label: data.label || `Restored ${accountNum}`,
      deployed: true,
      salt: data.salt,
      secretKey: data.secretKey,
      privateKeyPkcs8: data.privateKeyPkcs8,
      createdAt: data.timestamp || new Date().toISOString(),
    };

    store.accounts.push(account);
    store.activeAccountIndex = store.accounts.length - 1;
    await chrome.storage.local.set({ celari_accounts: store.accounts });
    chrome.runtime.sendMessage({ type: "SAVE_ACCOUNT", account });

    // Store sensitive keys in session storage
    if (data.secretKey) await chrome.storage.session.set({ celari_secret: data.secretKey });
    if (data.privateKeyPkcs8) await chrome.storage.session.set({ celari_private_key: data.privateKeyPkcs8 });

    // Register with PXE
    if (data.secretKey && data.salt && data.privateKeyPkcs8) {
      chrome.runtime.sendMessage({
        type: "PXE_REGISTER_ACCOUNT",
        data: {
          publicKeyX: data.publicKeyX,
          publicKeyY: data.publicKeyY,
          secretKey: data.secretKey,
          salt: data.salt,
          privateKeyPkcs8: data.privateKeyPkcs8,
        },
      });
    }

    store.tokens = getTokenList();
    setState({ screen: "dashboard" });
    showToast("Account restored successfully!", "success");
  } catch (e) {
    const msg = e.message?.includes("decrypt") ? "Wrong password or corrupted backup" : sanitizeError(e);
    showBackupStatus(statusEl, msg, true);
    btn.disabled = false;
    btn.textContent = "DECRYPT & IMPORT";
  }
}

// ─── Screen: NFT Detail (Phase 3) ────────────────────

function renderNftList() {
  if (store.nfts.length === 0) {
    return `<div style="text-align:center;padding:32px 16px;color:var(--text-dim)">
      <div style="font-size:24px;margin-bottom:8px;opacity:0.3">&#9671;</div>
      <p style="font-size:10px;letter-spacing:2px;text-transform:uppercase;margin:0">No NFTs found</p>
      <button id="btn-add-nft-contract" class="btn btn-secondary" style="margin-top:12px;padding:8px 16px;font-size:8px">ADD NFT CONTRACT</button>
    </div>`;
  }
  return store.nfts.map(nft => `
    <div class="token-item nft-item" data-contract="${escapeHtml(nft.contractAddress)}" data-token-id="${escapeHtml(nft.tokenId)}" style="cursor:pointer">
      <div class="token-icon" style="border-color:#9A7B5B">
        <span style="transform:rotate(-45deg);color:#9A7B5B;font-family:Poiret One,cursive;font-size:10px">NFT</span>
      </div>
      <div class="token-info">
        <div class="token-name">${escapeHtml(nft.contractSymbol || "NFT")} #${escapeHtml(nft.tokenId)}</div>
        <div class="token-symbol">${escapeHtml(nft.contractName || "Unknown")}${nft.isPrivate ? ' <span style="color:var(--green);font-size:7px">SHIELDED</span>' : ''}</div>
      </div>
      <div style="font-size:8px;color:var(--text-faint);font-family:IBM Plex Mono,monospace">
        ${nft.isPrivate ? 'Private' : 'Public'}
      </div>
    </div>`).join("") + `
    <div style="padding:8px 0;text-align:center">
      <button id="btn-add-nft-contract" style="background:none;border:1px dashed var(--border);color:var(--text-faint);cursor:pointer;padding:6px 12px;font-family:IBM Plex Mono,monospace;font-size:8px;letter-spacing:1px">+ ADD NFT CONTRACT</button>
    </div>`;
}

function bindNftItems() {
  document.querySelectorAll(".nft-item").forEach(item => {
    item.addEventListener("click", () => {
      store.nftDetail = {
        contractAddress: item.dataset.contract,
        tokenId: item.dataset.tokenId,
      };
      setState({ screen: "nft-detail" });
    });
  });
  document.getElementById("btn-add-nft-contract")?.addEventListener("click", () => setState({ screen: "add-nft-contract" }));
}

function renderNftDetail() {
  const nft = store.nfts.find(n =>
    n.contractAddress === store.nftDetail?.contractAddress && n.tokenId === store.nftDetail?.tokenId
  );
  if (!nft) {
    return `${renderSubHeader("NFT Detail", "dashboard")}
    <div style="padding:32px 16px;text-align:center;color:var(--text-dim)">NFT not found</div>`;
  }
  return `
    ${renderSubHeader("NFT Detail", "dashboard")}
    <div style="padding:16px">
      <div style="background:var(--bg-card);border:1px solid var(--border);padding:20px;text-align:center;margin-bottom:16px">
        <div style="width:80px;height:80px;margin:0 auto 12px;border:2px solid var(--bronze);transform:rotate(45deg);display:flex;align-items:center;justify-content:center">
          <span style="transform:rotate(-45deg);font-family:Poiret One,cursive;font-size:24px;color:var(--bronze)">NFT</span>
        </div>
        <div style="font-family:Poiret One,cursive;font-size:20px;color:var(--text-warm);letter-spacing:2px">${escapeHtml(nft.contractSymbol)} #${escapeHtml(nft.tokenId)}</div>
        <div style="font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--text-dim);margin-top:4px">${escapeHtml(nft.contractName)}</div>
        <div style="margin-top:8px;font-size:8px;padding:3px 10px;display:inline-block;font-family:IBM Plex Mono,monospace;letter-spacing:2px;
          background:${nft.isPrivate ? 'var(--green-glow)' : 'rgba(200,121,65,0.08)'};
          border:1px solid ${nft.isPrivate ? 'rgba(74,222,128,0.15)' : 'rgba(200,121,65,0.2)'};
          color:${nft.isPrivate ? 'var(--green)' : 'var(--copper)'}">
          ${nft.isPrivate ? 'PRIVATE' : 'PUBLIC'}
        </div>
      </div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Contract</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);padding:10px 12px;margin-bottom:16px;font-family:IBM Plex Mono,monospace;font-size:9px;color:var(--text-dim);word-break:break-all">${escapeHtml(nft.contractAddress)}</div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Transfer</div>
      <div class="form-group">
        <label class="form-label">Recipient Address</label>
        <input type="text" class="form-input" id="nft-transfer-to" placeholder="0x..." autocomplete="off" />
      </div>
      <div class="form-group">
        <label class="form-label">Transfer Type</label>
        <div style="display:flex;gap:6px" id="nft-transfer-type-group">
          <button class="transfer-type-btn active" data-type="private" style="flex:1;padding:8px 4px;border:1px solid rgba(74,222,128,0.3);background:rgba(74,222,128,0.08);color:var(--green);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">PRIVATE</button>
          <button class="transfer-type-btn" data-type="public" style="flex:1;padding:8px 4px;border:1px solid var(--border);background:var(--bg-elevated);color:var(--text-dim);font-family:IBM Plex Mono,monospace;font-size:8px;cursor:pointer;letter-spacing:1px">PUBLIC</button>
        </div>
      </div>
      <button id="btn-nft-transfer" class="btn btn-primary">Transfer NFT</button>
    </div>`;
}

function bindNftDetail() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));

  let nftTransferType = "private";
  document.querySelectorAll("#nft-transfer-type-group .transfer-type-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll("#nft-transfer-type-group .transfer-type-btn").forEach(b => {
        b.classList.remove("active");
        b.style.borderColor = "var(--border)";
        b.style.background = "var(--bg-elevated)";
        b.style.color = "var(--text-dim)";
      });
      btn.classList.add("active");
      nftTransferType = btn.dataset.type;
      if (nftTransferType === "private") {
        btn.style.borderColor = "rgba(74,222,128,0.3)";
        btn.style.background = "rgba(74,222,128,0.08)";
        btn.style.color = "var(--green)";
      } else {
        btn.style.borderColor = "rgba(200,121,65,0.3)";
        btn.style.background = "rgba(200,121,65,0.08)";
        btn.style.color = "var(--copper)";
      }
    });
  });

  document.getElementById("btn-nft-transfer")?.addEventListener("click", async () => {
    const to = document.getElementById("nft-transfer-to")?.value?.trim();
    if (!to || !isValidAddress(to)) {
      showToast("Enter a valid address", "error");
      return;
    }

    const btn = document.getElementById("btn-nft-transfer");
    btn.disabled = true;
    btn.textContent = "TRANSFERRING...";

    try {
      const result = await new Promise((resolve, reject) => {
        chrome.runtime.sendMessage({
          type: "PXE_NFT_TRANSFER",
          data: {
            contractAddress: store.nftDetail.contractAddress,
            tokenId: store.nftDetail.tokenId,
            to,
            transferType: nftTransferType,
          },
        }, (res) => {
          if (res?.success && res.txHash) resolve(res);
          else reject(new Error(res?.error || "NFT transfer failed"));
        });
      });

      showToast(`NFT transferred! Block ${result.blockNumber}`, "success");
      fetchNftBalances();
      setState({ screen: "dashboard" });
    } catch (e) {
      showToast(sanitizeError(e), "error");
      btn.disabled = false;
      btn.textContent = "TRANSFER NFT";
    }
  });
}

// ─── Screen: Add NFT Contract (Phase 3) ──────────────

function renderAddNftContract() {
  return `
    ${renderSubHeader("Add NFT Contract", "dashboard")}
    <div style="padding:16px">
      <div class="form-group">
        <label class="form-label">NFT Contract Address</label>
        <input type="text" class="form-input" id="nft-contract-address" placeholder="0x..." autocomplete="off" />
      </div>
      <div class="form-group">
        <label class="form-label">Name</label>
        <input type="text" class="form-input" id="nft-contract-name" placeholder="e.g. Aztec Punks" autocomplete="off" maxlength="32" />
      </div>
      <div class="form-group">
        <label class="form-label">Symbol</label>
        <input type="text" class="form-input" id="nft-contract-symbol" placeholder="e.g. APUNK" autocomplete="off" maxlength="10" />
      </div>
      <button id="btn-save-nft-contract" class="btn btn-primary" style="margin-bottom:16px">Add NFT Contract</button>

      ${store.customNftContracts.length > 0 ? `
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Tracked NFT Contracts (${store.customNftContracts.length})</div>
      <div style="background:var(--bg-card);border:1px solid var(--border);overflow:hidden">
        ${store.customNftContracts.map(c => `
        <div style="padding:10px 12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border)">
          <div style="flex:1;min-width:0">
            <div style="font-size:11px;color:var(--text-warm)">${escapeHtml(c.name)} (${escapeHtml(c.symbol)})</div>
            <div style="font-size:8px;color:var(--text-dim);font-family:IBM Plex Mono,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escapeHtml(c.address)}</div>
          </div>
          <button class="btn-remove-nft-contract" data-address="${escapeHtml(c.address)}" style="background:none;border:none;color:var(--text-faint);cursor:pointer;font-size:14px;padding:2px 4px;transition:color 0.2s">&times;</button>
        </div>`).join("")}
      </div>` : ''}
    </div>`;
}

function bindAddNftContract() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));

  document.getElementById("btn-save-nft-contract")?.addEventListener("click", () => {
    const address = document.getElementById("nft-contract-address")?.value?.trim();
    const name = document.getElementById("nft-contract-name")?.value?.trim();
    const symbol = document.getElementById("nft-contract-symbol")?.value?.trim().toUpperCase();

    if (!address || !isValidAddress(address)) { showToast("Enter a valid contract address", "error"); return; }
    if (!name) { showToast("Enter a name", "error"); return; }
    if (!symbol) { showToast("Enter a symbol", "error"); return; }

    if (store.customNftContracts.find(c => c.address.toLowerCase() === address.toLowerCase())) {
      showToast("Contract already added", "error");
      return;
    }

    store.customNftContracts.push({ address, name, symbol });
    chrome.storage.local.set({ celari_custom_nft_contracts: store.customNftContracts });
    showToast(`${symbol} NFT contract added`, "success");
    fetchNftBalances();
    setState({ screen: "dashboard" });
  });

  document.querySelectorAll(".btn-remove-nft-contract").forEach(btn => {
    btn.addEventListener("click", () => {
      const addr = btn.dataset.address;
      store.customNftContracts = store.customNftContracts.filter(c => c.address !== addr);
      chrome.storage.local.set({ celari_custom_nft_contracts: store.customNftContracts });
      store.nfts = store.nfts.filter(n => n.contractAddress !== addr);
      render();
      showToast("Contract removed", "success");
    });
  });
}

async function fetchNftBalances() {
  const account = getActiveAccount();
  if (!account?.deployed || !account?.address || store.customNftContracts.length === 0) return;

  try {
    const res = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({
        type: "PXE_NFT_BALANCES",
        data: { address: account.address, nftContracts: store.customNftContracts },
      }, (r) => {
        if (r?.success) resolve(r);
        else reject(new Error(r?.error || "NFT query failed"));
      });
    });
    if (Array.isArray(res.nfts)) {
      store.nfts = res.nfts;
    }
  } catch (e) {
    console.warn("NFT balance fetch:", e.message);
  }
}

// ─── Screen: WalletConnect (Phase 4) ──────────────────

function renderWalletConnect() {
  return `
    ${renderSubHeader("WalletConnect", "dashboard")}
    <div style="padding:16px">
      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:12px">New Connection</div>

      <div class="form-group">
        <label class="form-label">WalletConnect URI</label>
        <input type="text" class="form-input" id="wc-uri" placeholder="wc:..." autocomplete="off" style="font-size:10px" />
      </div>
      <button id="btn-wc-pair" class="btn btn-primary" style="margin-bottom:20px">Connect</button>

      <div id="wc-pair-status" style="display:none;padding:10px;margin-bottom:14px;font-family:IBM Plex Mono,monospace;font-size:9px"></div>

      <div style="font-family:IBM Plex Mono,monospace;font-size:8px;color:var(--text-faint);text-transform:uppercase;letter-spacing:4px;margin-bottom:8px">Active Sessions (${store.wcSessions.length})</div>
      ${store.wcSessions.length === 0
        ? `<div style="text-align:center;padding:20px;color:var(--text-dim);font-size:10px">No active sessions</div>`
        : `<div style="background:var(--bg-card);border:1px solid var(--border);overflow:hidden">
          ${store.wcSessions.map(s => `
          <div style="padding:12px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border)">
            <div style="flex:1;min-width:0">
              <div style="font-size:11px;color:var(--text-warm)">${escapeHtml(s.peerName || "Unknown dApp")}</div>
              <div style="font-size:8px;color:var(--text-dim);font-family:IBM Plex Mono,monospace">${escapeHtml(s.peerUrl || "")}</div>
            </div>
            <button class="btn-wc-disconnect" data-topic="${escapeHtml(s.topic)}" style="background:none;border:1px solid rgba(239,68,68,0.3);color:var(--red);cursor:pointer;padding:4px 8px;font-family:IBM Plex Mono,monospace;font-size:7px;letter-spacing:1px">DISCONNECT</button>
          </div>`).join("")}
        </div>`}
    </div>`;
}

function bindWalletConnect() {
  document.getElementById("btn-back")?.addEventListener("click", () => setState({ screen: "dashboard" }));

  document.getElementById("btn-wc-pair")?.addEventListener("click", async () => {
    const uri = document.getElementById("wc-uri")?.value?.trim();
    const statusEl = document.getElementById("wc-pair-status");
    if (!uri || !uri.startsWith("wc:")) {
      showBackupStatus(statusEl, "Enter a valid WalletConnect URI (wc:...)", true);
      return;
    }

    const btn = document.getElementById("btn-wc-pair");
    btn.disabled = true;
    btn.textContent = "CONNECTING...";
    showBackupStatus(statusEl, "Pairing with dApp...", false);

    try {
      const result = await new Promise((resolve, reject) => {
        chrome.runtime.sendMessage({ type: "PXE_WC_PAIR", data: { uri } }, (res) => {
          if (res?.success) resolve(res);
          else reject(new Error(res?.error || "Pairing failed"));
        });
      });
      showBackupStatus(statusEl, "Connected!", false);
      showToast("WalletConnect paired", "success");
      refreshWcSessions();
    } catch (e) {
      showBackupStatus(statusEl, sanitizeError(e), true);
    } finally {
      btn.disabled = false;
      btn.textContent = "CONNECT";
    }
  });

  document.querySelectorAll(".btn-wc-disconnect").forEach(btn => {
    btn.addEventListener("click", async () => {
      const topic = btn.dataset.topic;
      try {
        await new Promise((resolve, reject) => {
          chrome.runtime.sendMessage({ type: "PXE_WC_DISCONNECT", data: { topic } }, (res) => {
            if (res?.success) resolve(res);
            else reject(new Error(res?.error || "Disconnect failed"));
          });
        });
        showToast("Session disconnected", "success");
        refreshWcSessions();
      } catch (e) {
        showToast(sanitizeError(e), "error");
      }
    });
  });
}

async function refreshWcSessions() {
  try {
    const res = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({ type: "PXE_WC_SESSIONS" }, (r) => {
        if (r?.success) resolve(r);
        else reject(new Error(r?.error || "Failed to fetch sessions"));
      });
    });
    store.wcSessions = res.sessions || [];
    render();
  } catch {}
}

function renderWcApprove() {
  const proposal = store.wcProposal;
  if (!proposal) return renderLoading();

  return `
    <div class="onboarding" style="padding:28px 20px;gap:16px">
      <div style="width:48px;height:48px;background:var(--burgundy);transform:rotate(45deg);display:flex;align-items:center;justify-content:center;margin-bottom:4px">
        <span style="transform:rotate(-45deg);font-size:18px;color:var(--copper)">WC</span>
      </div>
      <h2 style="font-family:Poiret One,serif;font-size:18px;letter-spacing:2px;margin:0">SESSION REQUEST</h2>
      <p style="font-size:10px;letter-spacing:2px;color:var(--text-dim);text-transform:uppercase;margin:0">A dApp wants to connect</p>

      <div style="width:100%;background:var(--bg-card);border:1px solid var(--border);padding:16px;margin:8px 0">
        <div style="display:flex;justify-content:space-between;margin-bottom:10px">
          <span style="font-size:10px;color:var(--text-dim);letter-spacing:1px">DAPP</span>
          <span style="font-size:11px;color:var(--text-warm);font-family:IBM Plex Mono,monospace">${escapeHtml(proposal.peerName || "Unknown")}</span>
        </div>
        <div style="display:flex;justify-content:space-between">
          <span style="font-size:10px;color:var(--text-dim);letter-spacing:1px">URL</span>
          <span style="font-size:11px;color:var(--copper);font-family:IBM Plex Mono,monospace">${escapeHtml(proposal.peerUrl || "")}</span>
        </div>
      </div>

      <div style="display:flex;gap:12px;width:100%;margin-top:8px">
        <button id="btn-wc-reject" class="btn btn-secondary" style="flex:1">Reject</button>
        <button id="btn-wc-approve" class="btn btn-primary" style="flex:1">Approve</button>
      </div>
    </div>`;
}

function bindWcApprove() {
  document.getElementById("btn-wc-approve")?.addEventListener("click", async () => {
    try {
      await new Promise((resolve, reject) => {
        chrome.runtime.sendMessage({ type: "PXE_WC_APPROVE", data: { proposalId: store.wcProposal?.id } }, (res) => {
          if (res?.success) resolve(res);
          else reject(new Error(res?.error || "Approve failed"));
        });
      });
      store.wcProposal = null;
      showToast("Session approved", "success");
      setState({ screen: "dashboard" });
    } catch (e) {
      showToast(sanitizeError(e), "error");
    }
  });

  document.getElementById("btn-wc-reject")?.addEventListener("click", async () => {
    try {
      await new Promise((resolve, reject) => {
        chrome.runtime.sendMessage({ type: "PXE_WC_REJECT", data: { proposalId: store.wcProposal?.id } }, (res) => {
          if (res?.success) resolve(res);
          else reject(new Error(res?.error || "Reject failed"));
        });
      });
    } catch {}
    store.wcProposal = null;
    setState({ screen: "dashboard" });
  });
}

// ─── WalletConnect Message Listener ───────────────────

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === "WC_SESSION_PROPOSAL") {
    store.wcProposal = message.proposal;
    setState({ screen: "wc-approve" });
  }
  if (message.type === "WC_SESSION_REQUEST") {
    // For now, auto-handle requests in offscreen — just show a toast
    showToast("dApp request processed", "success");
  }
});

// ─── Boot ─────────────────────────────────────────────

document.addEventListener("DOMContentLoaded", init);
