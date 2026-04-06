import SwiftUI

struct BridgeViewV2: View {
    @Environment(WalletStore.self) private var store

    enum BridgeDirection: String, CaseIterable {
        case deposit = "Deposit"
        case withdraw = "Withdraw"
    }

    private let bridgeTokens = ["ETH", "USDC", "Fee Juice"]

    @State private var direction: BridgeDirection = .deposit
    @State private var selectedTokenIndex = 0
    @State private var amount = ""
    @State private var l1Address = ""
    @State private var isBridging = false
    @State private var resultMessage: String? = nil

    private var selectedToken: String {
        bridgeTokens[selectedTokenIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bridge")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 20) {

                    // Deposit / Withdraw selector
                    HStack(spacing: 0) {
                        ForEach(BridgeDirection.allCases, id: \.self) { dir in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    direction = dir
                                    resultMessage = nil
                                }
                            } label: {
                                Text(dir.rawValue)
                                    .font(V2Fonts.bodyMedium(14))
                                    .foregroundColor(direction == dir ? V2Colors.aztecGreen : V2Colors.textMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(direction == dir ? V2Colors.aztecDark : .clear)
                                    )
                            }
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    // Token selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOKEN")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        HStack(spacing: 0) {
                            ForEach(bridgeTokens.indices, id: \.self) { idx in
                                Button {
                                    selectedTokenIndex = idx
                                } label: {
                                    Text(bridgeTokens[idx])
                                        .font(V2Fonts.bodyMedium(13))
                                        .foregroundColor(selectedTokenIndex == idx ? V2Colors.textPrimary : V2Colors.textMuted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(selectedTokenIndex == idx ? V2Colors.aztecDark : .clear)
                                        )
                                }
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(V2Colors.bgCanvas)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                )
                        )
                    }

                    // Amount input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AMOUNT")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        HStack {
                            TextField("0.00", text: $amount)
                                .font(V2Fonts.mono(16))
                                .foregroundColor(V2Colors.textPrimary)
                                .keyboardType(.decimalPad)
                            Text(selectedToken)
                                .font(V2Fonts.bodyMedium(14))
                                .foregroundColor(V2Colors.textSecondary)
                        }
                        .cardStyle()
                    }

                    // L1 address input (withdraw only)
                    if direction == .withdraw {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("L1 RECIPIENT ADDRESS")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)

                            HStack {
                                TextField("0x...", text: $l1Address)
                                    .font(V2Fonts.mono(14))
                                    .foregroundColor(V2Colors.textPrimary)
                                Button {
                                    if let clip = UIPasteboard.general.string {
                                        l1Address = clip
                                    }
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(V2Colors.textTertiary)
                                }
                            }
                            .cardStyle()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Result message
                    if let msg = resultMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(V2Colors.aztecGreen)
                            Text(msg)
                                .font(V2Fonts.bodyMedium(13))
                                .foregroundColor(V2Colors.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(V2Colors.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                )
                        )
                    }

                    // Action button
                    Button {
                        executeBridge()
                    } label: {
                        HStack(spacing: 8) {
                            if isBridging {
                                ProgressView()
                                    .tint(V2Colors.bgCanvas)
                                    .scaleEffect(0.85)
                            }
                            Text(isBridging ? "Processing..." : actionLabel)
                                .font(V2Fonts.bodyMedium(16))
                                .foregroundColor(V2Colors.bgCanvas)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canBridge ? V2Colors.aztecGreen : V2Colors.textMuted)
                        )
                    }
                    .disabled(!canBridge || isBridging)

                    // Transaction history
                    if !store.bridgeTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RECENT BRIDGE ACTIVITY")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)

                            ForEach(store.bridgeTransactions.prefix(10)) { tx in
                                BridgeTxRowV2(tx: tx)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Helpers

    private var actionLabel: String {
        direction == .deposit ? "Deposit to Aztec" : "Withdraw to L1"
    }

    private var canBridge: Bool {
        let amountOk = (Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0) > 0
        let addressOk = direction == .deposit || !l1Address.trimmingCharacters(in: .whitespaces).isEmpty
        return amountOk && addressOk
    }

    private func executeBridge() {
        guard canBridge else { return }
        isBridging = true
        resultMessage = nil

        // Placeholder: create a pending BridgeTransaction entry
        let tx = BridgeTransaction(
            id: UUID(),
            type: direction == .deposit ? .deposit : .withdraw,
            token: selectedToken,
            amount: amount,
            status: .pending,
            l1TxHash: nil,
            l2TxHash: nil,
            timestamp: Date()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            store.bridgeTransactions.insert(tx, at: 0)
            store.saveBridgeTransactions()
            isBridging = false
            resultMessage = direction == .deposit
                ? "Deposit queued. Funds will appear on Aztec after L1 confirmation."
                : "Withdraw queued. Funds will arrive on L1 after proof generation."
        }
    }
}

// MARK: - Bridge Transaction Row

private struct BridgeTxRowV2: View {
    let tx: BridgeTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.type == .deposit ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(tx.type == .deposit ? V2Colors.aztecGreen : V2Colors.soOrange)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tx.type == .deposit ? "Deposit" : "Withdraw")
                        .font(V2Fonts.bodyMedium(14))
                        .foregroundColor(V2Colors.textPrimary)
                    Text(tx.token)
                        .font(V2Fonts.mono(12))
                        .foregroundColor(V2Colors.textSecondary)
                }
                Text(statusLabel(for: tx.status))
                    .font(V2Fonts.mono(11))
                    .foregroundColor(statusColor(for: tx.status))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount)
                    .font(V2Fonts.mono(14))
                    .foregroundColor(V2Colors.textPrimary)
                Text(tx.timestamp, style: .relative)
                    .font(V2Fonts.mono(11))
                    .foregroundColor(V2Colors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .cardStyle()
    }

    private func statusLabel(for status: BridgeTransaction.BridgeStatus) -> String {
        switch status {
        case .pending:      return "Pending"
        case .l1Confirmed:  return "L1 Confirmed"
        case .l2Claimed:    return "Claimed on L2"
        case .failed:       return "Failed"
        }
    }

    private func statusColor(for status: BridgeTransaction.BridgeStatus) -> Color {
        switch status {
        case .pending:      return V2Colors.textMuted
        case .l1Confirmed:  return V2Colors.soOrange
        case .l2Claimed:    return V2Colors.aztecGreen
        case .failed:       return V2Colors.errorRed
        }
    }
}
