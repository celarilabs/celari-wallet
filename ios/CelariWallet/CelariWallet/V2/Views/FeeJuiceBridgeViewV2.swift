import SwiftUI

struct FeeJuiceBridgeViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(V2Colors.soOrange)
                                .frame(width: 44, height: 44)
                            Image(systemName: "fuelpump.fill")
                                .font(.system(size: 20))
                                .foregroundColor(V2Colors.textWhite)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fee Juice")
                                .font(V2Fonts.bodySemibold(15))
                                .foregroundColor(V2Colors.textWhite)
                            Text("Required to pay for transactions on Aztec")
                                .font(V2Fonts.body(12))
                                .foregroundColor(V2Colors.textWhite.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.aztecDark)
                    )

                    // Current balance card
                    VStack(spacing: 8) {
                        Text("CURRENT BALANCE")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        Text(formattedBalance)
                            .font(V2Fonts.monoBold(28))
                            .foregroundColor(balanceColor)

                        Text("Fee Juice")
                            .font(V2Fonts.mono(13))
                            .foregroundColor(V2Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    // One-tap faucet button
                    Button {
                        Task { await store.requestFaucetDrip() }
                    } label: {
                        HStack(spacing: 10) {
                            if store.faucetRequesting {
                                ProgressView().tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "drop.fill")
                            }
                            Text(store.faucetRequesting ? "Requesting..." : "Request Fee Juice from Faucet")
                        }
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(hasPendingAddress ? V2Colors.textDisabled : V2Colors.soOrange)
                        )
                    }
                    .disabled(store.faucetRequesting || hasPendingAddress)

                    // Faucet progress status
                    if !store.faucetStatus.isEmpty {
                        let isReady = store.faucetClaimData != nil
                        let isFailed = store.faucetStatus.contains("Failed")
                        let statusColor = isReady ? V2Colors.successGreen : (isFailed ? V2Colors.errorRed : V2Colors.soOrange)
                        let statusIcon = isReady ? "checkmark.circle.fill" : (isFailed ? "xmark.circle.fill" : "arrow.triangle.2.circlepath")

                        HStack(spacing: 10) {
                            if !isReady && !isFailed {
                                ProgressView()
                                    .tint(statusColor)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: statusIcon)
                                    .foregroundColor(statusColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.faucetStatus)
                                    .font(V2Fonts.bodySemibold(13))
                                    .foregroundColor(statusColor)
                                if isReady {
                                    Text("Will be used automatically during account deploy")
                                        .font(V2Fonts.mono(10))
                                        .foregroundColor(V2Colors.textSecondary)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(statusColor.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(statusColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }

                    // Claim data details
                    if let cd = store.faucetClaimData {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CLAIM DATA")
                                .font(V2Fonts.label(10))
                                .tracking(1)
                                .foregroundColor(V2Colors.textTertiary)

                            claimRow(label: "Amount", value: formatClaimAmount(cd["claimAmount"] ?? "0"))
                            claimRow(label: "Leaf Index", value: cd["messageLeafIndex"] ?? "—")
                            claimRow(label: "Secret", value: String((cd["claimSecret"] ?? "—").prefix(18)) + "...")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                )
                        )
                    }

                    // How it works — network-aware instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HOW IT WORKS")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        if isDevnetOrTestnet {
                            stepRow(number: "1", title: "Request", description: "Tap the button above to request Fee Juice from the faucet.")
                            stepRow(number: "2", title: "Bridge", description: "The faucet bridges Fee Juice from L1 to your L2 address (~1-2 minutes).")
                            stepRow(number: "3", title: "Deploy / Send", description: "Go back — Fee Juice is used to pay for transactions and deployments.")
                        } else {
                            stepRow(number: "1", title: "Bridge from L1", description: "Use an Ethereum L1 bridge to send Fee Juice to your Aztec L2 address.")
                            stepRow(number: "2", title: "Wait", description: "Bridging takes ~10-15 minutes for L1 confirmation.")
                            stepRow(number: "3", title: "Transact", description: "Once bridged, Fee Juice is used to pay for all transactions on Aztec.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    // Your address
                    if let account = store.activeAccount, !account.address.hasPrefix("pending_") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR AZTEC ADDRESS")
                                .font(V2Fonts.label(10))
                                .tracking(1)
                                .foregroundColor(V2Colors.textTertiary)

                            Button {
                                UIPasteboard.general.string = account.address
                                store.showToast("Address copied!")
                            } label: {
                                HStack {
                                    Text(account.address)
                                        .font(V2Fonts.mono(10))
                                        .foregroundColor(V2Colors.textPrimary)
                                        .lineLimit(2)
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundColor(V2Colors.textSecondary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(V2Colors.bgControl)
                                )
                            }
                        }
                    }

                    // Rate limit note
                    Text("Rate limited to 1 request per 24 hours. Faucet provided by Nethermind.")
                        .font(V2Fonts.body(11))
                        .foregroundColor(V2Colors.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Fee Juice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(V2Colors.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var hasPendingAddress: Bool {
        guard let account = store.activeAccount else { return true }
        return account.address.hasPrefix("pending_") || account.address.isEmpty
    }

    private var isDevnetOrTestnet: Bool {
        let network = store.network.lowercased()
        return network.contains("devnet") || network.contains("testnet") || network.contains("local")
    }

    private var formattedBalance: String {
        let raw = store.feeJuiceBalance
        if raw.isEmpty || raw == "0" { return "0" }
        return raw
    }

    private var balanceColor: Color {
        let raw = store.feeJuiceBalance
        if raw.isEmpty || raw == "0" {
            return V2Colors.errorRed
        }
        return V2Colors.successGreen
    }

    private func claimRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(V2Fonts.label(11))
                .foregroundColor(V2Colors.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(V2Fonts.mono(11))
                .foregroundColor(V2Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Button {
                UIPasteboard.general.string = value
                store.showToast("Copied!")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(V2Colors.textTertiary)
            }
        }
    }

    private func formatClaimAmount(_ raw: String) -> String {
        guard let bigVal = Double(raw) else { return raw }
        let formatted = bigVal / 1e18
        return String(format: "%.0f Fee Juice", formatted)
    }

    private func stepRow(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(V2Fonts.monoSemibold(13))
                .foregroundColor(V2Colors.textWhite)
                .frame(width: 26, height: 26)
                .background(Circle().fill(V2Colors.soOrange))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(V2Fonts.bodySemibold(14))
                    .foregroundColor(V2Colors.textPrimary)
                Text(description)
                    .font(V2Fonts.body(13))
                    .foregroundColor(V2Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
