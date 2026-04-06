import SwiftUI
import CryptoKit
import os.log

private let walletLog = Logger(subsystem: "com.celari.wallet", category: "WalletStore")

// MARK: - Screen Navigation

enum Screen: Equatable {
    case loading
    case onboarding
    case dashboard
    case send
    case receive
    case settings
    case addToken
    case addAccount
    case backup
    case restore
    case confirmTx
    case addNftContract
    case nftDetail
    case walletConnect
    case wcApprove
    case guardianSetup
    case recoverAccount
}

// MARK: - PXE State

enum PXEState: Equatable {
    case notStarted
    case initializing
    case syncing(progress: String)
    case ready
    case failed(error: String)
}

// MARK: - Guardian Status

enum GuardianStatus: Codable, Equatable {
    case notSetup
    case configured(guardianCount: Int)
    case recoveryPending(initiatedAt: Date, deadline: Date)
    case recovered
}

    struct BridgeTransaction: Codable, Identifiable, Equatable {
        let id: UUID
        let type: BridgeType
        let token: String
        let amount: String
        var status: BridgeStatus
        let l1TxHash: String?
        var l2TxHash: String?
        let timestamp: Date

        enum BridgeType: String, Codable { case deposit, withdraw }
        enum BridgeStatus: String, Codable { case pending, l1Confirmed, l2Claimed, failed }
    }

// MARK: - Supporting Types

struct NodeInfo: Codable {
    var nodeVersion: String
    var l1ChainId: Int?
    var protocolVersion: Int?
}

struct SendForm {
    var to: String = ""
    var amount: String = ""
    var token: String = "zkUSD"
    var transferType: TransferType = .privateTransfer
}

enum TransferType: String, CaseIterable {
    case privateTransfer = "private"
    case publicTransfer = "public"
    case shield = "shield"
    case unshield = "unshield"

    var label: String {
        switch self {
        case .privateTransfer: return "PRIVATE"
        case .publicTransfer: return "PUBLIC"
        case .shield: return "SHIELD"
        case .unshield: return "UNSHIELD"
        }
    }

    var description: String {
        switch self {
        case .privateTransfer: return "Fully private transfer — invisible to observers"
        case .publicTransfer: return "Public transfer — visible on-chain"
        case .shield: return "Shield — move public balance into private notes"
        case .unshield: return "Unshield — move private notes to public balance"
        }
    }

    var isPrivate: Bool { self == .privateTransfer || self == .shield }
}

struct CustomNetwork: Codable, Identifiable {
    var id: String
    var name: String
    var url: String
}

struct Toast: Equatable {
    var message: String
    var type: ToastType

    enum ToastType: Equatable {
        case success
        case error
    }
}

struct NFTDetailSelection: Equatable {
    var contractAddress: String
    var tokenId: String
}

// MARK: - Network Presets

enum NetworkPreset: String, CaseIterable {
    case local = "local"
    case devnet = "devnet"
    case testnet = "testnet"
    case mainnet = "mainnet"

    var name: String {
        switch self {
        case .local: return "Local Sandbox"
        case .devnet: return "Aztec Devnet"
        case .testnet: return "Aztec Testnet"
        case .mainnet: return "Aztec Mainnet"
        }
    }

    var url: String {
        switch self {
        case .local: return "http://localhost:8080"
        case .devnet: return "https://v4-devnet-2.aztec-labs.com/"
        case .testnet: return "https://rpc.testnet.aztec-labs.com/"
        case .mainnet: return "https://rpc.aztec.network/"
        }
    }

    var hasSponsoredFPC: Bool {
        switch self {
        case .local, .devnet: return true
        case .testnet, .mainnet: return false
        }
    }
}

// MARK: - PXE Log Entry

struct PXELogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let message: String

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    var levelIcon: String {
        switch level {
        case "error": return "✕"
        case "warn": return "⚠"
        default: return "›"
        }
    }
}

// MARK: - Wallet Store

@MainActor
@Observable
class WalletStore {
    // Navigation
    var screen: Screen = .loading

    // Connection (forwarded to walletNetworkManager)
    var connected: Bool {
        get { walletNetworkManager.connected }
        set { walletNetworkManager.connected = newValue }
    }
    var network: String {
        get { walletNetworkManager.network }
        set { walletNetworkManager.network = newValue }
    }
    var nodeUrl: String {
        get { walletNetworkManager.nodeUrl }
        set { walletNetworkManager.nodeUrl = newValue }
    }
    var nodeInfo: NodeInfo? { walletNetworkManager.nodeInfo }

    // Accounts
    var accounts: [Account] = []
    var activeAccountIndex: Int = 0

    // Tokens
    var tokens: [Token] = [] {
        didSet {
            persistence.updateWidget(tokens: self.tokens)
        }
    }
    var customTokens: [CustomToken] = []
    var tokenAddresses: [String: String] = [:]

    // Activities
    var activities: [Activity] = []

    // NFTs
    var nfts: [NFTItem] = []
    var customNftContracts: [NFTContract] = []
    var nftDetail: NFTDetailSelection?

    // WalletConnect
    var wcSessions: [WCSession] = []
    var wcProposal: WCProposal?

    // Networks (forwarded to walletNetworkManager)
    var customNetworks: [CustomNetwork] {
        get { walletNetworkManager.customNetworks }
        set { walletNetworkManager.customNetworks = newValue }
    }
    var deployServerUrl: String {
        get { walletNetworkManager.deployServerUrl }
        set { walletNetworkManager.deployServerUrl = newValue }
    }

