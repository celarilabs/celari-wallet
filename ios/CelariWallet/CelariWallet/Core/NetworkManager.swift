import Foundation

actor NetworkManager {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - JSON-RPC

    func jsonRPC(url: String, method: String, params: [Any] = [], timeout: TimeInterval = 12) async throws -> [String: Any] {
        guard let rpcUrl = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: rpcUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidJSON
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "RPC error"
            throw NetworkError.rpcError(message)
        }

        return json
    }

    // MARK: - Check Connection (node_getNodeInfo)

    func checkConnection(nodeUrl: String) async -> ConnectionResult {
        // Try JSON-RPC first
        do {
            let result = try await jsonRPC(url: nodeUrl, method: "node_getNodeInfo")
            if let info = result["result"] as? [String: Any] {
                return ConnectionResult(
                    connected: true,
                    nodeInfo: NodeInfo(
                        nodeVersion: info["nodeVersion"] as? String ?? "unknown",
                        l1ChainId: info["l1ChainId"] as? Int,
                        protocolVersion: info["protocolVersion"] as? Int ?? info["rollupVersion"] as? Int
                    )
                )
            }
        } catch {
            // Fallback: REST API (sandbox)
        }

        // REST fallback
        do {
            let cleanUrl = nodeUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let restUrl = URL(string: "\(cleanUrl)/api/node-info") else {
                return ConnectionResult(connected: false, nodeInfo: nil)
            }

            var request = URLRequest(url: restUrl)
            request.timeoutInterval = 5

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return ConnectionResult(connected: false, nodeInfo: nil)
            }

            if let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ConnectionResult(
                    connected: true,
                    nodeInfo: NodeInfo(
                        nodeVersion: info["nodeVersion"] as? String ?? info["sandboxVersion"] as? String ?? "unknown",
                        l1ChainId: info["l1ChainId"] as? Int,
                        protocolVersion: info["protocolVersion"] as? Int
                    )
                )
            }
        } catch {}

        return ConnectionResult(connected: false, nodeInfo: nil)
    }

    // MARK: - Verify Account (node_getContract)

    func verifyAccount(nodeUrl: String, address: String) async -> Bool {
        do {
            let result = try await jsonRPC(url: nodeUrl, method: "node_getContract", params: [address], timeout: 10)
            return result["result"] != nil
        } catch {
            return false
        }
    }

    // MARK: - Get Block Number

    func getBlockNumber(nodeUrl: String) async -> Int? {
        do {
            let result = try await jsonRPC(url: nodeUrl, method: "node_getBlockNumber")
            if let block = result["result"] as? Int {
                return block
            }
        } catch {}
        return nil
    }

    // MARK: - Test RPC Connection

    func testRPC(url: String) async -> RPCTestResult {
        let start = Date()
        do {
            let result = try await jsonRPC(url: url, method: "node_getNodeInfo", timeout: 10)
            let latency = Int(Date().timeIntervalSince(start) * 1000)

            if let info = result["result"] as? [String: Any],
               let version = info["nodeVersion"] as? String {
                return RPCTestResult(
                    success: true,
                    message: "Connected (\(latency)ms) · v\(String(version.prefix(8)))",
                    latency: latency
                )
            }
            return RPCTestResult(
                success: true,
                message: "Response OK (\(latency)ms) but no node info",
                latency: latency
            )
        } catch let error as NetworkError {
            return RPCTestResult(success: false, message: error.localizedDescription, latency: nil)
        } catch {
            return RPCTestResult(success: false, message: "Connection failed: \(error.localizedDescription)", latency: nil)
        }
    }

    // MARK: - Deploy Server API

    func fetchBalances(deployServerUrl: String, address: String) async throws -> BalanceResponse {
        guard !deployServerUrl.isEmpty else { throw NetworkError.noDeployServer }

        let url = URL(string: "\(deployServerUrl)/api/balances")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["address": address]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidJSON
        }

        var tokenAddresses: [String: String] = [:]
        if let addrs = json["tokenAddresses"] as? [String: String] {
            tokenAddresses = addrs
        }

        var tokens: [Token] = []
        if let tokenArray = json["tokens"] as? [[String: Any]] {
            tokens = tokenArray.map { t in
                Token(
                    name: t["name"] as? String ?? "",
                    symbol: t["symbol"] as? String ?? "",
                    balance: formatBalance(t["balance"]),
                    value: formatValue(t["value"]),
                    icon: t["icon"] as? String ?? "T",
                    color: t["color"] as? String ?? "#999",
                    isCustom: false
                )
            }
        }

        return BalanceResponse(tokens: tokens, tokenAddresses: tokenAddresses)
    }

    private func formatBalance(_ value: Any?) -> String {
        if let num = value as? Double {
            return num < 0.001 && num > 0 ? String(format: "%.6f", num) : String(format: "%.3f", num)
        }
        if let str = value as? String { return str }
        return "0"
    }

    private func formatValue(_ value: Any?) -> String {
        if let num = value as? Double {
            return String(format: "$%.2f", num)
        }
        if let str = value as? String { return str }
        return "$0.00"
    }
}

// MARK: - Types

struct ConnectionResult {
    var connected: Bool
    var nodeInfo: NodeInfo?
}

struct RPCTestResult {
    var success: Bool
    var message: String
    var latency: Int?
}

struct BalanceResponse {
    var tokens: [Token]
    var tokenAddresses: [String: String]
}

// MARK: - Errors

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case invalidJSON
    case rpcError(String)
    case noDeployServer

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP error \(code)"
        case .invalidJSON: return "Invalid JSON response"
        case .rpcError(let msg): return msg
        case .noDeployServer: return "No deploy server configured"
        }
    }
}
