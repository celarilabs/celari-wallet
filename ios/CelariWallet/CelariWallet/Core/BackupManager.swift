import CommonCrypto
import CryptoKit
import Foundation

enum BackupManager {

    // MARK: - Encryption (AES-256-GCM + PBKDF2 — matches popup.js encryptBackup)

    static func encrypt(data: [String: Any], password: String) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .sortedKeys)

        // Generate random salt (16 bytes) and IV (12 bytes) — same as JS
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }

        var iv = Data(count: 12)
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!) }

        // PBKDF2 key derivation: 600K iterations, SHA-256 — matches JS exactly
        let key = try deriveKey(password: password, salt: salt)

        // AES-256-GCM encryption
        let symmetricKey = SymmetricKey(data: key)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealed = try AES.GCM.seal(jsonData, using: symmetricKey, nonce: nonce)

        // Build output format matching JS: { v: 1, salt: number[], iv: number[], data: number[] }
        let output: [String: Any] = [
            "v": 1,
            "salt": [UInt8](salt),
            "iv": [UInt8](iv),
            "data": [UInt8](sealed.ciphertext + sealed.tag) // GCM appends auth tag
        ]

        return try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
    }

    // MARK: - Decryption (matches popup.js decryptBackup)

    static func decrypt(encryptedData: Data, password: String) throws -> [String: Any] {
        guard let blob = try JSONSerialization.jsonObject(with: encryptedData) as? [String: Any] else {
            throw BackupError.invalidFormat
        }

        guard let saltArray = blob["salt"] as? [Int],
              let ivArray = blob["iv"] as? [Int],
              let dataArray = blob["data"] as? [Int] else {
            throw BackupError.invalidFormat
        }

        let salt = Data(saltArray.map { UInt8(clamping: $0) })
        let iv = Data(ivArray.map { UInt8(clamping: $0) })
        let encryptedBytes = Data(dataArray.map { UInt8(clamping: $0) })

        // PBKDF2 key derivation — same parameters
        let key = try deriveKey(password: password, salt: salt)
        let symmetricKey = SymmetricKey(data: key)

        // AES-GCM: last 16 bytes = auth tag, rest = ciphertext
        guard encryptedBytes.count > 16 else { throw BackupError.invalidFormat }
        let ciphertext = encryptedBytes.prefix(encryptedBytes.count - 16)
        let tag = encryptedBytes.suffix(16)

        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let result = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] else {
            throw BackupError.decryptionFailed
        }

        return result
    }

    // MARK: - PBKDF2 Key Derivation

    private static func deriveKey(password: String, salt: Data) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw BackupError.invalidPassword
        }

        // PBKDF2-SHA256, 600000 iterations, 32-byte key — matches JS crypto.subtle.deriveKey
        var derivedKey = Data(count: 32)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            passwordData.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        600_000,
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw BackupError.keyDerivationFailed
        }

        return derivedKey
    }

    // MARK: - Build Backup Payload

    static func buildBackupPayload(account: Account) -> [String: Any] {
        var payload: [String: Any] = [
            "address": account.address,
            "publicKeyX": account.publicKeyX,
            "publicKeyY": account.publicKeyY,
            "credentialId": account.credentialId,
            "label": account.label,
            "type": account.type.rawValue,
            "deployed": account.deployed,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // Load sensitive keys from Keychain
        if let keys = try? KeychainManager.loadAccountKeys(address: account.address) {
            if let sk = keys.secretKey { payload["secretKey"] = sk }
            if let pk = keys.privateKey { payload["privateKeyPkcs8"] = pk }
            if let salt = keys.salt { payload["salt"] = salt }
        }

        return payload
    }

    // MARK: - Restore from Backup Payload

    static func restoreAccount(from payload: [String: Any]) throws -> Account {
        guard let address = payload["address"] as? String,
              let publicKeyX = payload["publicKeyX"] as? String,
              let publicKeyY = payload["publicKeyY"] as? String else {
            throw BackupError.incompleteBackup
        }

        let account = Account(
            address: address,
            credentialId: payload["credentialId"] as? String ?? "",
            publicKeyX: publicKeyX,
            publicKeyY: publicKeyY,
            type: Account.AccountType(rawValue: payload["type"] as? String ?? "passkey") ?? .passkey,
            label: payload["label"] as? String ?? "Restored",
            deployed: payload["deployed"] as? Bool ?? true,
            salt: payload["salt"] as? String,
            secretKey: payload["secretKey"] as? String,
            privateKeyPkcs8: payload["privateKeyPkcs8"] as? String
        )

        // Store sensitive keys in Keychain (biometric-protected)
        try KeychainManager.saveAccountKeys(
            address: address,
            secretKey: payload["secretKey"] as? String,
            privateKeyPkcs8: payload["privateKeyPkcs8"] as? String,
            salt: payload["salt"] as? String
        )

        return account
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case invalidFormat
    case invalidPassword
    case decryptionFailed
    case keyDerivationFailed
    case incompleteBackup

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid backup format"
        case .invalidPassword: return "Invalid password"
        case .decryptionFailed: return "Decryption failed — wrong password?"
        case .keyDerivationFailed: return "Key derivation failed"
        case .incompleteBackup: return "Backup data is incomplete (missing address or keys)"
        }
    }
}
