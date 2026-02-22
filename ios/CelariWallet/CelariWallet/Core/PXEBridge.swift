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

    private var webView: WKWebView?
    private var pendingCallbacks: [String: CheckedContinuation<[String: Any], Error>] = [:]
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
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let controller = WKUserContentController()
        controller.add(self, name: "pxeBridge")
        controller.add(self, name: "pxeStorage")
        controller.add(self, name: "pxeEvent")

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

        // Attach to key window so the WebContent process stays active
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            window.addSubview(wv)
        }

        // Load PXE bridge HTML
        if let htmlURL = Bundle.main.url(forResource: "pxe-bridge", withExtension: "html") {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    // MARK: - Send Message to JavaScript

    func sendMessage(_ type: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        guard let webView else { throw PXEError.notReady }

        let messageId = "msg_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"

        var message = data
        message["type"] = type
        message["_messageId"] = messageId

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        // ZK proof generation on single-threaded WASM takes ~140s per proof.
        // Faucet first-time setup needs 3 sequential proofs (~15 min total).
        let timeoutSeconds: Int
        switch type {
        case "PXE_FAUCET":
            timeoutSeconds = 1200  // 20 min — up to 3 sequential proofs + block inclusion
        case "PXE_DEPLOY_ACCOUNT", "PXE_TRANSFER", "PXE_NFT_TRANSFER":
            timeoutSeconds = 600   // 10 min — 1 proof + block inclusion
        case "PXE_SNAPSHOT_RESTORE":
            timeoutSeconds = 600   // 10 min — deserialize + recreate PXE/TestWallet
        default:
            timeoutSeconds = 300   // 5 min — non-proving operations
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingCallbacks[messageId] = continuation

            let js = "window._receiveFromSwift('\(jsonString.replacingOccurrences(of: "'", with: "\\'"))')"
            pxeLog.notice("[PXEBridge] evaluateJavaScript for \(type, privacy: .public), msgId: \(messageId, privacy: .public), jsonLen: \(jsonString.count), timeout: \(timeoutSeconds)s")
            Task { @MainActor in
                webView.evaluateJavaScript(js) { result, error in
                    if let error {
                        pxeLog.error("[PXEBridge] evaluateJavaScript ERROR for \(type, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        self.pendingCallbacks.removeValue(forKey: messageId)
                        continuation.resume(throwing: error)
                    } else {
                        pxeLog.notice("[PXEBridge] evaluateJavaScript OK for \(type, privacy: .public)")
                    }
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if let cb = self.pendingCallbacks.removeValue(forKey: messageId) {
                    cb.resume(throwing: PXEError.timeout)
                }
            }
        }
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

    func deployAccount(pubKeyX: String, pubKeyY: String, pkcs8: String) async throws -> [String: Any] {
        try await sendMessage("PXE_DEPLOY_ACCOUNT", data: [
            "data": ["publicKeyX": pubKeyX, "publicKeyY": pubKeyY, "privateKeyPkcs8": pkcs8]
        ])
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
            if let messageId = json["_messageId"] as? String,
               let continuation = pendingCallbacks.removeValue(forKey: messageId) {
                if let error = json["error"] as? String {
                    continuation.resume(throwing: PXEError.jsError(error))
                } else {
                    continuation.resume(returning: json)
                }
            }

        case "pxeStorage":
            // chrome.storage shim calls
            handleStorageRequest(json)

        case "pxeEvent":
            // WalletConnect events from JS
            handleEvent(json)

        case "jsConsole":
            // JavaScript console output
            let level = json["level"] as? String ?? "log"
            let msg = json["msg"] as? String ?? ""
            pxeLog.notice("[PXE-JS:\(level, privacy: .public)] \(msg, privacy: .public)")

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
        default:
            break
        }
    }

    private func deliverStorageCallback(_ callbackId: String, result: [String: Any]) {
        guard let webView else { return }
        if let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            let js = "window._deliverStorageCallback('\(callbackId)', '\(jsonStr.replacingOccurrences(of: "'", with: "\\'"))')"
            Task { @MainActor in
                webView.evaluateJavaScript(js, completionHandler: nil)
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
