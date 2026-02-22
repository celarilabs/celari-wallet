import Security
import LocalAuthentication
import os.log

private let kcLog = Logger(subsystem: "com.celari.wallet", category: "Keychain")

enum KeychainManager {

    private static let service = "com.celari.wallet"

    // MARK: - Simulator Fallback
    // Simulator builds with CODE_SIGNING_ALLOWED=NO or ad-hoc signing lack the
    // keychain-access-groups entitlement, causing ALL Keychain operations to fail
    // with errSecMissingEntitlement (-34018). We detect this at first save and
    // fall back to UserDefaults for the rest of the session.

    private static let fallbackPrefix = "kc_fallback_"
    private static var _useFallback: Bool?

    private static var useFallback: Bool {
        if let cached = _useFallback { return cached }
        #if targetEnvironment(simulator)
        // Probe Keychain: try to save and immediately delete a test item
        let testKey = "__keychain_probe__"
        let testQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: testKey,
            kSecValueData as String: Data([0x42]),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(testQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            // Cleanup probe item
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: testKey,
            ]
            SecItemDelete(delQuery as CFDictionary)
            kcLog.notice("[Keychain] Probe succeeded — using real Keychain")
            _useFallback = false
        } else {
            kcLog.notice("[Keychain] Probe failed (\(addStatus)) — using UserDefaults fallback")
            _useFallback = true
        }
        #else
        _useFallback = false
        #endif
        return _useFallback!
    }

    // MARK: - Save

    static func save(key: String, data: Data, requireBiometric: Bool = false) throws {
        if useFallback {
            UserDefaults.standard.set(data, forKey: fallbackPrefix + key)
            return
        }

        // Delete existing entry first
        try? delete(key: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        #if !targetEnvironment(simulator)
        if requireBiometric {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
            if let access {
                query[kSecAttrAccessControl as String] = access
                query.removeValue(forKey: kSecAttrAccessible as String)
            }
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func save(key: String, string: String, requireBiometric: Bool = false) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key, data: data, requireBiometric: requireBiometric)
    }

    // MARK: - Load

    static func load(key: String) throws -> Data? {
        if useFallback {
            return UserDefaults.standard.data(forKey: fallbackPrefix + key)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    static func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    static func delete(key: String) throws {
        if useFallback {
            UserDefaults.standard.removeObject(forKey: fallbackPrefix + key)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Account-Specific Keys

    static func saveAccountKeys(address: String, secretKey: String?, privateKeyPkcs8: String?, salt: String?) throws {
        if let sk = secretKey {
            try save(key: "sk_\(address)", string: sk, requireBiometric: true)
        }
        if let pk = privateKeyPkcs8 {
            try save(key: "pk_\(address)", string: pk, requireBiometric: true)
        }
        if let s = salt {
            try save(key: "salt_\(address)", string: s)
        }
    }

    static func loadAccountKeys(address: String) throws -> (secretKey: String?, privateKey: String?, salt: String?) {
        let sk = try loadString(key: "sk_\(address)")
        let pk = try loadString(key: "pk_\(address)")
        let salt = try loadString(key: "salt_\(address)")
        return (sk, pk, salt)
    }

    static func deleteAccountKeys(address: String) throws {
        try delete(key: "sk_\(address)")
        try delete(key: "pk_\(address)")
        try delete(key: "salt_\(address)")
    }

    // MARK: - Delete All

    static func deleteAll() throws {
        if useFallback {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(fallbackPrefix) {
                defaults.removeObject(forKey: key)
            }
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .loadFailed(let s): return "Keychain load failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        case .encodingFailed: return "String encoding failed"
        }
    }
}
