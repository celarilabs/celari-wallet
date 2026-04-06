import SwiftUI

struct HomeViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Binding var activeTab: V2Tab
    @State private var showProfile = false
    @State private var showShield = false
    @State private var showFaucetAlert = false
    @State private var showAddAccount = false
    @State private var showFeeJuice = false
    @AppStorage("alphaWarningDismissed") private var alphaWarningDismissed = false

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
                    // Alpha Network warning banner
                    if !alphaWarningDismissed {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(V2Colors.soOrange)

                            Text("Alpha Network — Experimental software. Do not deposit more than you are willing to lose.")
                                .font(V2Fonts.mono(11))
                                .foregroundColor(V2Colors.soOrange)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button {
                                withAnimation { alphaWarningDismissed = true }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(V2Colors.soOrange.opacity(0.7))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(V2Colors.soOrange.opacity(0.12)))
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.soOrange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(V2Colors.soOrange.opacity(0.25), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // PXE initialization error banner
                    if store.pxeInitFailed {
                        Button {
                            Task { await store.retryPXEInit() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(V2Colors.errorRed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PXE Engine Error")
                                        .font(V2Fonts.bodySemibold(13))
                                        .foregroundColor(V2Colors.errorRed)
                                    Text({
                                        if case .failed(let error) = store.pxeState { return error }
                                        return "Initialization failed"
                                    }())
                                        .font(V2Fonts.body(11))
                                        .foregroundColor(V2Colors.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text("Retry")
                                    .font(V2Fonts.label(10))
                                    .foregroundColor(V2Colors.textWhite)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(V2Colors.errorRed))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(V2Colors.errorRed.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(V2Colors.errorRed.opacity(0.25), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 24)
                    }

                    // Account selector (shown when multiple accounts exist)
                    if store.accounts.count > 1 {
                        AccountSelectorV2 {
                            showAddAccount = true
                        }
                    }

                    // Balance card
                    BalanceCardV2()
                        .padding(.horizontal, 24)

                    // Fee Juice banner — show for both deployed (no balance) and undeployed (needs faucet before deploy)
                    if let account = store.activeAccount,
                       !account.address.hasPrefix("pending_"),
                       (!account.deployed || store.feeJuiceBalance.isEmpty || store.feeJuiceBalance == "0") {
                        Button { showFeeJuice = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "fuelpump.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(V2Colors.warningOrange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.deployed ? "No Fee Juice" : "Get Fee Juice to Deploy")
                                        .font(V2Fonts.bodySemibold(13))
                                        .foregroundColor(V2Colors.warningOrange)
                                    Text(account.deployed ? "Fee Juice required — bridge from L1 or use faucet" : "Fee Juice is needed to deploy your account on-chain")
                                        .font(V2Fonts.body(11))
                                        .foregroundColor(V2Colors.textSecondary)
                                }
                                Spacer()
                                Text("Get Fee Juice")
                                    .font(V2Fonts.label(10))
                                    .foregroundColor(V2Colors.textWhite)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(V2Colors.soOrange)
                                    )
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(V2Colors.warningOrange.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(V2Colors.warningOrange.opacity(0.25), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 24)
                    }

                    // Backup reminder banner
                    if store.needsBackupReminder && !store.backupReminderDismissed {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.badge.clock")
                                .font(.system(size: 14))
                                .foregroundColor(V2Colors.soBlue)

                            Text("It's been a while since your last backup")
                                .font(V2Fonts.mono(11))
                                .foregroundColor(V2Colors.soBlue)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button {
                                showProfile = true
                            } label: {
                                Text("Backup Now")
                                    .font(V2Fonts.bodySemibold(11))
                                    .foregroundColor(V2Colors.textWhite)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(V2Colors.soBlue)
                                    )
                            }

                            Button {
                                withAnimation { store.backupReminderDismissed = true }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(V2Colors.soBlue.opacity(0.7))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(V2Colors.soBlue.opacity(0.12)))
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.soBlue.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(V2Colors.soBlue.opacity(0.25), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

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
                .padding(.bottom, 120)
            }
            .refreshable {
                await store.fetchBalances()
                await store.checkFeeJuiceBalance()
            }
        }
        .background(V2Colors.bgCanvas)
        .sheet(isPresented: $showProfile) {
            ProfileViewV2()
        }
        .sheet(isPresented: $showShield) {
            ShieldViewV2()
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountViewV2()
        }
        .sheet(isPresented: $showFeeJuice) {
            FeeJuiceBridgeViewV2()
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
