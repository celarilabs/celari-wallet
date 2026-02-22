import Foundation
import CryptoKit
import os.log

private let pmLog = Logger(subsystem: "com.celari.wallet", category: "PXEPersistence")

enum PXEPersistenceManager {

    private static let snapshotFile = "pxe_snapshot.enc"
    private static let keychainKey = "pxe_snapshot_aes_key"

    // MARK: - Encryption Key

    private static func getOrCreateKey() throws -> SymmetricKey {
        // Try loading from Keychain
        if let keyData = try? KeychainManager.load(key: keychainKey) {
            return SymmetricKey(data: keyData)
        }
        // Generate and persist new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try KeychainManager.save(key: keychainKey, data: keyData)
        pmLog.notice("[PXEPersistence] AES-256 key generated and saved to Keychain")
        return key
    }

    // MARK: - File Path

    private static func snapshotURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dir.appendingPathComponent(snapshotFile)
    }

    // MARK: - Save Snapshot

    static func save(json: String) async throws {
        guard let plaintext = json.data(using: .utf8) else {
            throw PXEPersistenceError.encodingFailed
        }

        let key = try getOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw PXEPersistenceError.encryptionFailed
        }

        let url = try snapshotURL()
        try combined.write(to: url, options: [.atomic, .completeFileProtection])

        let sizeKB = combined.count / 1024
        pmLog.notice("[PXEPersistence] Snapshot saved — \(sizeKB) KB encrypted to \(url.lastPathComponent)")
    }

    // MARK: - Load Snapshot

    static func load() async throws -> String {
        let url = try snapshotURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PXEPersistenceError.noSnapshot
        }

        let combined = try Data(contentsOf: url)
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: key)

        guard let json = String(data: plaintext, encoding: .utf8) else {
            throw PXEPersistenceError.decodingFailed
        }

        let sizeKB = combined.count / 1024
        pmLog.notice("[PXEPersistence] Snapshot loaded — \(sizeKB) KB decrypted from \(url.lastPathComponent)")
        return json
    }

    // MARK: - Has Snapshot

    static func hasSnapshot() -> Bool {
        guard let url = try? snapshotURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Delete Snapshot

    static func deleteSnapshot() {
        guard let url = try? snapshotURL() else { return }
        try? FileManager.default.removeItem(at: url)
        pmLog.notice("[PXEPersistence] Snapshot deleted")
    }
}

enum PXEPersistenceError: LocalizedError {
    case encodingFailed
    case encryptionFailed
    case noSnapshot
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode snapshot to UTF-8"
        case .encryptionFailed: return "AES-GCM encryption failed"
        case .noSnapshot: return "No snapshot file found"
        case .decodingFailed: return "Failed to decode snapshot from UTF-8"
        }
    }
}
