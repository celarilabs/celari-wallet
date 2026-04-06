import SwiftUI

struct SwapViewV2: View {
    @Environment(WalletStore.self) private var store

    private let availableTokens = ["ETH", "USDC", "WBTC", "Fee Juice"]

    private let slippageOptions = ["0.5%", "1%", "2%"]

    @State private var fromTokenIndex = 0
    @State private var toTokenIndex = 1
    @State private var amount = ""
    @State private var selectedSlippageIndex = 0
    @State private var isSwapping = false

    private var fromToken: String { availableTokens[fromTokenIndex] }
    private var toToken: String { availableTokens[toTokenIndex] }

    // Hardcoded placeholder quote values
    private var estimatedOutput: String {
        guard let input = Double(amount.replacingOccurrences(of: ",", with: "")), input > 0 else {
            return "—"
        }
        return String(format: "%.4f", input * 0.9972)
    }

    private var priceImpact: String { "< 0.01%" }
    private var minimumReceived: String {
        guard let input = Double(amount.replacingOccurrences(of: ",", with: "")), input > 0 else {
            return "—"
        }
        let slippage: Double
        switch selectedSlippageIndex {
        case 0: slippage = 0.005
        case 1: slippage = 0.01
        default: slippage = 0.02
        }
        return String(format: "%.4f \(toToken)", input * 0.9972 * (1 - slippage))
    }

    private var canSwap: Bool {
        let amountOk = (Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0) > 0
        return amountOk && fromTokenIndex != toTokenIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Swap")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 20) {

                    // Token pair selector
                    VStack(spacing: 0) {
                        // From token
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FROM")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)

                            tokenSelectorRow(selectedIndex: $fromTokenIndex, excludeIndex: toTokenIndex)
                        }

                        // Flip button
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let tmp = fromTokenIndex
                                    fromTokenIndex = toTokenIndex
                                    toTokenIndex = tmp
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(V2Colors.aztecGreen)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(V2Colors.aztecDark)
                                            .overlay(
                                                Circle()
                                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                            )
                                    )
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        // To token
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TO")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)

                            tokenSelectorRow(selectedIndex: $toTokenIndex, excludeIndex: fromTokenIndex)
                        }
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
                            Text(fromToken)
                                .font(V2Fonts.bodyMedium(14))
                                .foregroundColor(V2Colors.textSecondary)
                        }
                        .cardStyle()
                    }

                    // Quote display
                    if !amount.isEmpty {
                        VStack(spacing: 12) {
                            Text("QUOTE")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 10) {
                                quoteRow(label: "Estimated Output", value: "\(estimatedOutput) \(toToken)")
                                Divider()
                                    .background(V2Colors.borderPrimary)
                                quoteRow(label: "Price Impact", value: priceImpact)
                                quoteRow(label: "Min. Received", value: minimumReceived)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(V2Colors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                    )
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Slippage setting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SLIPPAGE TOLERANCE")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        HStack(spacing: 0) {
                            ForEach(slippageOptions.indices, id: \.self) { idx in
                                Button {
                                    selectedSlippageIndex = idx
                                } label: {
                                    Text(slippageOptions[idx])
                                        .font(V2Fonts.bodyMedium(13))
                                        .foregroundColor(selectedSlippageIndex == idx ? V2Colors.textPrimary : V2Colors.textMuted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(selectedSlippageIndex == idx ? V2Colors.aztecDark : .clear)
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

                    // Swap button
                    Button {
                        executeSwap()
                    } label: {
                        HStack(spacing: 8) {
                            if isSwapping {
                                ProgressView()
                                    .tint(V2Colors.bgCanvas)
                                    .scaleEffect(0.85)
                            }
                            Text(isSwapping ? "Swapping..." : "Swap \(fromToken) → \(toToken)")
                                .font(V2Fonts.bodyMedium(16))
                                .foregroundColor(V2Colors.bgCanvas)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canSwap ? V2Colors.aztecGreen : V2Colors.textMuted)
                        )
                    }
                    .disabled(!canSwap || isSwapping)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func tokenSelectorRow(selectedIndex: Binding<Int>, excludeIndex: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(availableTokens.indices, id: \.self) { idx in
                Button {
                    selectedIndex.wrappedValue = idx
                } label: {
                    Text(availableTokens[idx])
                        .font(V2Fonts.bodyMedium(13))
                        .foregroundColor(
                            selectedIndex.wrappedValue == idx
                                ? V2Colors.textPrimary
                                : (excludeIndex == idx ? V2Colors.textMuted.opacity(0.4) : V2Colors.textMuted)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedIndex.wrappedValue == idx ? V2Colors.aztecDark : .clear)
                        )
                }
                .disabled(excludeIndex == idx)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(V2Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(V2Colors.borderPrimary, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func quoteRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(V2Fonts.bodyMedium(13))
                .foregroundColor(V2Colors.textSecondary)
            Spacer()
            Text(value)
                .font(V2Fonts.mono(13))
                .foregroundColor(V2Colors.textPrimary)
        }
    }

    // MARK: - Actions

    private func executeSwap() {
        guard canSwap else { return }
        isSwapping = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isSwapping = false
            store.showToast("DEX not yet connected", type: .error)
        }
    }
}
