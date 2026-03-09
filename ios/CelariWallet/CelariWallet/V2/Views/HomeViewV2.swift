import SwiftUI

struct HomeViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Binding var activeTab: V2Tab
    @State private var showProfile = false
    @State private var showShield = false
    @State private var showFaucetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Celari")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)

                Spacer()

                HStack(spacing: 16) {
                    // Log toggle button
                    Button { store.showLogs.toggle() } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 18))
                            .foregroundColor(store.showLogs ? V2Colors.soOrange : V2Colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(store.showLogs ? V2Colors.soOrange.opacity(0.1) : V2Colors.bgControl)
                            )
                    }

                    // Avatar button → Profile
                    Button { showProfile = true } label: {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(V2Colors.textWhite)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(V2Colors.aztecDark))
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            // PXE Log viewer
            if store.showLogs {
                PXELogViewV2()
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Balance card
                    BalanceCardV2()
                        .padding(.horizontal, 24)

                    // Action buttons
                    HStack(spacing: 20) {
                        ActionButtonV2(icon: "arrow.up.right", label: "Send") {
                            activeTab = .send
                        }
                        ActionButtonV2(icon: "arrow.down.left", label: "Receive") {
                            activeTab = .receive
                        }
                        ActionButtonV2(icon: "arrow.2.squarepath", label: "Swap") {}
                        ActionButtonV2(icon: "shield.fill", label: "Shield") {
                            showShield = true
                        }
                    }

                    // Assets section
                    VStack(spacing: 12) {
                        HStack {
                            Text("ASSETS")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)
                            Spacer()
                            Button("See All") {}
                                .font(V2Fonts.bodyMedium(13))
                                .foregroundColor(V2Colors.soBlue)
                        }
                        .padding(.horizontal, 24)

                        VStack(spacing: 0) {
                            ForEach(store.tokens) { token in
                                TokenRowV2(token: token)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                if token.id != store.tokens.last?.id {
                                    Divider()
                                        .background(V2Colors.borderDivider)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(V2Colors.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                    }

                    // Account status + actions
                    if let account = store.activeAccount {
                        VStack(spacing: 12) {
                            // Account address chip
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(account.deployed ? V2Colors.successGreen : V2Colors.warningOrange)
                                    .frame(width: 8, height: 8)
                                Text(account.shortAddress)
                                    .font(V2Fonts.mono(12))
                                    .foregroundColor(V2Colors.textSecondary)
                                Spacer()
                                Text(account.deployed ? "DEPLOYED" : "NOT DEPLOYED")
                                    .font(V2Fonts.label(10))
                                    .tracking(1)
                                    .foregroundColor(account.deployed ? V2Colors.successGreen : V2Colors.warningOrange)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(V2Colors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                    )
                            )

                            // Deploy button
                            if !account.deployed {
                                Button {
                                    Task { await store.deployActiveAccount(pxeBridge: pxeBridge) }
                                } label: {
                                    HStack(spacing: 8) {
                                        if store.deploying {
                                            ProgressView().tint(V2Colors.textWhite)
                                            Text("Deploying...")
                                        } else {
                                            Image(systemName: "bolt.fill")
                                            Text("Deploy Account")
                                        }
                                    }
                                    .font(V2Fonts.bodySemibold(16))
                                    .foregroundColor(V2Colors.textWhite)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(V2Colors.soOrange)
                                    )
                                }
                                .disabled(store.deploying)

                                if !store.deployStep.isEmpty {
                                    Text(store.deployStep)
                                        .font(V2Fonts.mono(11))
                                        .foregroundColor(V2Colors.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            // Faucet button
                            if account.deployed {
                                Button { showFaucetAlert = true } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "drop.fill")
                                        Text("Request Faucet")
                                    }
                                    .font(V2Fonts.bodySemibold(16))
                                    .foregroundColor(V2Colors.aztecDark)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(V2Colors.aztecGreen)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.fetchBalances()
            }
        }
        .background(V2Colors.bgCanvas)
        .sheet(isPresented: $showProfile) {
            ProfileViewV2()
        }
        .sheet(isPresented: $showShield) {
            ShieldViewV2()
        }
        .alert("Request Faucet", isPresented: $showFaucetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Request") { requestFaucet() }
        } message: {
            Text("This may take 10-15 minutes for proof generation.")
        }
        .task {
            await store.fetchBalances()
        }
    }

    private func requestFaucet() {
        guard let account = store.activeAccount else { return }
        store.showToast("Requesting faucet tokens...")
        Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let result = try await pxeBridge.faucet(address: account.address)
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
