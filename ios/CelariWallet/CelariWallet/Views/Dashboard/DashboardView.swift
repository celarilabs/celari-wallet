import SwiftUI

struct DashboardView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var activeTab: DashboardTab = .tokens
    @State private var showFaucetAlert = false
    @State private var savedBrightness: CGFloat = 0.5

    enum DashboardTab: String, CaseIterable {
        case tokens = "Tokens"
        case nfts = "NFTs"
        case activity = "Activity"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            ScrollView {
                VStack(spacing: 0) {
                    BalanceCardView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // In-app PXE log panel
                    if store.showLogs {
                        PXELogView()
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    AccountSelectorView()
                        .padding(.top, 8)

                    // Action buttons
                    HStack(spacing: 0) {
                        ActionButton(icon: "arrow.up.right", label: "Send") {
                            store.sendForm = SendForm() // Reset form on navigation (4.13 audit fix)
                            store.screen = .send
                        }
                        ActionButton(icon: "arrow.down.left", label: "Receive") {
                            store.screen = .receive
                        }
                        ActionButton(icon: "drop", label: "Faucet") {
                            showFaucetAlert = true
                        }
                        ActionButton(icon: "shield", label: "Shield") {
                            store.sendForm = SendForm()
                            store.sendForm.transferType = .shield
                            store.sendForm.to = store.activeAccount?.address ?? ""
                            store.screen = .send
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Tabs
                    HStack(spacing: 0) {
                        ForEach(DashboardTab.allCases, id: \.self) { tab in
                            Button {
                                activeTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(CelariTypography.monoLabel)
                                    .tracking(2)
                                    .foregroundColor(activeTab == tab ? CelariColors.copper : CelariColors.textDim)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .bottom) {
                                        if activeTab == tab {
                                            Rectangle()
                                                .fill(CelariColors.copper)
                                                .frame(height: 1)
                                        }
                                    }
                            }
                        }

                        Spacer()

                        if activeTab == .tokens {
                            Button {
                                store.screen = .addToken
                            } label: {
                                Text("+")
                                    .font(CelariTypography.mono)
                                    .foregroundColor(CelariColors.textDim)
                                    .padding(.horizontal, 8)
                            }
                        } else if activeTab == .nfts {
                            Button {
                                store.screen = .addNftContract
                            } label: {
                                Text("+")
                                    .font(CelariTypography.mono)
                                    .foregroundColor(CelariColors.textDim)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(CelariColors.border).frame(height: 1)
                    }

                    // Content
                    switch activeTab {
                    case .tokens:
                        TokenListView()
                    case .nfts:
                        NftListView()
                    case .activity:
                        ActivityListView()
                    }
                }
            }
            .refreshable {
                await store.fetchBalances()
            }
        }
        .alert("Request Faucet", isPresented: $showFaucetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Request") { requestFaucet() }
        } message: {
            Text("This may take 10-15 minutes for proof generation. Keep the screen on during this process — the screen will dim automatically to save battery.")
        }
        .task {
            await store.fetchBalances()
        }
    }

    private func requestFaucet() {
        guard let account = store.activeAccount else { return }
        store.showToast("Requesting faucet tokens...")
        // Dim screen to save battery while keeping it awake
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.1
        Task {
            // Keep screen awake during faucet (3 sequential proofs, ~15 min)
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                UIScreen.main.brightness = savedBrightness
            }
            do {
                let result = try await pxeBridge.faucet(address: account.address)

                // Auto-register CLR token so balances can be queried
                if let tokenAddress = result["tokenAddress"] as? String,
                   let symbol = result["symbol"] as? String,
                   !tokenAddress.isEmpty {
                    store.registerTokenIfNeeded(
                        contractAddress: tokenAddress,
                        name: symbol == "CLR" ? "Celari Token" : symbol,
                        symbol: symbol,
                        decimals: 18
                    )
                }

                store.showToast("Faucet tokens received!")
                await store.fetchBalances()
            } catch {
                store.showToast("Faucet failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
