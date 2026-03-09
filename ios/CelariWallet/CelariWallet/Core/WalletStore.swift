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

    var name: String {
        switch self {
        case .local: return "Local Sandbox"
        case .devnet: return "Aztec Devnet"
        case .testnet: return "Aztec Testnet"
        }
    }

    var url: String {
        switch self {
        case .local: return "http://localhost:8080"
        case .devnet: return "https://v4-devnet-2.aztec-labs.com/"
        case .testnet: return "https://rpc.testnet.aztec-labs.com/"
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

    // Connection
    var connected: Bool = false
    var network: String = "local"
    var nodeUrl: String = "http://localhost:8080"
    var nodeInfo: NodeInfo?

    // Accounts
    var accounts: [Account] = []
    var activeAccountIndex: Int = 0

    // Tokens
    var tokens: [Token] = []
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

    // Networks
    var customNetworks: [CustomNetwork] = []
    var deployServerUrl: String = ""

    // UI State
    var sendForm: SendForm = SendForm()
    var toast: Toast?
    var loading: Bool = false
    var deploying: Bool = false
    var pxeInitialized: Bool = false

    /// Live progress message from PXE operations (shown as bottom status bar)
    var progressMessage: String?

    // PXE Logs (in-app console)
    var pxeLogs: [PXELogEntry] = []
    var showLogs: Bool = false
    var deployStep: String = ""
    private let maxLogEntries = 200

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
    let networkManager = NetworkManager()
    let passkeyManager = PasskeyManager()
    weak var pxeBridge: PXEBridge?

    // MARK: - Initialization

    func initialize(pxeBridge: PXEBridge) async {
        self.pxeBridge = pxeBridge
        // Load persisted data
        loadFromStorage()
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
                walletLog.error("[WalletStore] PXE WebView failed to load after 30s, skipping init")
                return
            }
            walletLog.notice("[WalletStore] PXE bridge ready — sending PXE_INIT to \(self.nodeUrl, privacy: .public)")
            do {
                let result = try await pxeBridge.initPXE(nodeUrl: self.nodeUrl)
                self.pxeInitialized = true
                walletLog.notice("[WalletStore] PXE initialized: \(String(describing: result).prefix(200), privacy: .public)")

                // Restore PXE snapshot if available (preserves notes, contracts, tree data across restarts)
                if PXEPersistenceManager.hasSnapshot() {
                    walletLog.notice("[WalletStore] PXE snapshot found — restoring...")
                    do {
                        let json = try await PXEPersistenceManager.load()
                        try await pxeBridge.restoreSnapshot(json: json)
                        walletLog.notice("[WalletStore] PXE snapshot restored OK — \(json.count / 1024) KB")
                    } catch {
                        walletLog.error("[WalletStore] PXE snapshot restore failed: \(error.localizedDescription, privacy: .public) — continuing with fresh store")
                    }
                }

                if let account = self.activeAccount, account.deployed {
                    // Account already deployed — re-register with PXE (in-memory store is fresh)
                    walletLog.notice("[WalletStore] PXE ready, account deployed — re-registering with PXE")
                    await self.reRegisterAccount(pxeBridge: pxeBridge, account: account)
                    // Wait for PXE block sync to discover private notes (note sync needs a few seconds)
                    walletLog.notice("[WalletStore] Waiting 3s for PXE note sync...")
                    try? await Task.sleep(for: .seconds(3))
                    await self.fetchBalances()
                    // Save PXE snapshot so private notes persist across restarts
                    await self.savePXESnapshot()
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
            }
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
        } catch {
            walletLog.error("[WalletStore] PXE snapshot save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Network Connection

    func checkConnection() async {
        walletLog.notice("[WalletStore] checkConnection — nodeUrl: \(self.nodeUrl, privacy: .public)")
        let result = await networkManager.checkConnection(nodeUrl: nodeUrl)
        connected = result.connected
        nodeInfo = result.nodeInfo
        walletLog.notice("[WalletStore] checkConnection — connected: \(self.connected, privacy: .public), nodeVersion: \(self.nodeInfo?.nodeVersion ?? "nil", privacy: .public)")
    }

    func switchNetwork(preset: NetworkPreset) async {
        network = preset.rawValue
        nodeUrl = preset.url
        saveConfig()
        await checkConnection()
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

        // 3. Create account entry
        let account = Account(
            address: "0x" + String(repeating: "0", count: 40) + "_pending",
            credentialId: passkeyResult.credentialId,
            publicKeyX: pubKeyX,
            publicKeyY: pubKeyY,
            type: .passkey,
            label: accounts.isEmpty ? "Main Wallet" : accountLabel
        )

        accounts.append(account)
        activeAccountIndex = accounts.count - 1
        saveAccounts()
        walletLog.notice("[WalletStore] Account entry saved — label: \(account.label, privacy: .public), index: \(self.activeAccountIndex, privacy: .public)")

        // 4. Store PKCS8 private key in Keychain for future deploy/signing
        try KeychainManager.saveAccountKeys(
            address: account.address,
            secretKey: nil,
            privateKeyPkcs8: pkcs8Base64,
            salt: nil
        )
        walletLog.notice("[WalletStore] PKCS8 key saved to Keychain")

        // NOTE: PXE_GENERATE_KEYS removed — iOS generates P-256 keys natively (CryptoKit).
        // The JS generateP256KeyPairBrowser() was redundant and caused AbortError when called
        // during PXE_INIT (IndexedDB transaction conflict in WKWebView single-threaded JS).
        // secretKey and salt are generated during deploy (deployAccountClientSide → Fr.random()).
        walletLog.notice("[WalletStore] Using native P-256 keys — secretKey/salt will be generated during deploy")

        tokens = Token.defaults
        screen = .dashboard
        showToast("Passkey wallet created!")
        walletLog.notice("[WalletStore] Account creation complete — navigated to dashboard")

        walletLog.notice("[WalletStore] Account ready — user can deploy from dashboard")
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

            walletLog.notice("[WalletStore] Calling PXE deployAccount — pubKeyX: \(pubKeyX.prefix(20), privacy: .public)...")

            let result = try await pxeBridge.deployAccount(pubKeyX: pubKeyX, pubKeyY: pubKeyY, pkcs8: pkcs8)
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
                accounts[activeAccountIndex].deployed = true
                saveAccounts()
                walletLog.warning("[WalletStore] Deploy returned without address: \(String(describing: result).prefix(200), privacy: .public)")
                showToast("Account deployed!")
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

    private let accountsKey = "celari_accounts"
    private let configKey = "celari_config"
    private let customTokensKey = "celari_custom_tokens"
    private let customNetworksKey = "celari_custom_networks"
    private let nftContractsKey = "celari_custom_nft_contracts"
    private let activitiesKey = "celari_activities"

    func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: customTokensKey),
           let decoded = try? JSONDecoder().decode([CustomToken].self, from: data) {
            customTokens = decoded
        }
        if let data = UserDefaults.standard.data(forKey: customNetworksKey),
           let decoded = try? JSONDecoder().decode([CustomNetwork].self, from: data) {
            customNetworks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: nftContractsKey),
           let decoded = try? JSONDecoder().decode([NFTContract].self, from: data) {
            customNftContracts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: activitiesKey),
           let decoded = try? JSONDecoder().decode([Activity].self, from: data) {
            activities = decoded
        }
        if let config = UserDefaults.standard.dictionary(forKey: configKey) {
            network = config["network"] as? String ?? network
            nodeUrl = config["nodeUrl"] as? String ?? nodeUrl
        }
    }

    func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    func saveConfig() {
        UserDefaults.standard.set(["network": network, "nodeUrl": nodeUrl], forKey: configKey)
    }

    func saveCustomTokens() {
        if let data = try? JSONEncoder().encode(customTokens) {
            UserDefaults.standard.set(data, forKey: customTokensKey)
        }
    }

    func saveNftContracts() {
        if let data = try? JSONEncoder().encode(customNftContracts) {
            UserDefaults.standard.set(data, forKey: nftContractsKey)
        }
    }

    func saveActivities() {
        if let data = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(data, forKey: activitiesKey)
        }
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
