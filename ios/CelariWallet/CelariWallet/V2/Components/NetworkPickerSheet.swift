import SwiftUI

struct NetworkPickerSheet: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.connected ? V2Colors.successGreen : V2Colors.errorRed)
                        .frame(width: 10, height: 10)
                    Text(store.connected ? "Connected" : "Not Connected")
                        .font(V2Fonts.bodySemibold(14))
                        .foregroundColor(store.connected ? V2Colors.successGreen : V2Colors.errorRed)
                    Spacer()
                    if let info = store.nodeInfo {
                        Text("v\(info.nodeVersion ?? "?")")
                            .font(V2Fonts.mono(11))
                            .foregroundColor(V2Colors.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    (store.connected ? V2Colors.successGreen : V2Colors.errorRed).opacity(0.06)
                )

                // Network list
                VStack(spacing: 0) {
                    ForEach(NetworkPreset.allCases, id: \.self) { preset in
                        Button {
                            Task {
                                await store.switchNetwork(preset: preset)
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(colorForPreset(preset).opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: iconForPreset(preset))
                                        .font(.system(size: 16))
                                        .foregroundColor(colorForPreset(preset))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(preset.name)
                                            .font(V2Fonts.bodyMedium(15))
                                            .foregroundColor(V2Colors.textPrimary)
                                        if preset == .devnet {
                                            Text("FAUCET")
                                                .font(V2Fonts.label(8))
                                                .tracking(0.5)
                                                .foregroundColor(V2Colors.aztecGreen)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().fill(V2Colors.aztecGreen.opacity(0.12))
                                                )
                                        }
                                    }
                                    Text(preset.url)
                                        .font(V2Fonts.mono(10))
                                        .foregroundColor(V2Colors.textTertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if store.network == preset.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(V2Colors.successGreen)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }

                        if preset != NetworkPreset.allCases.last {
                            Divider()
                                .padding(.leading, 74)
                        }
                    }
                }
                .background(V2Colors.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Info note
                Text("Devnet has a faucet for free Fee Juice. Testnet may require bridging from L1.")
                    .font(V2Fonts.body(12))
                    .foregroundColor(V2Colors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer()
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Select Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(V2Colors.textSecondary)
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
        case .mainnet: return "shield.fill"
        }
    }

    private func colorForPreset(_ preset: NetworkPreset) -> Color {
        switch preset {
        case .local: return V2Colors.textTertiary
        case .devnet: return V2Colors.soOrange
        case .testnet: return V2Colors.aztecGreen
        case .mainnet: return V2Colors.soBlue
        }
    }
}