    // UI State
    var sendForm: SendForm = SendForm()
    var toast: Toast?
    var loading: Bool = false
    var deploying: Bool = false
    var pxeState: PXEState = .notStarted

    var pxeInitialized: Bool { pxeState == .ready }
    var pxeInitFailed: Bool {
        if case .failed = pxeState { return true }
        return false
    }

    /// Live progress message from PXE operations (shown as bottom status bar)
    var progressMessage: String?

    /// Fee Juice balance on L2 (needed for transaction fees on testnet where SponsoredFPC is unavailable)
    var feeJuiceBalance: String = "0"

    /// Faucet claim data (stored after requesting Fee Juice, used during deploy for FeeJuicePaymentMethodWithClaim)
    var faucetClaimData: [String: String]?
    var faucetRequesting: Bool = false

    // PXE Logs (in-app console)
    var pxeLogs: [PXELogEntry] = []
    var showLogs: Bool = false
    var deployStep: String = ""
    private let maxLogEntries = 200

    // Guardian Recovery (forwarded to guardianManager)
    var guardianStatus: GuardianStatus {
        get { guardianManager.guardianStatus }
        set { guardianManager.guardianStatus = newValue }
    }
    var guardians: [String] {
        get { guardianManager.guardians }
        set { guardianManager.guardians = newValue }
    }

    // Bridge
    var bridgeTransactions: [BridgeTransaction] = []

    // State Migration & Backup Tracking
    var pxeNodeInfo: String?
    var backupReminderDismissed: Bool = false

    var lastKnownNetworkVersion: String {
        get { persistence.lastKnownNetworkVersion }
        set { persistence.lastKnownNetworkVersion = newValue }
    }

    var lastBackupDate: Double {
        get { persistence.lastBackupDate }
        set { persistence.lastBackupDate = newValue }
    }

    var pinataApiKey: String? {
        get { persistence.pinataApiKey }
        set { persistence.pinataApiKey = newValue }
    }

    var needsBackupReminder: Bool {
        let daysSinceBackup = (Date().timeIntervalSince1970 - lastBackupDate) / 86400
        return daysSinceBackup > 7 && accounts.count > 0
    }

    var networkVersionChanged: Bool {
        !lastKnownNetworkVersion.isEmpty && lastKnownNetworkVersion != currentNetworkVersion
    }

    private var currentNetworkVersion: String {
        return pxeNodeInfo ?? nodeInfo?.nodeVersion ?? "unknown"
    }

    func acknowledgeNetworkVersion() {
        lastKnownNetworkVersion = currentNetworkVersion
    }

    // MARK: - Computed

    var activeAccount: Account? {
        guard activeAccountIndex >= 0, activeAccountIndex < accounts.count else { return nil }
        return accounts[activeAccountIndex]
    }

    var isDemo: Bool { activeAccount?.type == .demo }

    var totalValue: String {
        // Sum token values
        let total = tokens.compactMap { t -> Double? in
            let cleaned = t.value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }.reduce(0, +)
        return String(format: "$%.2f", total)
    }

    // Core managers
    let persistence = WalletPersistence()
    let networkManager = NetworkManager()
    let walletNetworkManager = WalletNetworkManager()
    let passkeyManager = PasskeyManager()
    private var _guardianManager: GuardianManager?
    var guardianManager: GuardianManager {
        if _guardianManager == nil { _guardianManager = GuardianManager(persistence: persistence) }
        return _guardianManager!
    }
    weak var pxeBridge: PXEBridge?

    // MARK: - Initialization

