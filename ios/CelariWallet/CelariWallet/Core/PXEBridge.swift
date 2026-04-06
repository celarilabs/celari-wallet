import WebKit
import SwiftUI
import os.log

private let pxeLog = Logger(subsystem: "com.celari.wallet", category: "PXEBridge")

// MARK: - PXE Bridge (WKWebView ↔ Swift async bridge)

@Observable
class PXEBridge: NSObject {
    var isReady: Bool = false
    var error: String?
    weak var store: WalletStore?

    let messageBus = PXEMessageBus()
    private var _nativeProver: PXENativeProver?
    private var nativeProver: PXENativeProver {
        if _nativeProver == nil { _nativeProver = PXENativeProver(messageBus: messageBus) }
        return _nativeProver!
    }
    private var webView: WKWebView?
    private var storageData: [String: Any] = [:]

    override init() {
        super.init()
    }

    // MARK: - Setup

    @MainActor
    func setupWebView() {
        // Idempotent: only create the WebView once
        guard webView == nil else {
            pxeLog.notice("[PXEBridge] setupWebView() skipped — already created")
            return
        }
        pxeLog.notice("[PXEBridge] setupWebView() creating WKWebView...")

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CelariSchemeHandler(), forURLScheme: "celari")

        let controller = WKUserContentController()
        controller.add(self, name: "pxeBridge")
        controller.add(self, name: "pxeStorage")
        controller.add(self, name: "pxeEvent")
        controller.add(self, name: "nativeProver")

