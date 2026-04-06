import SwiftUI

struct ProfileViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss
    @State private var showNetworkPicker = false
    @State private var showGuardianSetup = false
    @State private var showBackup = false
    @State private var showRestore = false
    @State private var showAddAccount = false
    @State private var showTransactionLimits = false
    @State private var showProverBenchmark = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile card
                    VStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [V2Colors.aztecGreen, V2Colors.tealAccent],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 64, height: 64)
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(V2Colors.textWhite)
                        }

                        // Account label
                        if let account = store.activeAccount {
                            Text(account.label)
                                .font(V2Fonts.bodyMedium(16))
                                .foregroundColor(V2Colors.textWhite)
                        }

                        // Address
                        HStack(spacing: 8) {
                            Text(store.activeAccount?.shortAddress ?? "No address")
                                .font(V2Fonts.mono(14))
                                .foregroundColor(V2Colors.textWhite.opacity(0.7))
                            Button {
                                UIPasteboard.general.string = store.activeAccount?.address
                                store.showToast("Address copied!")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(V2Colors.textWhite.opacity(0.6))
                            }
                        }

                        // Network badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(V2Colors.aztecGreen)
                                .frame(width: 6, height: 6)
                            Text(networkLabel)
                                .font(V2Fonts.label(10))
                                .foregroundColor(V2Colors.aztecGreen)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color(hex2: "2A3D52"))
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.aztecDark)
                    )

                    // Account section
                    settingsSection(title: "ACCOUNT") {
                        settingsButton(icon: "person.badge.plus", label: "Add Account") {
                            showAddAccount = true
                        }
                        Divider().background(V2Colors.borderDivider)
                        settingsButton(icon: "square.and.arrow.up", label: "Backup Wallet") {
                            showBackup = true
                        }
                        Divider().background(V2Colors.borderDivider)
                        settingsButton(icon: "arrow.down.doc", label: "Restore Wallet") {
                            showRestore = true
                        }
                    }

                    // Security section
                    settingsSection(title: "SECURITY") {
                        settingsRow(icon: "faceid", label: "Face ID", trailing: "toggle")
                        Divider().background(V2Colors.borderDivider)
                        settingsButton(icon: "shield.checkered", label: "Guardian Recovery") {
                            showGuardianSetup = true
                        }
                        Divider().background(V2Colors.borderDivider)
                        settingsButton(icon: "gauge.with.dots.needle.33percent", label: "Transaction Limits") {
                            showTransactionLimits = true
                        }
                    }

                    // Network section
                    settingsSection(title: "NETWORK") {
                        Button { showNetworkPicker = true } label: {
                            HStack {
                                Image(systemName: "network")
                                    .font(.system(size: 18))
                                    .foregroundColor(V2Colors.textSecondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Network")
                                        .font(V2Fonts.bodyMedium(15))
                                        .foregroundColor(V2Colors.textPrimary)
                                    Text(store.nodeUrl)
                                        .font(V2Fonts.mono(10))
                                        .foregroundColor(V2Colors.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(networkLabel)
                                    .font(V2Fonts.label(11))
                                    .foregroundColor(V2Colors.aztecGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(V2Colors.aztecGreen.opacity(0.12))
                                    )
                            }
                            .padding(.vertical, 12)
                        }
                        Divider().background(V2Colors.borderDivider)
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 18))
                                .foregroundColor(V2Colors.textSecondary)
                                .frame(width: 28)
                            Text("Connection")
                                .font(V2Fonts.bodyMedium(15))
                                .foregroundColor(V2Colors.textPrimary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(store.connected ? V2Colors.successGreen : V2Colors.errorRed)
                                    .frame(width: 8, height: 8)
                                Text(store.connected ? "Connected" : "Disconnected")
                                    .font(V2Fonts.mono(12))
                                    .foregroundColor(store.connected ? V2Colors.successGreen : V2Colors.errorRed)
                            }
                        }
                        .padding(.vertical, 12)
                    }

                    // Network version change warning
                    if store.networkVersionChanged {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(V2Colors.soOrange)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Network version changed. State may not have been migrated. Please verify your balances and backup your wallet.")
                                    .font(V2Fonts.body(13))
                                    .foregroundColor(V2Colors.soOrange)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button {
                                    withAnimation { store.acknowledgeNetworkVersion() }
                                } label: {
                                    Text("Dismiss")
                                        .font(V2Fonts.bodySemibold(13))
                                        .foregroundColor(V2Colors.textWhite)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(V2Colors.soOrange)
                                        )
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.soOrange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(V2Colors.soOrange.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }

                    // Developer section
                    settingsSection(title: "DEVELOPER") {
                        settingsButton(icon: "bolt.fill", label: "Native Prover Benchmark") {
                            showProverBenchmark = true
                        }
                    }

                    // About section
                    settingsSection(title: "ABOUT") {
                        settingsRow(icon: "info.circle", label: "Version", trailing: "0.5.0")
                        Divider().background(V2Colors.borderDivider)
                        settingsRow(icon: "cube.fill", label: "Node", trailing: store.nodeInfo?.nodeVersion ?? "—")
                    }

                    // Disconnect button
                    Button {
                        store.deleteAccount(at: store.activeAccountIndex)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Disconnect Wallet")
                        }
                        .font(V2Fonts.bodySemibold(15))
                        .foregroundColor(V2Colors.errorRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex2: "FEF2F2"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex2: "FECACA"), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(V2Colors.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showNetworkPicker) {
                NetworkPickerSheet()
            }
            .sheet(isPresented: $showGuardianSetup) {
                GuardianSetupViewV2()
            }
            .sheet(isPresented: $showBackup) {
                BackupViewV2()
            }
            .sheet(isPresented: $showRestore) {
                RestoreViewV2()
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountViewV2()
            }
            .sheet(isPresented: $showTransactionLimits) {
                TransactionLimitsSheet()
            }
            .sheet(isPresented: $showProverBenchmark) {
                NavigationStack {
                    ProverBenchmarkView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showProverBenchmark = false }
                                    .foregroundColor(V2Colors.textSecondary)
                            }
                        }
                }
            }
        }
    }

    private var networkLabel: String {
        switch store.network {
        case "devnet": return "Aztec Devnet"
        case "testnet": return "Aztec Testnet"
        default: return "Local Sandbox"
        }
    }

    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.textTertiary)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(V2Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                    )
            )
        }
    }

    private func settingsRow(icon: String, label: String, trailing: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(V2Colors.textSecondary)
                .frame(width: 28)
            Text(label)
                .font(V2Fonts.bodyMedium(15))
                .foregroundColor(V2Colors.textPrimary)
            Spacer()
            if trailing == "chevron" {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(V2Colors.textDisabled)
            } else if trailing == "toggle" {
                Toggle("", isOn: .constant(true))
                    .tint(V2Colors.soBlue)
                    .labelsHidden()
            } else {
                Text(trailing)
                    .font(V2Fonts.mono(13))
                    .foregroundColor(V2Colors.textTertiary)
            }
        }
        .padding(.vertical, 12)
    }

    private func settingsButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(V2Colors.textSecondary)
                    .frame(width: 28)
                Text(label)
                    .font(V2Fonts.bodyMedium(15))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(V2Colors.textDisabled)
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Transaction Limits Sheet

