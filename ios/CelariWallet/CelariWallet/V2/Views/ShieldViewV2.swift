import SwiftUI

struct ShieldViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss
    @State private var isShield = true
    @State private var amount = ""
    @State private var shielding = false
    @State private var selectedTokenIndex = 0
    @State private var showTokenPicker = false
    @State private var showConfirmAlert = false

    private var selectedToken: Token? {
        guard !store.tokens.isEmpty, selectedTokenIndex < store.tokens.count else { return nil }
        return store.tokens[selectedTokenIndex]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Shield / Unshield toggle
                    HStack(spacing: 0) {
                        toggleTab("Shield", icon: "shield.fill", isActive: isShield) {
                            isShield = true
                        }
                        toggleTab("Unshield", icon: "shield.slash.fill", isActive: !isShield) {
                            isShield = false
                        }
                    }
                    .frame(height: 44)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgControl)
                    )

                    // Hero card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [V2Colors.aztecGreen, V2Colors.tealAccent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            Image(systemName: isShield ? "shield.fill" : "shield.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(V2Colors.textWhite)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isShield ? "Private Transactions" : "Public Transactions")
                                .font(V2Fonts.bodySemibold(15))
                                .foregroundColor(V2Colors.textWhite)
                            Text(isShield
                                 ? "Move assets into Aztec's ZK-shielded pool for private transfers"
                                 : "Move shielded assets back to public balance")
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

                    // Token selector — real data
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

                    // Amount card
                    VStack(spacing: 10) {
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
                                Button(pct) { applyPercent(pct) }
                                    .font(V2Fonts.bodyMedium(12))
                                    .foregroundColor(V2Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(V2Colors.bgControl)
                                    )
                            }
                            Button("MAX") { applyPercent("100%") }
                                .font(V2Fonts.bodyMedium(12))
                                .foregroundColor(V2Colors.textWhite)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(V2Colors.soOrange)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .cardStyle()

                    // Privacy level
                    VStack(spacing: 10) {
                        HStack {
                            Text("Privacy Level")
                                .font(V2Fonts.bodyMedium(14))
                                .foregroundColor(V2Colors.textPrimary)
                            Spacer()
                            Text("Maximum")
                                .font(V2Fonts.label(10))
                                .foregroundColor(V2Colors.aztecGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(V2Colors.aztecGreen.opacity(0.15))
                                )
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(V2Colors.bgControl)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(V2Colors.shieldGradient)
                                    .frame(width: geo.size.width, height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack(spacing: 8) {
                            privacyStep("Deposit", active: true)
                            privacyStep("ZK Proof", active: true)
                            privacyStep("Shielded", active: true)
                        }
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

                    // Shield button
                    Button {
                        showConfirmAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            if shielding {
                                ProgressView().tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "shield.fill")
                                Text("\(isShield ? "Shield" : "Unshield") \(amount.isEmpty ? "0" : amount) \(selectedToken?.symbol ?? "")")
                            }
                        }
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(V2Colors.shieldGradient)
                                .opacity(amount.isEmpty ? 0.4 : 1.0)
                        )
                    }
                    .disabled(shielding || amount.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle(isShield ? "Shield" : "Unshield")
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
        .sheet(isPresented: $showTokenPicker) {
            tokenPickerSheet
        }
        .alert("\(isShield ? "Shield" : "Unshield") \(amount) \(selectedToken?.symbol ?? "")?", isPresented: $showConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") { performShield() }
        } message: {
            Text("This may take 10-15 minutes for proof generation.")
        }
    }

    // MARK: - Token Picker

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

    private func toggleTab(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(V2Fonts.bodySemibold(14))
            }
            .foregroundColor(isActive ? V2Colors.textWhite : V2Colors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? V2Colors.aztecDark : .clear)
            )
        }
    }

    private func privacyStep(_ label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? V2Colors.successGreen : V2Colors.textDisabled)
                .frame(width: 6, height: 6)
            Text(label)
                .font(V2Fonts.body(11))
                .foregroundColor(active ? V2Colors.textPrimary : V2Colors.textMuted)
        }
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

    private func performShield() {
        guard let account = store.activeAccount, let token = selectedToken else { return }
        let symbol = token.symbol
        guard let tokenAddr = store.tokenAddresses[symbol] ?? token.contractAddress else {
            store.showToast("No token address found for \(symbol)", type: .error)
            return
        }
        shielding = true
        Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                shielding = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                _ = try await pxeBridge.transfer(
                    to: account.address,
                    amount: amount,
                    tokenAddress: tokenAddr,
                    transferType: isShield ? "shield" : "unshield"
                )
                store.showToast("\(isShield ? "Shield" : "Unshield") complete!")
                await store.fetchBalances()
                dismiss()
            } catch {
                store.showToast("Failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
