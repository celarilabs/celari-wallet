import WebKit
import os.log

private let messageBusLog = Logger(subsystem: "com.celari.wallet", category: "PXEMessageBus")

// MARK: - PXEMessageBus Protocol

protocol PXEMessageBusProtocol {
    func sendMessage(_ type: String, data: [String: Any]) async throws -> [String: Any]
    @MainActor func evaluateJS(_ jsCode: String) async throws -> Any?
}

// MARK: - PXEMessageBus

final class PXEMessageBus: PXEMessageBusProtocol {
    private weak var webView: WKWebView?
    private var pendingCallbacks: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private let callbackLock = NSLock()

    // MARK: - WebView Registration

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Thread-safe Continuation Access

    func storeContinuation(_ id: String, _ continuation: CheckedContinuation<[String: Any], Error>) {
        callbackLock.lock()
        pendingCallbacks[id] = continuation
        callbackLock.unlock()
    }

    /// Remove and return the continuation for the given ID, or nil if already consumed.
    /// This ensures each CheckedContinuation is resumed at most once.
    func resumeContinuation(_ id: String, with result: Result<[String: Any], Error>) {
        callbackLock.lock()
        let cb = pendingCallbacks.removeValue(forKey: id)
        callbackLock.unlock()
        switch result {
        case .success(let value):
            cb?.resume(returning: value)
        case .failure(let error):
            cb?.resume(throwing: error)
        }
    }

    /// Remove and return the continuation without resuming (used for timeout / JS-error path
    /// where the caller handles resumption).
    func removeContinuation(_ id: String) -> CheckedContinuation<[String: Any], Error>? {
        callbackLock.lock()
        let cb = pendingCallbacks.removeValue(forKey: id)
        callbackLock.unlock()
        return cb
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
        case "PXE_DEPLOY_ACCOUNT", "PXE_TRANSFER", "PXE_NFT_TRANSFER",
             "PXE_SETUP_GUARDIANS", "PXE_INITIATE_RECOVERY", "PXE_EXECUTE_RECOVERY", "PXE_CANCEL_RECOVERY":
            timeoutSeconds = 600   // 10 min — 1 proof + block inclusion
        case "PXE_SNAPSHOT_RESTORE":
            timeoutSeconds = 600   // 10 min — deserialize + recreate PXE/TestWallet
        default:
            timeoutSeconds = 300   // 5 min — non-proving operations
        }

        return try await withCheckedThrowingContinuation { continuation in
            storeContinuation(messageId, continuation)

            messageBusLog.notice("[PXEMessageBus] callAsyncJavaScript for \(type, privacy: .public), msgId: \(messageId, privacy: .public), jsonLen: \(jsonString.count), timeout: \(timeoutSeconds)s")
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "window._receiveFromSwift(msg)",
                        arguments: ["msg": jsonString],
                        contentWorld: .page
                    )
                    messageBusLog.notice("[PXEMessageBus] callAsyncJavaScript OK for \(type, privacy: .public)")
                } catch {
                    messageBusLog.error("[PXEMessageBus] callAsyncJavaScript ERROR for \(type, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    if let cb = self.removeContinuation(messageId) {
                        cb.resume(throwing: error)
                    }
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if let cb = self.removeContinuation(messageId) {
                    cb.resume(throwing: PXEError.timeout)
                }
            }
        }
    }

    // MARK: - Evaluate JavaScript

    @MainActor
    func evaluateJS(_ jsCode: String) async throws -> Any? {
        guard let webView else { throw PXEError.notReady }
        return try await webView.callAsyncJavaScript(
            jsCode,
            arguments: [:],
            contentWorld: .page
        )
    }
}
