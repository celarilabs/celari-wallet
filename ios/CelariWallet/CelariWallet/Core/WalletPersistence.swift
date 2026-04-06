import Foundation
import WidgetKit

// MARK: - WalletPersistence
//
// Encapsulates all UserDefaults read/write operations that were previously
// scattered through WalletStore. WalletStore delegates every save/load call
// to an instance of this class.

@Observable
class WalletPersistence {

    // MARK: - Keys

    // Structured data (JSON-encoded)
    let accountsKey          = "celari_accounts"
    let configKey            = "celari_config"
    let customTokensKey      = "celari_custom_tokens"
    let customNetworksKey    = "celari_custom_networks"
    let nftContractsKey      = "celari_custom_nft_contracts"
    let activitiesKey        = "celari_activities"

    // Loose keys (stored with primitive setters)
    private let cachedTokensKey              = "cachedTokens"
    private let guardianStatusKey            = "guardianStatus"
    private let guardiansKey                 = "guardians"
    private let bridgeTransactionsKey        = "bridgeTransactions"
    private let lastKnownNetworkVersionKey   = "lastKnownNetworkVersion"
    private let lastBackupDateKey            = "lastBackupDate"
    private let pinataApiKeyKey              = "pinataApiKey"
    private let dailyWithdrawalAmountKey     = "dailyWithdrawalAmount"
    private let dailyWithdrawalDateKey       = "dailyWithdrawalDate"
    private let dailyWithdrawalLimitKey      = "dailyWithdrawalLimit"
    private let largeTransactionThresholdKey = "largeTransactionThreshold"

    // Widget App Group
    private let widgetSuiteName      = "group.com.celari.wallet"
    private let widgetBalanceKey     = "widgetTotalBalance"
    private let widgetTokensKey      = "widgetTokens"

    // MARK: - Load Methods

    func loadAccounts() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else { return [] }
        return decoded
    }

    func loadCustomTokens() -> [CustomToken] {
        guard let data = UserDefaults.standard.data(forKey: customTokensKey),
              let decoded = try? JSONDecoder().decode([CustomToken].self, from: data) else { return [] }
        return decoded
    }

    func loadCustomNetworks() -> [CustomNetwork] {
        guard let data = UserDefaults.standard.data(forKey: customNetworksKey),
              let decoded = try? JSONDecoder().decode([CustomNetwork].self, from: data) else { return [] }
        return decoded
    }

    func loadNftContracts() -> [NFTContract] {
        guard let data = UserDefaults.standard.data(forKey: nftContractsKey),
              let decoded = try? JSONDecoder().decode([NFTContract].self, from: data) else { return [] }
        return decoded
    }

    func loadActivities() -> [Activity] {
        guard let data = UserDefaults.standard.data(forKey: activitiesKey),
              let decoded = try? JSONDecoder().decode([Activity].self, from: data) else { return [] }
        return decoded
    }

    /// Returns (network, nodeUrl) defaults are the caller's responsibility if nil.
    func loadConfig() -> (network: String?, nodeUrl: String?) {
        guard let config = UserDefaults.standard.dictionary(forKey: configKey) else { return (nil, nil) }
        return (config["network"] as? String, config["nodeUrl"] as? String)
    }

    func loadCachedTokens() -> [Token]? {
        guard let data = UserDefaults.standard.data(forKey: cachedTokensKey),
              let cached = try? JSONDecoder().decode([Token].self, from: data) else { return nil }
        return cached
    }

    func loadGuardianStatus() -> GuardianStatus? {
        guard let data = UserDefaults.standard.data(forKey: guardianStatusKey),
              let status = try? JSONDecoder().decode(GuardianStatus.self, from: data) else { return nil }
        return status
    }

    func loadGuardians() -> [String] {
        return UserDefaults.standard.stringArray(forKey: guardiansKey) ?? []
    }

    func loadBridgeTransactions() -> [BridgeTransaction] {
        guard let data = UserDefaults.standard.data(forKey: bridgeTransactionsKey),
              let txs = try? JSONDecoder().decode([BridgeTransaction].self, from: data) else { return [] }
        return txs
    }

    // MARK: - Save Methods

    func saveAccounts(_ accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    func saveConfig(network: String, nodeUrl: String) {
        UserDefaults.standard.set(["network": network, "nodeUrl": nodeUrl], forKey: configKey)
    }

    func saveCustomTokens(_ customTokens: [CustomToken]) {
        if let data = try? JSONEncoder().encode(customTokens) {
            UserDefaults.standard.set(data, forKey: customTokensKey)
        }
    }

    func saveNftContracts(_ contracts: [NFTContract]) {
        if let data = try? JSONEncoder().encode(contracts) {
            UserDefaults.standard.set(data, forKey: nftContractsKey)
        }
    }

    func saveActivities(_ activities: [Activity]) {
        if let data = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(data, forKey: activitiesKey)
        }
    }

    func saveCachedTokens(_ tokens: [Token]) {
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: cachedTokensKey)
        }
    }

    func saveGuardianStatus(_ status: GuardianStatus, guardians: [String]) {
        if let data = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(data, forKey: guardianStatusKey)
        }
        UserDefaults.standard.set(guardians, forKey: guardiansKey)
    }

    func saveBridgeTransactions(_ transactions: [BridgeTransaction]) {
        if let data = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(data, forKey: bridgeTransactionsKey)
        }
    }

    // MARK: - Scalar UserDefaults Properties

    var lastKnownNetworkVersion: String {
        get { UserDefaults.standard.string(forKey: lastKnownNetworkVersionKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: lastKnownNetworkVersionKey) }
    }

    var lastBackupDate: Double {
        get { UserDefaults.standard.double(forKey: lastBackupDateKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastBackupDateKey) }
    }

    var pinataApiKey: String? {
        get { UserDefaults.standard.string(forKey: pinataApiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: pinataApiKeyKey) }
    }

    var dailyWithdrawalAmount: Double {
        get { UserDefaults.standard.double(forKey: dailyWithdrawalAmountKey) }
        set { UserDefaults.standard.set(newValue, forKey: dailyWithdrawalAmountKey) }
    }

    var dailyWithdrawalDate: String {
        get { UserDefaults.standard.string(forKey: dailyWithdrawalDateKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: dailyWithdrawalDateKey) }
    }

    var dailyWithdrawalLimit: Double {
        get {
            let val = UserDefaults.standard.double(forKey: dailyWithdrawalLimitKey)
            return val > 0 ? val : 1000.0
        }
        set { UserDefaults.standard.set(newValue, forKey: dailyWithdrawalLimitKey) }
    }

    var largeTransactionThreshold: Double {
        get {
            let val = UserDefaults.standard.double(forKey: largeTransactionThresholdKey)
            return val > 0 ? val : 100.0
        }
        set { UserDefaults.standard.set(newValue, forKey: largeTransactionThresholdKey) }
    }

    // MARK: - Widget Update

    /// Writes the current token list to the shared App Group so the widget
    /// can display up-to-date balances. Call this whenever `tokens` changes.
    func updateWidget(tokens: [Token]) {
        let shared = UserDefaults(suiteName: widgetSuiteName)
        shared?.set(tokens.first?.balance ?? "0.00", forKey: widgetBalanceKey)
        let widgetTokens = tokens.prefix(3).map { [$0.symbol, $0.balance] }
        if let data = try? JSONEncoder().encode(widgetTokens) {
            shared?.set(data, forKey: widgetTokensKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
