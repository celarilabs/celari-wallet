import SwiftUI

struct ProfileViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showNetworkPicker = false

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

                        // Address
                        HStack(spacing: 8) {
                            Text(store.activeAccount?.shortAddress ?? "No address")
                                .font(V2Fonts.mono(14))
                                .foregroundColor(V2Colors.textWhite)
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

                    // Security section
                    settingsSection(title: "SECURITY") {
                        settingsRow(icon: "faceid", label: "Face ID", trailing: "toggle")
                        Divider().background(V2Colors.borderDivider)
                        settingsRow(icon: "key.fill", label: "Recovery Phrase", trailing: "chevron")
                        Divider().background(V2Colors.borderDivider)
                        settingsRow(icon: "link", label: "Connected Apps", trailing: "chevron")
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
                networkPickerSheet
            }
        }
    }

    // MARK: - Network Picker

    private var networkPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(NetworkPreset.allCases, id: \.self) { preset in
                    Button {
                        Task { await store.switchNetwork(preset: preset) }
                        showNetworkPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconForPreset(preset))
                                .font(.system(size: 20))
                                .foregroundColor(colorForPreset(preset))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(V2Fonts.bodyMedium(15))
                                    .foregroundColor(V2Colors.textPrimary)
                                Text(preset.url)
                                    .font(V2Fonts.mono(10))
                                    .foregroundColor(V2Colors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if store.network == preset.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(V2Colors.successGreen)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showNetworkPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func iconForPreset(_ preset: NetworkPreset) -> String {
        switch preset {
        case .local: return "desktopcomputer"
        case .devnet: return "hammer.fill"
        case .testnet: return "globe"
        }
    }

    private func colorForPreset(_ preset: NetworkPreset) -> Color {
        switch preset {
        case .local: return V2Colors.textTertiary
        case .devnet: return V2Colors.soOrange
        case .testnet: return V2Colors.aztecGreen
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
}
