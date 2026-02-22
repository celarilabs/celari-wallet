import SwiftUI

struct SettingsView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var customRpc: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Settings")

            ScrollView {
                VStack(spacing: 0) {
                    // Network section
                    settingsSection("NETWORK") {
                        VStack(spacing: 0) {
                            ForEach(NetworkPreset.allCases, id: \.self) { preset in
                                Button {
                                    Task {
                                        await store.switchNetwork(preset: preset)
                                        store.showToast(store.connected ? "\(preset.name) connected" : "\(preset.name) connecting...")
                                    }
                                } label: {
                                    HStack {
                                        Text(preset.name)
                                            .font(CelariTypography.monoSmall)
                                            .foregroundColor(store.network == preset.rawValue ? CelariColors.copper : CelariColors.textBody)

                                        Spacer()

                                        if store.network == preset.rawValue {
                                            DiamondShape()
                                                .fill(CelariColors.copper)
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(CelariColors.border).frame(height: 1)
                                    }
                                }
                            }

                            // Custom RPC
                            HStack(spacing: 8) {
                                TextField("Custom RPC URL", text: $customRpc)
                                    .font(CelariTypography.monoTiny)
                                    .foregroundColor(CelariColors.textWarm)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(CelariColors.bgInput)
                                    .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))

                                Button {
                                    guard !customRpc.isEmpty else { return }
                                    store.nodeUrl = customRpc
                                    store.network = "custom"
                                    store.saveConfig()
                                    store.showToast("Custom RPC set")
                                } label: {
                                    Text("SET")
                                        .font(CelariTypography.monoLabel)
                                        .foregroundColor(CelariColors.copper)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .overlay(Rectangle().stroke(CelariColors.copper.opacity(0.3), lineWidth: 1))
                                }
                            }
                            .padding(16)
                        }
                    }

                    // Account section
                    settingsSection("ACCOUNT") {
                        VStack(spacing: 0) {
                            settingsRow("Add Account") {
                                store.screen = .addAccount
                            }
                            settingsRow("Backup Wallet") {
                                store.screen = .backup
                            }
                            settingsRow("Restore Wallet") {
                                store.screen = .restore
                            }
                        }
                    }

                    // Tokens section
                    settingsSection("TOKENS") {
                        VStack(spacing: 0) {
                            settingsRow("Add Custom Token") {
                                store.screen = .addToken
                            }

                            if !store.customTokens.isEmpty {
                                ForEach(store.customTokens) { token in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(token.name)
                                                .font(CelariTypography.monoSmall)
                                                .foregroundColor(CelariColors.textBody)
                                            Text(token.symbol)
                                                .font(CelariTypography.monoTiny)
                                                .foregroundColor(CelariColors.textDim)
                                        }
                                        Spacer()
                                        Button {
                                            store.customTokens.removeAll { $0.contractAddress == token.contractAddress }
                                            store.saveCustomTokens()
                                            store.showToast("Token removed")
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                                .foregroundColor(CelariColors.red)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(CelariColors.border).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }

                    // Danger zone
                    if store.accounts.count > 0 && !store.isDemo {
                        settingsSection("DANGER ZONE") {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Text("Delete Current Account")
                                        .font(CelariTypography.monoSmall)
                                        .foregroundColor(CelariColors.red)
                                    Spacer()
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(CelariColors.red)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    // Info section
                    settingsSection("INFO") {
                        VStack(spacing: 0) {
                            infoRow("Version", "0.5.0")
                            infoRow("Network", store.network)
                            infoRow("Status", store.connected ? "Connected" : "Disconnected")
                            infoRow("Node URL", store.nodeUrl)
                            if let info = store.nodeInfo {
                                infoRow("Node Version", info.nodeVersion)
                            }
                        }
                    }
                }
            }
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteCurrentAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(store.activeAccount?.label ?? "this account")\"? This cannot be undone.")
        }
    }

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(CelariTypography.monoLabel)
                .tracking(3)
                .foregroundColor(CelariColors.textDim)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            content()
        }
    }

    private func settingsRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(CelariTypography.monoSmall)
                    .foregroundColor(CelariColors.textBody)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(CelariColors.textDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CelariColors.border).frame(height: 1)
            }
        }
    }

    private func deleteCurrentAccount() {
        store.deleteAccount(at: store.activeAccountIndex)
        store.showToast("Account deleted")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(CelariTypography.monoTiny)
                .foregroundColor(CelariColors.textDim)
            Spacer()
            Text(value)
                .font(CelariTypography.monoTiny)
                .foregroundColor(CelariColors.textBody)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