        // Inject console.log capture so JS logs are visible in Swift
        controller.add(self, name: "jsConsole")
        let consoleOverride = """
        (function() {
            var origLog = console.log, origErr = console.error, origWarn = console.warn;
            function send(level, args) {
                try {
                    var msg = Array.prototype.slice.call(args).map(function(a) {
                        return typeof a === 'object' ? JSON.stringify(a) : String(a);
                    }).join(' ');
                    window.webkit.messageHandlers.jsConsole.postMessage(JSON.stringify({level: level, msg: msg}));
                } catch(e) {}
            }
            console.log = function() { send('log', arguments); origLog.apply(console, arguments); };
            console.error = function() { send('error', arguments); origErr.apply(console, arguments); };
            console.warn = function() { send('warn', arguments); origWarn.apply(console, arguments); };
            window.addEventListener('error', function(e) {
                send('error', ['[JS Error] ' + e.message + ' at ' + e.filename + ':' + e.lineno]);
            });
            window.addEventListener('unhandledrejection', function(e) {
                send('error', ['[Unhandled Promise] ' + (e.reason && e.reason.message || e.reason || 'unknown')]);
            });
        })();
        """
        let consoleScript = WKUserScript(source: consoleOverride, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(consoleScript)

        // Inject native prover bridge (JS → Swift → Swoirenberg)
        let nativeProverShim = """
        (function() {
            var _npCallbacks = {};
            var _npId = 0;

            window._nativeProverCallback = function(callbackId, resultJson) {
                var cb = _npCallbacks[callbackId];
                if (cb) {
                    delete _npCallbacks[callbackId];
                    try {
                        var result = JSON.parse(resultJson);
                        if (result.error) cb.reject(new Error(result.error));
                        else cb.resolve(result);
                    } catch(e) { cb.reject(e); }
                }
            };

            function callNative(action, params) {
                return new Promise(function(resolve, reject) {
                    var cbId = 'np_' + (++_npId);
                    _npCallbacks[cbId] = { resolve: resolve, reject: reject };
                    var msg = JSON.stringify(Object.assign({ action: action, callbackId: cbId }, params || {}));
                    window.webkit.messageHandlers.nativeProver.postMessage(msg);
                });
            }

            window.nativeProver = {
                available: false, // Decision gate: Week 4 — set to true after Swoirenberg stabilizes
                callNative: callNative,
                setupSrs: function(opts) {
                    return callNative('setup_srs', opts || {});
                },
                setupSrsFromBytecode: function(bytecodeBase64) {
                    return callNative('setup_srs_from_bytecode', { bytecode: bytecodeBase64 });
                },
                execute: function(bytecodeBase64, witnessMap) {
                    return callNative('execute', { bytecode: bytecodeBase64, witnessMap: witnessMap });
                },
                prove: function(bytecodeBase64, witnessMap, proofType) {
                    return callNative('prove', { bytecode: bytecodeBase64, witnessMap: witnessMap, proofType: proofType || 'ultra_honk' });
                },
                verify: function(proofHex, vkeyHex, proofType) {
                    return callNative('verify', { proof: proofHex, vkey: vkeyHex, proofType: proofType || 'ultra_honk' });
                },
                getVerificationKey: function(bytecodeBase64, proofType) {
                    return callNative('get_vkey', { bytecode: bytecodeBase64, proofType: proofType || 'ultra_honk' });
                },
                // Chonk/IVC pipeline
                setupForChonk: function(opts) {
                    return callNative('setup_for_chonk', opts || {});
                },
                setupGrumpkinSrs: function(opts) {
                    return callNative('setup_grumpkin_srs', opts || {});
                },
                chonkStart: function(numCircuits) {
                    return callNative('chonk_start', { numCircuits: numCircuits });
                },
                chonkLoad: function(name, bytecodeB64, vkeyB64) {
                    return callNative('chonk_load', { name: name, bytecode: bytecodeB64, vkey: vkeyB64 });
                },
                chonkAccumulate: function(witnessB64) {
                    return callNative('chonk_accumulate', { witness: witnessB64 });
                },
                chonkProve: function() {
                    return callNative('chonk_prove', {});
                },
                chonkVerify: function(proofB64, vkeyB64) {
                    return callNative('chonk_verify', { proof: proofB64, vkey: vkeyB64 });
                },
                chonkComputeVk: function(bytecodeB64) {
                    return callNative('chonk_compute_vk', { bytecode: bytecodeB64 });
                },
                chonkDestroy: function() {
                    return callNative('chonk_destroy', {});
                }
            };

            console.log('[NativeProver] JS bridge injected — window.nativeProver.available = true');
        })();
        """
        let nativeProverScript = WKUserScript(source: nativeProverShim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(nativeProverScript)

        // Inject Chrome API shim before page loads (defines process, global, chrome.*)
        if let shimURL = Bundle.main.url(forResource: "pxe-bridge-shim", withExtension: "js"),
           let shimCode = try? String(contentsOf: shimURL) {
            let shimScript = WKUserScript(source: shimCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            controller.addUserScript(shimScript)
        }

        // Inject full Buffer polyfill (required by Aztec SDK's msgpackr serializer)
        if let bufURL = Bundle.main.url(forResource: "buffer-polyfill", withExtension: "js"),
           let bufCode = try? String(contentsOf: bufURL) {
            let bufScript = WKUserScript(source: bufCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            controller.addUserScript(bufScript)
        }

        config.userContentController = controller

        // Use a 1×1 frame and attach to the key window so iOS doesn't freeze the
        // WebContent process (zero-frame/detached WKWebViews get suspended).
        let wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.alpha = 0.01 // effectively invisible but keeps process alive
        self.webView = wv
        messageBus.setWebView(wv)

        // Attach to key window so the WebContent process stays active
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            window.addSubview(wv)
        }

        // Load PXE bridge HTML via custom scheme
        wv.load(URLRequest(url: URL(string: "celari://pxe-bridge.html")!))
    }

    // MARK: - Send Message to JavaScript

    func sendMessage(_ type: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        try await messageBus.sendMessage(type, data: data)
    }

    // MARK: - Evaluate JavaScript

    @MainActor
    func evaluateJS(_ jsCode: String) async throws -> Any? {
        try await messageBus.evaluateJS(jsCode)
    }

    // MARK: - Typed PXE Methods

    func initPXE(nodeUrl: String) async throws -> [String: Any] {
        try await sendMessage("PXE_INIT", data: ["nodeUrl": nodeUrl])
    }

    func checkStatus() async throws -> [String: Any] {
        try await sendMessage("PXE_STATUS")
    }

    func generateKeys() async throws -> [String: Any] {
        try await sendMessage("PXE_GENERATE_KEYS")
    }

    func computeAddress(pubKeyX: String, pubKeyY: String, pkcs8: String) async throws -> [String: Any] {
        try await sendMessage("PXE_COMPUTE_ADDRESS", data: [
            "data": ["publicKeyX": pubKeyX, "publicKeyY": pubKeyY, "privateKeyPkcs8": pkcs8]
        ])
    }

    func deployAccount(pubKeyX: String, pubKeyY: String, pkcs8: String, secretKey: String? = nil, salt: String? = nil, claimData: [String: String]? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["publicKeyX": pubKeyX, "publicKeyY": pubKeyY, "privateKeyPkcs8": pkcs8]
        if let sk = secretKey { payload["secretKey"] = sk }
        if let s = salt { payload["salt"] = s }
        if let cd = claimData {
            for (k, v) in cd { payload[k] = v }
        }
        return try await sendMessage("PXE_DEPLOY_ACCOUNT", data: ["data": payload])
    }

    func registerAccount(data: [String: String]) async throws -> [String: Any] {
        try await sendMessage("PXE_REGISTER_ACCOUNT", data: ["data": data])
    }

    func transfer(to: String, amount: String, tokenAddress: String, transferType: String) async throws -> [String: Any] {
        try await sendMessage("PXE_TRANSFER", data: [
            "data": ["to": to, "amount": amount, "tokenAddress": tokenAddress, "transferType": transferType]
        ])
    }

    func getBalances(address: String, tokens: [[String: String]]) async throws -> [String: Any] {
        try await sendMessage("PXE_BALANCES", data: ["data": ["address": address, "tokens": tokens]])
    }

    func faucet(address: String) async throws -> [String: Any] {
        try await sendMessage("PXE_FAUCET", data: ["data": ["address": address]])
    }

    func syncStatus() async throws -> [String: Any] {
        try await sendMessage("PXE_SYNC_STATUS")
    }

    func setActiveAccount(address: String) async throws -> [String: Any] {
        try await sendMessage("PXE_SET_ACTIVE_ACCOUNT", data: ["data": ["address": address]])
    }

    func deleteAccount(address: String) async throws -> [String: Any] {
        try await sendMessage("PXE_DELETE_ACCOUNT", data: ["data": ["address": address]])
    }

    func getNftBalances(contracts: [[String: String]]) async throws -> [String: Any] {
        try await sendMessage("PXE_NFT_BALANCES", data: ["data": ["contracts": contracts]])
    }

    func transferNft(contractAddress: String, tokenId: String, to: String, mode: String) async throws -> [String: Any] {
        try await sendMessage("PXE_NFT_TRANSFER", data: [
            "data": ["contractAddress": contractAddress, "tokenId": tokenId, "to": to, "mode": mode, "nonce": "0"]
        ])
    }

    func wcInit() async throws -> [String: Any] {
        try await sendMessage("PXE_WC_INIT")
    }

    func wcPair(uri: String) async throws -> [String: Any] {
        try await sendMessage("PXE_WC_PAIR", data: ["data": ["uri": uri]])
    }

    func wcApprove(id: Int, namespaces: [String: Any]) async throws -> [String: Any] {
        try await sendMessage("PXE_WC_APPROVE", data: ["data": ["id": id, "namespaces": namespaces]])
    }

    func wcReject(id: Int) async throws -> [String: Any] {
        try await sendMessage("PXE_WC_REJECT", data: ["data": ["id": id]])
    }

    func wcDisconnect(topic: String) async throws -> [String: Any] {
        try await sendMessage("PXE_WC_DISCONNECT", data: ["data": ["topic": topic]])
    }

    func wcSessions() async throws -> [String: Any] {
        try await sendMessage("PXE_WC_SESSIONS")
    }

    // MARK: - AIP-20 Balance Queries

    func getPrivateBalance(tokenAddress: String, ownerAddress: String) async throws -> String {
        let result = try await sendMessage("PXE_PRIVATE_BALANCE", data: [
            "data": ["tokenAddress": tokenAddress, "ownerAddress": ownerAddress]
        ])
        return result["balance"] as? String ?? "0"
    }

    func getPublicBalance(tokenAddress: String, ownerAddress: String) async throws -> String {
        let result = try await sendMessage("PXE_PUBLIC_BALANCE", data: [
            "data": ["tokenAddress": tokenAddress, "ownerAddress": ownerAddress]
        ])
        return result["balance"] as? String ?? "0"
    }

    // MARK: - Fee Juice

    func getFeeJuiceBalance() async throws -> String {
        let result = try await sendMessage("PXE_FEE_JUICE_BALANCE")
        guard let balance = result["balance"] as? String else {
            throw PXEError.jsError("getFeeJuiceBalance returned no balance")
        }
        return balance
    }

    // MARK: - Guardian Recovery

    func setupGuardians(guardianHash0: String, guardianHash1: String, guardianHash2: String, threshold: Int, cidPart1: String, cidPart2: String) async throws -> [String: Any] {
        try await sendMessage("PXE_SETUP_GUARDIANS", data: ["data": [
            "guardianHash0": guardianHash0,
            "guardianHash1": guardianHash1,
            "guardianHash2": guardianHash2,
            "threshold": threshold,
            "cidPart1": cidPart1,
            "cidPart2": cidPart2,
        ]])
    }

    func initiateRecovery(newKeyX: String, newKeyY: String, guardianKeyA: String, guardianKeyB: String) async throws -> [String: Any] {
        try await sendMessage("PXE_INITIATE_RECOVERY", data: ["data": [
            "newKeyX": newKeyX,
            "newKeyY": newKeyY,
            "guardianKeyA": guardianKeyA,
            "guardianKeyB": guardianKeyB,
        ]])
    }

    func executeRecovery(newKeyX: String, newKeyY: String) async throws -> [String: Any] {
        try await sendMessage("PXE_EXECUTE_RECOVERY", data: ["data": [
            "newKeyX": newKeyX,
            "newKeyY": newKeyY,
        ]])
    }

    func cancelRecovery() async throws -> [String: Any] {
        try await sendMessage("PXE_CANCEL_RECOVERY")
    }

    func isGuardianConfigured() async throws -> Bool {
        let result = try await sendMessage("PXE_IS_GUARDIAN_CONFIGURED")
        return result["configured"] as? Bool ?? false
    }

    func getRecoveryCid() async throws -> (String, String) {
        let result = try await sendMessage("PXE_GET_RECOVERY_CID")
        let part1 = result["cidPart1"] as? String ?? "0"
        let part2 = result["cidPart2"] as? String ?? "0"
        return (part1, part2)
    }

    func checkRecoveryStatus() async throws -> [String: Any] {
        return try await sendMessage("PXE_IS_RECOVERY_ACTIVE")
    }

    // MARK: - DEX

    func getSwapQuote(tokenIn: String, tokenOut: String, amountIn: String, slippage: Double = 0.01) async throws -> [String: Any] {
        return try await sendMessage("PXE_DEX_GET_QUOTE", data: ["data": [
            "tokenIn": tokenIn,
            "tokenOut": tokenOut,
            "amountIn": amountIn,
            "slippage": slippage
        ]])
    }

    func executeSwap(tokenIn: String, tokenOut: String, amountIn: String, amountOutMin: String) async throws -> [String: Any] {
        return try await sendMessage("PXE_DEX_EXECUTE_SWAP", data: ["data": [
            "tokenIn": tokenIn,
            "tokenOut": tokenOut,
            "amountIn": amountIn,
            "amountOutMin": amountOutMin
        ]])
    }

    func getSupportedPairs() async throws -> [String: Any] {
        return try await sendMessage("PXE_DEX_SUPPORTED_PAIRS")
    }

    // MARK: - Snapshot Persistence

    func saveSnapshot() async throws -> String {
        let result = try await sendMessage("PXE_SNAPSHOT_SAVE")
        guard let snapshot = result["snapshot"] as? String else {
            throw PXEError.jsError("PXE_SNAPSHOT_SAVE returned no snapshot data")
        }
        return snapshot
    }

    @MainActor
    func restoreSnapshot(json: String) async throws {
        guard let webView else { throw PXEError.notReady }

        // Use callAsyncJavaScript with structured arguments to avoid
        // evaluateJavaScript string size limits (~56MB snapshot would overflow).
        let jsCode = """
        return new Promise((resolve, reject) => {
            const handler = window._messageHandlers && window._messageHandlers[0];
            if (!handler) { reject(new Error('No JS message handler registered')); return; }
            handler(
                { type: 'PXE_SNAPSHOT_RESTORE', data: { snapshot: snapshotJson } },
                { id: 'celari-ios' },
                (response) => {
                    if (response && response.error) reject(new Error(response.error));
                    else resolve(response || {});
                }
            );
        });
        """

        do {
            _ = try await webView.callAsyncJavaScript(
                jsCode,
                arguments: ["snapshotJson": json],
                contentWorld: .page
            )
        } catch {
            throw PXEError.jsError("Snapshot restore failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - WKScriptMessageHandler

extension PXEBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch message.name {
        case "pxeBridge":
            // JS handler readiness signal (ESM modules load after didFinish)
            if json["_type"] as? String == "JS_HANDLER_READY" {
                Task { @MainActor in
                    self.isReady = true
                    pxeLog.notice("[PXEBridge] JS message handler ready")
                }
                return
            }
            // Response from JS to a pending Swift call
            if let messageId = json["_messageId"] as? String {
                if let error = json["error"] as? String {
                    messageBus.resumeContinuation(messageId, with: .failure(PXEError.jsError(error)))
                } else {
                    messageBus.resumeContinuation(messageId, with: .success(json))
                }
            }

        case "pxeStorage":
            // chrome.storage shim calls
            handleStorageRequest(json)

        case "pxeEvent":
            // WalletConnect events from JS
            handleEvent(json)

        case "nativeProver":
            nativeProver.handleRequest(json)

        case "jsConsole":
            // JavaScript console output
            let level = json["level"] as? String ?? "log"
            let msg = json["msg"] as? String ?? ""
            pxeLog.notice("[PXE-JS:\(level, privacy: .public)] \(msg, privacy: .public)")

            // Forward PXE-related logs to in-app log panel
            if msg.contains("[PXE") || msg.contains("[AuthWit") || msg.contains("[NativeProver") || level == "error" || level == "warn" {
                Task { @MainActor in
                    self.store?.appendPXELog(level: level, message: msg)
                }
            }

        default:
            break
        }
    }

    private func handleStorageRequest(_ json: [String: Any]) {
        let action = json["action"] as? String ?? ""
        let callbackId = json["callbackId"] as? String ?? ""

        switch action {
        case "get":
            if let keys = json["keys"] as? [String] {
                var result: [String: Any] = [:]
                for key in keys {
                    if let val = UserDefaults.standard.object(forKey: key) {
                        result[key] = val
                    }
                }
                deliverStorageCallback(callbackId, result: result)
            }
        case "set":
            if let data = json["data"] as? [String: Any] {
                for (key, val) in data {
                    UserDefaults.standard.set(val, forKey: key)
                }
                deliverStorageCallback(callbackId, result: [:])
            }
        case "remove":
            if let keys = json["keys"] as? [String] {
                for key in keys {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                deliverStorageCallback(callbackId, result: [:])
            }
        default:
            pxeLog.warning("[PXEBridge] Unknown storage action: \(action, privacy: .public)")
            deliverStorageCallback(callbackId, result: [:])
        }
    }

    private func deliverStorageCallback(_ callbackId: String, result: [String: Any]) {
        guard let webView else { return }
        if let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            Task { @MainActor in
                try? await webView.callAsyncJavaScript(
                    "window._deliverStorageCallback(cbId, resultJson)",
                    arguments: ["cbId": callbackId, "resultJson": jsonStr],
                    contentWorld: .page
                )
            }
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "WC_SESSION_PROPOSAL":
                if let peerName = json["peerName"] as? String,
                   let peerUrl = json["peerUrl"] as? String,
                   let id = json["id"] as? Int {
                    store?.wcProposal = WCProposal(id: id, peerName: peerName, peerUrl: peerUrl)
                    store?.screen = .wcApprove
                }
            case "WC_SESSION_REQUEST":
                store?.showToast("dApp request processed")
            case "PROGRESS":
                let msg = json["message"] as? String
                store?.progressMessage = msg
                pxeLog.notice("[PXEBridge] Progress: \(msg ?? "nil", privacy: .public)")
                if let msg = msg {
                    store?.appendPXELog(level: "info", message: msg)
                }
            default:
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension PXEBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Note: isReady is set by JS_HANDLER_READY signal (ESM modules execute after didFinish)
        pxeLog.notice("[PXEBridge] WebView navigation finished (waiting for JS handler)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error.localizedDescription
        pxeLog.error("[PXEBridge] WebView failed: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - Errors

enum PXEError: LocalizedError {
    case notReady
    case timeout
    case jsError(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "PXE bridge not ready"
        case .timeout: return "PXE operation timed out"
        case .jsError(let msg): return msg
        }
    }
}
