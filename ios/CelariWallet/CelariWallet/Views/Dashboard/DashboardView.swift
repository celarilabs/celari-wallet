import SwiftUI

struct DashboardView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var activeTab: DashboardTab = .tokens

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

                    AccountSelectorView()
                        .padding(.top, 8)

                    // Action buttons
                    HStack(spacing: 0) {
                        ActionButton(icon: "arrow.up.right", label: "Send") {
                            store.screen = .send
                        }
                        ActionButton(icon: "arrow.down.left", label: "Receive") {
                            store.screen = .receive
                        }
                        ActionButton(icon: "drop", label: "Faucet") {
                            requestFaucet()
                        }
                        ActionButton(icon: "shield", label: "Shield") {
                            store.sendForm.transferType = .shield
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

                        Button {
                            store.screen = .addToken
                        } label: {
                            Text("+")
                                .font(CelariTypography.mono)
                                .foregroundColor(CelariColors.textDim)
                                .padding(.horizontal, 8)
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
        .task {
            await store.fetchBalances()
        }
    }

    private func requestFaucet() {
        guard let account = store.activeAccount else { return }
        store.showToast("Requesting faucet tokens...")
        Task {
            do {
                _ = try await pxeBridge.faucet(address: account.address)
                store.showToast("Faucet tokens received!")
                await store.fetchBalances()
            } catch {
                store.showToast("Faucet failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
