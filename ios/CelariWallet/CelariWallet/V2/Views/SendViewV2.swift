import SwiftUI

struct SendViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var recipient = ""
    @State private var amount = ""
    @State private var selectedTokenIndex = 0
    @State private var isPrivate = true
    @State private var sending = false
    @State private var showTokenPicker = false
    @State private var showConfirmAlert = false

    private var selectedToken: Token? {
        guard !store.tokens.isEmpty, selectedTokenIndex < store.tokens.count else { return nil }
        return store.tokens[selectedTokenIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Send")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 20) {
                    // Token selector
                    Button { showTokenPicker = true } label: {
                        HStack {
                            HStack(spacing: 10) {
                                tokenIcon(for: selectedToken)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(selectedToken?.name ?? "Select Token")
                                        .font(V2Fonts.bodyMedium(15))
                                        .foregroundColor(V2Colors.textPrimary)
                                    Text("Balance: \(selectedToken?.balance ?? "0") \(selectedToken?.symbol ?? "")")
                                        .font(V2Fonts.mono(11))
                                        .foregroundColor(V2Colors.textTertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(V2Colors.textTertiary)
                        }
                        .cardStyle()
                    }

                    // Recipient
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECIPIENT")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        HStack {
                            TextField("0x...", text: $recipient)
                                .font(V2Fonts.mono(14))
                                .foregroundColor(V2Colors.textPrimary)
                            Button {
                                if let clip = UIPasteboard.general.string {
                                    recipient = clip
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Paste")
                                }
                                .font(V2Fonts.bodyMedium(12))
                                .foregroundColor(V2Colors.soBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(V2Colors.soBlue.opacity(0.1))
                                )
                            }
                        }
                        .cardStyle()
                    }

                    // Amount
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AMOUNT")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        VStack(spacing: 8) {
                            HStack {
                                TextField("0.00", text: $amount)
                                    .font(V2Fonts.monoBold(28))
                                    .foregroundColor(V2Colors.textPrimary)
                                    .keyboardType(.decimalPad)
                                Text(selectedToken?.symbol ?? "")
                                    .font(V2Fonts.monoSemibold(15))
                                    .foregroundColor(V2Colors.textTertiary)
                            }

                            HStack(spacing: 8) {
                                ForEach(["25%", "50%", "75%"], id: \.self) { pct in
                                    Button(pct) {
                                        applyPercent(pct)
                                    }
                                    .font(V2Fonts.bodyMedium(12))
                                    .foregroundColor(V2Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(V2Colors.bgControl)
                                    )
                                }
                                Button("MAX") {
                                    applyPercent("100%")
                                }
                                .font(V2Fonts.bodyMedium(12))
                                .foregroundColor(V2Colors.textWhite)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(V2Colors.soOrange)
                                )
                            }
                        }
                        .cardStyle()
                    }

                    // Privacy toggle
                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(isPrivate ? V2Colors.aztecGreen : V2Colors.textMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ZK-Shielded")
                                    .font(V2Fonts.bodyMedium(14))
                                    .foregroundColor(V2Colors.textPrimary)
                                Text(isPrivate ? "Private transaction via Aztec" : "Public transaction — visible on-chain")
                                    .font(V2Fonts.body(11))
                                    .foregroundColor(V2Colors.textTertiary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $isPrivate)
                            .tint(V2Colors.aztecGreen)
                            .labelsHidden()
                    }
                    .cardStyle()

                    // Fee row
                    HStack {
                        Text("Estimated Fee")
                            .font(V2Fonts.bodyMedium(13))
                            .foregroundColor(V2Colors.textSecondary)
                        Spacer()
                        Text("~0.002 ETH")
                            .font(V2Fonts.monoSemibold(13))
                            .foregroundColor(V2Colors.textPrimary)
                    }
                    .padding(.horizontal, 4)

                    // Send button
                    Button {
                        showConfirmAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            if sending {
                                ProgressView()
                                    .tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "arrow.up.right")
                                Text("Send \(amount.isEmpty ? "0" : amount) \(selectedToken?.symbol ?? "")")
                            }
                        }
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canSend ? V2Colors.soOrange : V2Colors.soOrange.opacity(0.4))
                        )
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(V2Colors.bgCanvas)
        .sheet(isPresented: $showTokenPicker) {
            tokenPickerSheet
        }
        .alert("Send \(amount) \(selectedToken?.symbol ?? "")?", isPresented: $showConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Send") { performSend() }
        } message: {
            Text("This may take 10-15 minutes for proof generation.")
        }
    }

    private var canSend: Bool {
        !sending && !amount.isEmpty && !recipient.isEmpty && selectedToken != nil
    }

    // MARK: - Token Picker Sheet

    private var tokenPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(store.tokens.enumerated()), id: \.element.id) { index, token in
                    Button {
                        selectedTokenIndex = index
                        showTokenPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            tokenIcon(for: token)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.name)
                                    .font(V2Fonts.bodyMedium(15))
                                    .foregroundColor(V2Colors.textPrimary)
                                Text(token.symbol)
                                    .font(V2Fonts.mono(11))
                                    .foregroundColor(V2Colors.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(token.balance)
                                    .font(V2Fonts.monoSemibold(14))
                                    .foregroundColor(V2Colors.textPrimary)
                                if selectedTokenIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(V2Colors.successGreen)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTokenPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func tokenIcon(for token: Token?) -> some View {
        let color: Color = {
            switch token?.symbol {
            case "zkETH": return Color(hex2: "627EEA")
            case "zkUSD": return Color(hex2: "F48225")
            case "ZKP": return V2Colors.tealAccent
            case "CLR": return V2Colors.soOrange
            default: return V2Colors.textTertiary
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay(
                Text(token?.icon ?? "?")
                    .font(V2Fonts.monoBold(14))
                    .foregroundColor(V2Colors.textWhite)
            )
    }

    private func applyPercent(_ pct: String) {
        guard let token = selectedToken,
              let bal = Double(token.balance.replacingOccurrences(of: ",", with: "")) else { return }
        let multiplier: Double = switch pct {
        case "25%": 0.25
        case "50%": 0.5
        case "75%": 0.75
        default: 1.0
        }
        let val = bal * multiplier
        amount = val < 0.001 && val > 0 ? String(format: "%.6f", val) : String(format: "%.3f", val)
    }

    private func performSend() {
        guard let token = selectedToken else { return }
        let symbol = token.symbol
        guard let tokenAddr = store.tokenAddresses[symbol] ?? token.contractAddress else {
            store.showToast("Token address not found for \(symbol)", type: .error)
            return
        }
        sending = true
        Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                sending = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                _ = try await pxeBridge.transfer(
                    to: recipient,
                    amount: amount,
                    tokenAddress: tokenAddr,
                    transferType: isPrivate ? "private" : "public"
                )
                store.showToast("Transfer sent!")
                await store.fetchBalances()
            } catch {
                store.showToast("Send failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

// MARK: - Card Style Modifier

private struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
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

extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}