    func initialize(pxeBridge: PXEBridge) async {
        self.pxeBridge = pxeBridge
        // Load persisted data
        loadFromStorage()

        // Clean up orphaned pending addresses (failed deployments that left stale entries)
        let beforeCount = self.accounts.count
        self.accounts.removeAll { $0.address.hasPrefix("pending_") && !$0.deployed }
        if self.accounts.count < beforeCount {
            walletLog.notice("[WalletStore] Cleaned \(beforeCount - self.accounts.count, privacy: .public) orphaned pending account(s)")
            self.saveAccounts()
        }

        walletLog.notice("[WalletStore] initialize — accounts: \(self.accounts.count, privacy: .public), network: \(self.network, privacy: .public)")

        if accounts.isEmpty {
            #if targetEnvironment(simulator)
            // Auto-create a test wallet on simulator (no passkey UI available headless)
            walletLog.notice("[WalletStore] No accounts found — auto-creating test wallet (simulator)")
            do {
                try await createPasskeyAccount(pxeBridge: pxeBridge)
            } catch {
                walletLog.error("[WalletStore] Auto-create failed: \(error.localizedDescription, privacy: .public)")
                screen = .onboarding
            }
            #else
            walletLog.notice("[WalletStore] No accounts found — showing onboarding")
            screen = .onboarding
            #endif
        } else {
            tokens = Token.defaults
            screen = .dashboard
            walletLog.notice("[WalletStore] Loaded \(self.accounts.count, privacy: .public) account(s) — showing dashboard")

            // Check node connection in background
            Task { await checkConnection() }
        }

        // NOTE: setupWebView() is called in CelariWalletApp.onAppear — do NOT call it here
        // (calling it twice created a race condition where the second WKWebView replaced the first)

        // Wait for WebView to become ready, then send PXE_INIT
        // This applies whether we have accounts or not — PXE should always be initialized
        Task {
            walletLog.notice("[WalletStore] Waiting for PXE bridge to become ready...")
            // Poll until WebView is ready (max ~30s — first load of 68MB bundle can be slow)
            for i in 0..<300 {
                if pxeBridge.isReady { break }
                try? await Task.sleep(for: .milliseconds(100))
                if i > 0 && i % 50 == 0 {
                    walletLog.notice("[WalletStore] Still waiting for PXE bridge... (\(i * 100, privacy: .public)ms)")
                }
            }
            guard pxeBridge.isReady else {
                walletLog.error("[WalletStore] PXE WebView failed to load after 30s")
                self.pxeState = .failed(error: "PXE engine failed to load. Check your connection and try again.")
                self.showToast("PXE initialization failed — tap to retry", type: .error)
                return
            }
            walletLog.notice("[WalletStore] PXE bridge ready — sending PXE_INIT to \(self.nodeUrl, privacy: .public)")
            self.pxeState = .initializing
            do {
                let result = try await pxeBridge.initPXE(nodeUrl: self.nodeUrl)
                self.pxeState = .syncing(progress: "Restoring state...")
                walletLog.notice("[WalletStore] PXE initialized: \(String(describing: result).prefix(200), privacy: .public)")

                // Restore PXE snapshot if available (preserves notes, contracts, tree data across restarts)
                if PXEPersistenceManager.hasSnapshot() {
                    walletLog.notice("[WalletStore] PXE snapshot found — restoring...")
                    do {
                        let json = try await PXEPersistenceManager.load()
                        try await pxeBridge.restoreSnapshot(json: json)
                        walletLog.notice("[WalletStore] PXE snapshot restored OK — \(json.count / 1024) KB")
                        if let lastBlock = PXEPersistenceManager.getLastSyncedBlock() {
                            walletLog.notice("[WalletStore] Incremental sync from block \(lastBlock, privacy: .public)")
                        }
                    } catch {
                        walletLog.error("[WalletStore] PXE snapshot restore failed: \(error.localizedDescription, privacy: .public) — continuing with fresh store")
                    }
                }

                if let account = self.activeAccount, account.deployed {
                    self.pxeState = .syncing(progress: "Re-registering account...")
                    // Account already deployed — re-register with PXE (in-memory store is fresh)
                    walletLog.notice("[WalletStore] PXE ready, account deployed — re-registering with PXE")
                    await self.reRegisterAccount(pxeBridge: pxeBridge, account: account)
                    self.pxeState = .syncing(progress: "Syncing notes...")
                    // Wait for PXE block sync to discover private notes (note sync needs a few seconds)
                    walletLog.notice("[WalletStore] Waiting 3s for PXE note sync...")
                    try? await Task.sleep(for: .seconds(3))
                    await self.fetchBalances()
                    await self.checkFeeJuiceBalance()
                    // Save PXE snapshot so private notes persist across restarts
                    await self.savePXESnapshot()
                    self.pxeState = .ready
                    await self.checkGuardianStatus()
                }

                #if targetEnvironment(simulator)
                // Auto-deploy on simulator when account exists but is not deployed
                if let account = self.activeAccount, !account.deployed {
                    walletLog.notice("[WalletStore] Simulator: auto-deploying undeployed account...")
                    await self.deployActiveAccount(pxeBridge: pxeBridge)
                }
                #endif
            } catch {
                walletLog.error("[WalletStore] PXE init failed: \(error.localizedDescription, privacy: .public)")
                self.pxeState = .failed(error: error.localizedDescription)
                self.showToast("PXE init failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Retry PXE initialization after a failure
    func retryPXEInit() async {
        guard let pxeBridge else { return }
        pxeState = .notStarted
        showToast("Retrying PXE initialization...")
        do {
            let result = try await pxeBridge.initPXE(nodeUrl: self.nodeUrl)
            self.pxeState = .syncing(progress: "Restoring state...")
            walletLog.notice("[WalletStore] PXE retry succeeded: \(String(describing: result).prefix(200), privacy: .public)")
            if let account = self.activeAccount, account.deployed {
                await self.reRegisterAccount(pxeBridge: pxeBridge, account: account)
                try? await Task.sleep(for: .seconds(3))
                await self.fetchBalances()
                await self.checkFeeJuiceBalance()
                await self.savePXESnapshot()
            }
            self.pxeState = .ready
            showToast("PXE initialized successfully!")
        } catch {
            pxeState = .failed(error: error.localizedDescription)
            showToast("PXE retry failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - PXE Snapshot Persistence

    func savePXESnapshot() async {
        guard pxeInitialized, let pxeBridge else {
            walletLog.notice("[WalletStore] savePXESnapshot skipped — PXE not initialized")
            return
        }
        do {
            walletLog.notice("[WalletStore] Saving PXE snapshot...")
            let json = try await pxeBridge.saveSnapshot()
            try await PXEPersistenceManager.save(json: json)
            walletLog.notice("[WalletStore] PXE snapshot saved — \(json.count / 1024) KB")
            // Save last synced block for incremental sync tracking
            if let result = try? await pxeBridge.checkStatus(),
               let blockNum = result["blockNumber"] as? Int {
                PXEPersistenceManager.saveLastSyncedBlock(blockNum)
                walletLog.notice("[WalletStore] Snapshot saved at block \(blockNum, privacy: .public)")
            }
        } catch {
            walletLog.error("[WalletStore] PXE snapshot save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Network Connection

    func checkConnection() async {
        await walletNetworkManager.checkConnection()
        // Track network version for state migration warnings
        if let version = walletNetworkManager.nodeInfo?.nodeVersion {
            pxeNodeInfo = version
            if lastKnownNetworkVersion.isEmpty {
                lastKnownNetworkVersion = version
            }
        }
        walletLog.notice("[WalletStore] checkConnection — connected: \(self.connected, privacy: .public), nodeVersion: \(self.nodeInfo?.nodeVersion ?? "nil", privacy: .public)")
    }

    func switchNetwork(preset: NetworkPreset) async {
        await walletNetworkManager.switchNetwork(preset: preset)
        saveConfig()
    }

    // MARK: - Balance Fetching

    func fetchBalances() async {
        guard let account = activeAccount, account.deployed else {
            walletLog.notice("[WalletStore] fetchBalances skipped — account nil or not deployed (deployed: \(self.activeAccount?.deployed ?? false, privacy: .public))")
            return
        }
        walletLog.notice("[WalletStore] fetchBalances — address: \(account.address.prefix(20), privacy: .public)...")

        // Try deploy server first
        if !deployServerUrl.isEmpty {
            do {
                let response = try await networkManager.fetchBalances(
                    deployServerUrl: deployServerUrl,
                    address: account.address
                )
                tokenAddresses = response.tokenAddresses
                if !response.tokens.isEmpty {
                    let serverSymbols = Set(response.tokens.map(\.symbol))
                    let customExtras = customTokens
                        .filter { !serverSymbols.contains($0.symbol) }
                        .map { Token(name: $0.name, symbol: $0.symbol, balance: "—", value: "$0.00", icon: "C", color: "#666", isCustom: true) }
                    tokens = response.tokens + customExtras
                    // Cache balances for instant display on next launch
                    persistence.saveCachedTokens(self.tokens)
                    return
                }
            } catch {
                walletLog.notice("[WalletStore] Deploy server balance fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback: use PXE bridge to query balances directly on-chain
        if let bridge = pxeBridge, pxeInitialized {
            await fetchBalancesViaPXE(bridge: bridge, address: account.address)
            return
        }

        // Last resort: show defaults + custom tokens
        if tokens.isEmpty || tokens.allSatisfy({ !$0.isCustom && $0.balance == "0" || $0.balance == "0.00" || $0.balance == "0.000" }) {
            let defaults = Token.defaults
            let defaultSymbols = Set(defaults.map(\.symbol))
            let customExtras = customTokens
                .filter { !defaultSymbols.contains($0.symbol) }
                .map { Token(name: $0.name, symbol: $0.symbol, balance: "—", value: "$0.00",
                             icon: String($0.symbol.prefix(1)), color: "#666",
                             contractAddress: $0.contractAddress, decimals: $0.decimals, isCustom: true) }
            tokens = defaults + customExtras
        }
    }

    private func fetchBalancesViaPXE(bridge: PXEBridge, address: String) async {
        // Build token list: defaults (with known addresses) + custom tokens
        var tokenList: [[String: String]] = []

        // Add custom tokens (they have contract addresses), dedup by address
        for ct in customTokens {
            if !tokenList.contains(where: { $0["address"] == ct.contractAddress }) {
                tokenList.append([
                    "address": ct.contractAddress,
                    "name": ct.name,
                    "symbol": ct.symbol,
                    "decimals": String(ct.decimals),
                ])
            }
        }

        // Also add any known token addresses from previous fetches (dedup by address)
        for (symbol, addr) in tokenAddresses {
            if !tokenList.contains(where: { $0["address"] == addr || $0["symbol"] == symbol }) {
                let name = Token.defaults.first(where: { $0.symbol == symbol })?.name ?? symbol
                tokenList.append(["address": addr, "name": name, "symbol": symbol, "decimals": "18"])
            }
        }

        guard !tokenList.isEmpty else {
            walletLog.notice("[WalletStore] fetchBalancesViaPXE — no tokens with contract addresses to query")
            let customExtras = customTokens.map {
                Token(name: $0.name, symbol: $0.symbol, balance: "—", value: "$0.00",
                      icon: String($0.symbol.prefix(1)), color: "#666",
                      contractAddress: $0.contractAddress, decimals: $0.decimals, isCustom: true)
            }
            tokens = Token.defaults + customExtras
            return
        }

        walletLog.notice("[WalletStore] fetchBalancesViaPXE — querying \(tokenList.count, privacy: .public) token(s)...")

        do {
            let result = try await bridge.getBalances(address: address, tokens: tokenList)
            walletLog.notice("[WalletStore] PXE balances result: \(String(describing: result).prefix(300), privacy: .public)")

            if let balances = result["balances"] as? [[String: Any]] {
                var fetchedTokens: [Token] = []
                for b in balances {
                    let symbol = b["symbol"] as? String ?? "?"
                    let name = b["name"] as? String ?? symbol
                    let balance = b["balance"] as? String ?? "0"
                    let publicBal = b["publicBalance"] as? String ?? "0"
                    let privateBal = b["privateBalance"] as? String ?? "0"
                    let addr = b["address"] as? String

                    // Map icon/color from defaults or use generic
                    let defaultToken = Token.defaults.first(where: { $0.symbol == symbol })
                    let icon = defaultToken?.icon ?? String(symbol.prefix(1))
                    let color = defaultToken?.color ?? "#666"

                    fetchedTokens.append(Token(
                        name: name, symbol: symbol, balance: balance,
                        publicBalance: publicBal, privateBalance: privateBal,
                        value: "$0.00", icon: icon, color: color,
                        contractAddress: addr, isCustom: defaultToken == nil
                    ))

                    // Cache token address for transfers
                    if let addr { tokenAddresses[symbol] = addr }
                }

                // Add defaults that weren't in the query (they have no contract address)
                let fetchedSymbols = Set(fetchedTokens.map(\.symbol))
                let remaining = Token.defaults.filter { !fetchedSymbols.contains($0.symbol) }
                tokens = fetchedTokens + remaining
                // Cache balances for instant display on next launch
                persistence.saveCachedTokens(self.tokens)
            }
        } catch {
            walletLog.error("[WalletStore] PXE balance fetch failed: \(error.localizedDescription, privacy: .public)")
            let customExtras = customTokens.map {
                Token(name: $0.name, symbol: $0.symbol, balance: "?", value: "$0.00",
                      icon: String($0.symbol.prefix(1)), color: "#666",
                      contractAddress: $0.contractAddress, decimals: $0.decimals, isCustom: true)
            }
            tokens = Token.defaults + customExtras
        }
    }

    // MARK: - Fee Juice Balance

    func checkFeeJuiceBalance() async {
        guard let bridge = pxeBridge, pxeInitialized else {
            walletLog.notice("[WalletStore] checkFeeJuiceBalance skipped — PXE not initialized")
            return
        }
        guard let account = activeAccount, account.deployed else {
            walletLog.notice("[WalletStore] checkFeeJuiceBalance skipped — no deployed account")
            return
        }
        do {
            let balance = try await bridge.getFeeJuiceBalance()
            feeJuiceBalance = balance
            walletLog.notice("[WalletStore] Fee Juice balance: \(balance, privacy: .public)")
        } catch {
            walletLog.error("[WalletStore] Fee Juice balance check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Guardian Recovery

    func checkGuardianStatus() async {
        guard pxeInitialized, let pxeBridge else { return }
        await guardianManager.checkGuardianStatus(pxeBridge: pxeBridge)
    }

    func scheduleRecoveryNotification(deadline: Date) {
        guardianManager.scheduleRecoveryNotification(deadline: deadline)
    }

    // MARK: - Aztec Faucet (HTTP API)

    /// Faucet progress state for UI display
    var faucetStatus: String = ""

    func requestFaucetDrip(asset: String = "fee-juice") async {
        guard let account = activeAccount, !account.address.isEmpty, !account.address.hasPrefix("pending_") else {
            showToast("No valid address — create wallet first", type: .error)
            return
        }

        faucetRequesting = true
        faucetStatus = "Requesting..."
        defer { faucetRequesting = false }

        appendPXELog(level: "info", message: "Faucet: Requesting \(asset) on \(self.network)...")
        walletLog.notice("[WalletStore] Requesting faucet drip — asset: \(asset, privacy: .public), network: \(self.network, privacy: .public), address: \(account.address.prefix(22), privacy: .public)")

        do {
            let url = URL(string: "https://aztec-faucet.dev-nethermind.xyz/api/drip")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = ["address": account.address, "asset": asset, "network": network]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 60

            faucetStatus = "Sending request to faucet..."
            appendPXELog(level: "info", message: "Faucet: Sending request to \(url.absoluteString)")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                walletLog.error("[WalletStore] Faucet HTTP \(statusCode, privacy: .public): \(bodyStr.prefix(200), privacy: .public)")
                appendPXELog(level: "error", message: "Faucet: HTTP \(statusCode) — \(bodyStr.prefix(100))")
                faucetStatus = "Failed (HTTP \(statusCode))"
                showToast("Faucet request failed (HTTP \(statusCode))", type: .error)
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success else {
                let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Unknown error"
                appendPXELog(level: "error", message: "Faucet: \(errorMsg)")
                faucetStatus = "Failed"
                showToast("Faucet: \(errorMsg)", type: .error)
                return
            }

            let claimStatus = json["claimStatus"] as? String ?? "unknown"
            let claimId = (json["claimId"] as? String ?? "").prefix(12)
            faucetStatus = "Bridging L1 → L2..."
            appendPXELog(level: "info", message: "Faucet: Response OK — status: \(claimStatus), claimId: \(claimId)")
            walletLog.notice("[WalletStore] Faucet drip success — claimId: \(claimId, privacy: .public), status: \(claimStatus, privacy: .public)")

            // Store claim data for deploy (FeeJuicePaymentMethodWithClaim)
            if let claimData = json["claimData"] as? [String: Any] {
                var cd: [String: String] = [:]
                if let v = claimData["claimAmount"] as? String { cd["claimAmount"] = v }
                if let v = claimData["claimSecretHex"] as? String { cd["claimSecret"] = v }
                if let v = claimData["messageLeafIndex"] as? String { cd["messageLeafIndex"] = v }
                if let v = claimData["messageLeafIndex"] as? Int { cd["messageLeafIndex"] = String(v) }
                faucetClaimData = cd

                let amountDisplay = cd["claimAmount"] ?? "?"
                let leafIndex = cd["messageLeafIndex"] ?? "?"
                let l1TxHash = (claimData["l1TxHash"] as? String ?? "").prefix(16)

                faucetStatus = "Claim ready!"
                appendPXELog(level: "info", message: "Faucet: Claim data received!")
                appendPXELog(level: "info", message: "  Amount: \(amountDisplay)")
                appendPXELog(level: "info", message: "  Leaf Index: \(leafIndex)")
                if !l1TxHash.isEmpty {
                    appendPXELog(level: "info", message: "  L1 TX: \(l1TxHash)...")
                }
                appendPXELog(level: "info", message: "Faucet: Ready to use for deploy/transactions")

                walletLog.notice("[WalletStore] Stored faucet claim data — amount: \(amountDisplay, privacy: .public), leafIndex: \(leafIndex, privacy: .public)")
            } else {
                faucetStatus = "Bridging..."
                appendPXELog(level: "warn", message: "Faucet: No claim data in response — bridge may still be in progress")
            }

            showToast("Fee Juice claim ready!")
        } catch {
            walletLog.error("[WalletStore] Faucet error: \(error.localizedDescription, privacy: .public)")
            appendPXELog(level: "error", message: "Faucet: \(error.localizedDescription)")
            faucetStatus = "Failed"
            showToast("Faucet failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Account Creation

    func createPasskeyAccount(pxeBridge: PXEBridge) async throws {
        loading = true
        defer { loading = false }

        walletLog.notice("[WalletStore] createPasskeyAccount started (existing accounts: \(self.accounts.count, privacy: .public))")

        // 1. Create passkey (FaceID/TouchID — mock on Simulator)
        let accountLabel = "Account \(accounts.count + 1)"
        let passkeyResult = try await passkeyManager.createPasskey(accountLabel: accountLabel)
        walletLog.notice("[WalletStore] Passkey created — credentialId: \(passkeyResult.credentialId.prefix(20), privacy: .public)...")

        // 2. Generate P-256 signing key pair
        let (pubKeyX, pubKeyY, pkcs8Base64) = try generateP256KeyPair()
        walletLog.notice("[WalletStore] P-256 key pair generated — pubKeyX: \(pubKeyX.prefix(20), privacy: .public)...")

        // 3. Compute deterministic Aztec address via PXE (if ready)
        var computedAddress = ""
        var secretKeyHex: String?
        var saltHex: String?

        if pxeBridge.isReady {
            walletLog.notice("[WalletStore] PXE ready — computing deterministic address...")
            let addrResult = try await pxeBridge.computeAddress(pubKeyX: pubKeyX, pubKeyY: pubKeyY, pkcs8: pkcs8Base64)
            if let addr = addrResult["address"] as? String, !addr.isEmpty {
                computedAddress = addr
                secretKeyHex = addrResult["secretKey"] as? String
                saltHex = addrResult["salt"] as? String
                walletLog.notice("[WalletStore] Computed address: \(computedAddress.prefix(22), privacy: .public)...")
            }
        } else {
            walletLog.warning("[WalletStore] PXE not ready — address will be computed when PXE initializes")
        }

        let finalAddress = computedAddress.isEmpty ? "pending_\(UUID().uuidString.prefix(8))" : computedAddress
        let accountLabel2 = accounts.isEmpty ? "Main Wallet" : accountLabel

        let account = Account(
            address: finalAddress,
            credentialId: passkeyResult.credentialId,
            publicKeyX: pubKeyX,
            publicKeyY: pubKeyY,
            type: .passkey,
            label: accountLabel2
        )

        accounts.append(account)
        activeAccountIndex = accounts.count - 1
        saveAccounts()
        walletLog.notice("[WalletStore] Account entry saved — label: \(account.label, privacy: .public), address: \(finalAddress.prefix(22), privacy: .public)")

        // 4. Store keys in Keychain (secretKey + salt + PKCS8)
        try KeychainManager.saveAccountKeys(
            address: finalAddress,
            secretKey: secretKeyHex,
            privateKeyPkcs8: pkcs8Base64,
            salt: saltHex
        )
        walletLog.notice("[WalletStore] Keys saved to Keychain (secretKey: \(secretKeyHex != nil, privacy: .public), salt: \(saltHex != nil, privacy: .public))")

        tokens = Token.defaults
        screen = .dashboard
        showToast("Wallet created!")
        walletLog.notice("[WalletStore] Account creation complete — navigated to dashboard")
    }

    // MARK: - P-256 Key Generation (CryptoKit)

    /// Generate a P-256 key pair natively using CryptoKit.
    /// Returns (pubKeyX as "0x..." hex, pubKeyY as "0x..." hex, PKCS8 base64 string)
    private func generateP256KeyPair() throws -> (String, String, String) {
        let privateKey = P256.Signing.PrivateKey()

        // Extract raw X and Y from the uncompressed public key (04 || X || Y)
        let rawPub = privateKey.publicKey.x963Representation
        let xBytes = rawPub[rawPub.startIndex + 1 ..< rawPub.startIndex + 33]
        let yBytes = rawPub[rawPub.startIndex + 33 ..< rawPub.startIndex + 65]

        let pubKeyX = "0x" + xBytes.map { String(format: "%02x", $0) }.joined()
        let pubKeyY = "0x" + yBytes.map { String(format: "%02x", $0) }.joined()

        // PKCS8 DER export → base64 (compatible with WebCrypto importKey("pkcs8", ...))
        let pkcs8Data = privateKey.derRepresentation
        let pkcs8Base64 = pkcs8Data.base64EncodedString()

        return (pubKeyX, pubKeyY, pkcs8Base64)
    }

    // MARK: - Account Deployment

    func deployActiveAccount(pxeBridge: PXEBridge) async {
        guard let account = activeAccount, !account.deployed else {
            walletLog.notice("[WalletStore] deployActiveAccount skipped — no account or already deployed")
            return
        }

        deploying = true
        // Keep screen awake during deploy — WKWebView JS execution pauses when
        // the screen locks, which kills proof generation and node connections.
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            deploying = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        walletLog.notice("[WalletStore] deployActiveAccount started — label: \(account.label, privacy: .public)")

        do {
            // Load keys from Keychain
            let keys = try KeychainManager.loadAccountKeys(address: account.address)
            let pubKeyX = account.publicKeyX
            let pubKeyY = account.publicKeyY
            guard !pubKeyX.isEmpty, !pubKeyY.isEmpty, let pkcs8 = keys.privateKey else {
                walletLog.error("[WalletStore] Deploy failed — missing keys for account \(account.label, privacy: .public) (pubKeyX empty: \(pubKeyX.isEmpty, privacy: .public), pubKeyY empty: \(pubKeyY.isEmpty, privacy: .public), pkcs8: \(keys.privateKey != nil, privacy: .public))")
                showToast("Deploy failed: missing keys", type: .error)
                return
            }

            walletLog.notice("[WalletStore] Calling PXE deployAccount — pubKeyX: \(pubKeyX.prefix(20), privacy: .public)..., secretKey: \(keys.secretKey != nil, privacy: .public), salt: \(keys.salt != nil, privacy: .public)")

            let result = try await pxeBridge.deployAccount(
                pubKeyX: pubKeyX, pubKeyY: pubKeyY, pkcs8: pkcs8,
                secretKey: keys.secretKey, salt: keys.salt,
                claimData: faucetClaimData
            )
            walletLog.notice("[WalletStore] deployAccount result: \(String(describing: result).prefix(200), privacy: .public)")

            // Update account with the real address and keys from deployment
            if let deployedAddress = result["address"] as? String {
                let oldPendingAddress = accounts[activeAccountIndex].address
                accounts[activeAccountIndex].address = deployedAddress
                accounts[activeAccountIndex].deployed = true
                accounts[activeAccountIndex].salt = result["salt"] as? String
                accounts[activeAccountIndex].txHash = result["txHash"] as? String
                accounts[activeAccountIndex].blockNumber = result["blockNumber"] as? String
                accounts[activeAccountIndex].network = nodeUrl
                saveAccounts()

                // Save secretKey to Keychain under the real address
                if let sk = result["secretKey"] as? String, let s = result["salt"] as? String {
                    try? KeychainManager.saveAccountKeys(
                        address: deployedAddress,
                        secretKey: sk,
                        privateKeyPkcs8: pkcs8,
                        salt: s
                    )
                }

                // Clean up orphaned Keychain entry from pending address (3.9 audit fix)
                if oldPendingAddress != deployedAddress {
                    try? KeychainManager.deleteAccountKeys(address: oldPendingAddress)
                    walletLog.notice("[WalletStore] Cleaned up pending Keychain entry: \(oldPendingAddress.prefix(20), privacy: .public)")
                }

                walletLog.notice("[WalletStore] Account deployed — address: \(deployedAddress.prefix(20), privacy: .public)..., txHash: \(result["txHash"] as? String ?? "nil", privacy: .public)")
                showToast("Account deployed!")
            } else {
                walletLog.warning("[WalletStore] Deploy returned without address — NOT marking as deployed: \(String(describing: result).prefix(200), privacy: .public)")
                showToast("Deploy incomplete: no address returned", type: .error)
            }

            // Refresh balances
            await fetchBalances()

        } catch {
            walletLog.error("[WalletStore] Deploy failed: \(error.localizedDescription, privacy: .public)")
            showToast("Deploy failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Account Re-Registration

    /// Re-registers a deployed account with the PXE's in-memory store.
    /// Required because iOS PXE uses in-memory KV (no IndexedDB persistence).
    /// Called on app restart and after account restore from backup.
    func reRegisterAccount(pxeBridge: PXEBridge, account: Account) async {
        do {
            let keys = try KeychainManager.loadAccountKeys(address: account.address)
            guard let secretKey = keys.secretKey,
                  let salt = keys.salt ?? account.salt,
                  let pkcs8 = keys.privateKey else {
                walletLog.warning("[WalletStore] Re-register skipped — missing keys for \(account.label, privacy: .public)")
                return
            }

            let result = try await pxeBridge.registerAccount(data: [
                "publicKeyX": account.publicKeyX,
                "publicKeyY": account.publicKeyY,
                "secretKey": secretKey,
                "salt": salt,
                "privateKeyPkcs8": pkcs8,
            ])
            walletLog.notice("[WalletStore] Account re-registered with PXE: \(String(describing: result).prefix(100), privacy: .public)")
        } catch {
            walletLog.error("[WalletStore] Account re-register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Account Deletion

    func deleteAccount(at index: Int) {
        guard index >= 0 && index < accounts.count else { return }
        let address = accounts[index].address
        accounts.remove(at: index)

        // Clean up Keychain
        try? KeychainManager.deleteAccountKeys(address: address)

        if accounts.isEmpty {
            activeAccountIndex = 0
            screen = .onboarding
        } else {
            activeAccountIndex = min(activeAccountIndex, accounts.count - 1)
        }
        saveAccounts()
    }

    // MARK: - Token Registration

    /// Registers a token as a custom token if it's not already tracked.
    /// Called after faucet mint so that fetchBalancesViaPXE can query its balance.
    func registerTokenIfNeeded(contractAddress: String, name: String, symbol: String, decimals: Int) {
        guard !customTokens.contains(where: { $0.contractAddress == contractAddress }) else { return }
        customTokens.append(CustomToken(contractAddress: contractAddress, name: name, symbol: symbol, decimals: decimals))
        saveCustomTokens()
        walletLog.notice("[WalletStore] Auto-registered token: \(symbol, privacy: .public) at \(contractAddress.prefix(20), privacy: .public)...")
    }

    // MARK: - Storage

    func loadFromStorage() {
        accounts = persistence.loadAccounts()
        customTokens = persistence.loadCustomTokens()
        walletNetworkManager.customNetworks = persistence.loadCustomNetworks()
        customNftContracts = persistence.loadNftContracts()
        activities = persistence.loadActivities()
        let config = persistence.loadConfig()
        if let n = config.network { walletNetworkManager.network = n }
        if let u = config.nodeUrl { walletNetworkManager.nodeUrl = u }
        // Load cached token balances for instant dashboard display
        if let cached = persistence.loadCachedTokens() {
            tokens = cached
        }
        // guardianStatus and guardians are loaded by guardianManager.init
        _ = guardianManager  // ensure lazy init runs during loadFromStorage
        bridgeTransactions = persistence.loadBridgeTransactions()
    }

    func saveAccounts() {
        persistence.saveAccounts(accounts)
    }

    func saveConfig() {
        persistence.saveConfig(network: network, nodeUrl: nodeUrl)
    }

    func saveCustomTokens() {
        persistence.saveCustomTokens(customTokens)
    }

    func saveNftContracts() {
        persistence.saveNftContracts(customNftContracts)
    }

    func saveActivities() {
        persistence.saveActivities(activities)
    }

    func saveGuardianStatus() {
        guardianManager.saveGuardianStatus()
    }

    func saveBridgeTransactions() {
        persistence.saveBridgeTransactions(bridgeTransactions)
    }

    // MARK: - PXE Log Management

    func appendPXELog(level: String, message: String) {
        let entry = PXELogEntry(timestamp: Date(), level: level, message: message)
        pxeLogs.append(entry)
        if pxeLogs.count > maxLogEntries {
            pxeLogs.removeFirst(pxeLogs.count - maxLogEntries)
        }
        // Extract deploy step from log messages
        if message.contains("Deploy Step") || message.contains("Step ") {
            if let range = message.range(of: #"(?:Deploy )?Step \d+[A-E]?:.*"#, options: .regularExpression) {
                deployStep = String(message[range])
            }
        }
    }

    func clearPXELogs() {
        pxeLogs.removeAll()
        deployStep = ""
    }

    // MARK: - Toast

    func showToast(_ message: String, type: Toast.ToastType = .success) {
        toast = Toast(message: message, type: type)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast?.message == message {
                toast = nil
            }
        }
    }

    // MARK: - Withdrawal Rate Limiting

    /// Daily withdrawal amount tracked via UserDefaults
    var dailyWithdrawalAmount: Double {
        get { persistence.dailyWithdrawalAmount }
        set { persistence.dailyWithdrawalAmount = newValue }
    }

    /// Date string (YYYY-MM-DD) of the current daily withdrawal tracking window
    var dailyWithdrawalDate: String {
        get { persistence.dailyWithdrawalDate }
        set { persistence.dailyWithdrawalDate = newValue }
    }

    /// Configurable daily withdrawal limit (persisted via UserDefaults)
    var dailyWithdrawalLimit: Double {
        get { persistence.dailyWithdrawalLimit }
        set { persistence.dailyWithdrawalLimit = newValue }
    }

    /// Threshold above which extra confirmation is required (persisted via UserDefaults)
    var largeTransactionThreshold: Double {
        get { persistence.largeTransactionThreshold }
        set { persistence.largeTransactionThreshold = newValue }
    }

    /// Remaining daily withdrawal allowance (resets at midnight)
    var remainingDailyLimit: Double {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if dailyWithdrawalDate != today {
            return dailyWithdrawalLimit
        }
        return max(0, dailyWithdrawalLimit - dailyWithdrawalAmount)
    }

    /// Record a successful withdrawal against the daily limit
    func recordWithdrawal(amount: Double) {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if dailyWithdrawalDate != today {
            dailyWithdrawalAmount = 0
            dailyWithdrawalDate = today
        }
        dailyWithdrawalAmount += amount
        walletLog.notice("[WalletStore] Withdrawal recorded: \(amount, privacy: .public), daily total: \(self.dailyWithdrawalAmount, privacy: .public)/\(self.dailyWithdrawalLimit, privacy: .public)")
    }

    // MARK: - Demo Mode

    func enterDemoMode() {
        let demo = Account(
            address: "0x" + (0..<40).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined(),
            type: .demo,
            label: "Demo Account",
            deployed: false
        )
        accounts = [demo]
        activeAccountIndex = 0
        tokens = Token.defaults
        activities = [
            Activity(type: .send, label: "Sent zkUSD", amount: "-50.00 zkUSD", isPrivate: true),
            Activity(type: .receive, label: "Received zkETH", amount: "+0.5 zkETH", isPrivate: true),
        ]
        saveAccounts()
        screen = .dashboard
    }
}
