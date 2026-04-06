import Foundation
import os

private let ipfsLog = Logger(subsystem: "com.celari.wallet", category: "IPFS")

/// Uploads encrypted recovery bundles to IPFS via Pinata.
actor IPFSManager {
    static let shared = IPFSManager()

    private let pinataURL = "https://api.pinata.cloud/pinning/pinJSONToIPFS"

    /// Upload JSON data to IPFS and return the CID.
    func upload(json: [String: Any], apiKey: String) async throws -> String {
        let payload: [String: Any] = [
            "pinataContent": json,
            "pinataMetadata": ["name": "celari-recovery-\(UUID().uuidString.prefix(8))"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: pinataURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            ipfsLog.error("[IPFS] Upload failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
            throw IPFSError.uploadFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let cid = result?["IpfsHash"] as? String else {
            throw IPFSError.noCID
        }
        ipfsLog.notice("[IPFS] Upload OK — CID: \(cid, privacy: .public)")
        return cid
    }

    /// Fetch recovery bundle from IPFS by CID.
    func fetch(cid: String) async throws -> [String: Any] {
        let url = URL(string: "https://gateway.pinata.cloud/ipfs/\(cid)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPFSError.invalidData
        }
        return json
    }

    enum IPFSError: Error, LocalizedError {
        case uploadFailed
        case noCID
        case invalidData

        var errorDescription: String? {
            switch self {
            case .uploadFailed: return "Failed to upload to IPFS"
            case .noCID: return "No CID returned from IPFS"
            case .invalidData: return "Invalid data from IPFS"
            }
        }
    }
}