struct TransactionLimitsSheet: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var dailyLimit: Double = 1000
    @State private var largeThreshold: Double = 100

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Daily withdrawal limit
                VStack(alignment: .leading, spacing: 12) {
                    Text("DAILY WITHDRAWAL LIMIT")
                        .font(V2Fonts.label(11))
                        .tracking(2)
                        .foregroundColor(V2Colors.textTertiary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(String(format: "%.0f", dailyLimit))
                                .font(V2Fonts.monoBold(28))
                                .foregroundColor(V2Colors.textPrimary)
                            Spacer()
                            Text("tokens/day")
                                .font(V2Fonts.mono(13))
                                .foregroundColor(V2Colors.textTertiary)
                        }
                        Slider(value: $dailyLimit, in: 100...10000, step: 100)
                            .tint(V2Colors.soOrange)
                        HStack {
                            Text("100")
                                .font(V2Fonts.mono(10))
                                .foregroundColor(V2Colors.textMuted)
                            Spacer()
                            Text("10,000")
                                .font(V2Fonts.mono(10))
                                .foregroundColor(V2Colors.textMuted)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    Text("Maximum total amount you can send in a 24-hour period. Resets daily.")
                        .font(V2Fonts.body(12))
                        .foregroundColor(V2Colors.textTertiary)
                }

                // Large transaction threshold
                VStack(alignment: .leading, spacing: 12) {
                    Text("LARGE TRANSACTION THRESHOLD")
                        .font(V2Fonts.label(11))
                        .tracking(2)
                        .foregroundColor(V2Colors.textTertiary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(String(format: "%.0f", largeThreshold))
                                .font(V2Fonts.monoBold(28))
                                .foregroundColor(V2Colors.textPrimary)
                            Spacer()
                            Text("tokens")
                                .font(V2Fonts.mono(13))
                                .foregroundColor(V2Colors.textTertiary)
                        }
                        Slider(value: $largeThreshold, in: 10...1000, step: 10)
                            .tint(V2Colors.soBlue)
                        HStack {
                            Text("10")
                                .font(V2Fonts.mono(10))
                                .foregroundColor(V2Colors.textMuted)
                            Spacer()
                            Text("1,000")
                                .font(V2Fonts.mono(10))
                                .foregroundColor(V2Colors.textMuted)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    Text("Transactions above this amount require an extra confirmation step.")
                        .font(V2Fonts.body(12))
                        .foregroundColor(V2Colors.textTertiary)
                }

                Spacer()

                // Save button
                Button {
                    store.dailyWithdrawalLimit = dailyLimit
                    store.largeTransactionThreshold = largeThreshold
                    store.showToast("Transaction limits saved")
                    dismiss()
                } label: {
                    Text("Save Limits")
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(V2Colors.soOrange)
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(V2Colors.bgCanvas)
            .navigationTitle("Transaction Limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(V2Colors.textTertiary)
                }
            }
            .onAppear {
                dailyLimit = store.dailyWithdrawalLimit
                largeThreshold = store.largeTransactionThreshold
            }
        }
        .presentationDetents([.medium])
    }
}
