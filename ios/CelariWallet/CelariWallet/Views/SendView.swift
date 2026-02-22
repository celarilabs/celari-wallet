import SwiftUI

struct SendView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Send")

            ScrollView {
                VStack(spacing: 16) {
                    // Transfer type selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRANSFER TYPE")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        HStack(spacing: 0) {
                            ForEach(TransferType.allCases, id: \.self) { type in
                                Button {
                                    store.sendForm.transferType = type
                                } label: {
                                    Text(type.label)
                                        .font(CelariTypography.monoTiny)
                                        .tracking(1)
                                        .foregroundColor(store.sendForm.transferType == type ? CelariColors.copper : CelariColors.textDim)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(store.sendForm.transferType == type ? CelariColors.copper.opacity(0.08) : .clear)
                                        .overlay(
                                            Rectangle().stroke(
                                                store.sendForm.transferType == type ? CelariColors.copper.opacity(0.4) : CelariColors.border,
                                                lineWidth: 1
                                            )
                                        )
                                }
                            }
                        }

                        Text(store.sendForm.transferType.description)
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(store.sendForm.transferType.isPrivate ? CelariColors.green : CelariColors.textDim)
                    }

                    // Token selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOKEN")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(store.tokens) { token in
                                    Button {
                                        store.sendForm.token = token.symbol
                                    } label: {
                                        Text(token.symbol)
                                            .font(CelariTypography.monoTiny)
                                            .foregroundColor(store.sendForm.token == token.symbol ? CelariColors.copper : CelariColors.textDim)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .overlay(
                                                Rectangle().stroke(
                                                    store.sendForm.token == token.symbol ? CelariColors.copper.opacity(0.4) : CelariColors.border,
                                                    lineWidth: 1
                                                )
                                            )
                                    }
                                }
                            }
                        }
                    }

                    FormField(label: "Recipient Address", text: Bindable(store).sendForm.to, placeholder: "0x...")
                    FormField(label: "Amount", text: Bindable(store).sendForm.amount, placeholder: "0.00", keyboardType: .decimalPad)

                    DecoSeparator()

                    // Send button
                    Button {
                        performSend()
                    } label: {
                        if sending {
                            ProgressView()
                                .tint(CelariColors.textWarm)
                        } else {
                            Text("Sign & Send")
                        }
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(sending || store.sendForm.to.isEmpty || store.sendForm.amount.isEmpty)
                    .opacity(sending || store.sendForm.to.isEmpty || store.sendForm.amount.isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
        }
    }

    private func performSend() {
        sending = true
        Task {
            do {
                // Validate inputs
                guard isValidAddress(store.sendForm.to) else {
                    store.showToast("Enter a valid address (0x...)", type: .error)
                    sending = false
                    return
                }
                guard isValidAmount(store.sendForm.amount) else {
                    store.showToast("Enter a valid amount", type: .error)
                    sending = false
                    return
                }

                // Biometric verification before sending
                if store.activeAccount?.type == .passkey {
                    try await store.passkeyManager.authenticateWithBiometrics(
                        reason: "Verify identity to sign transaction"
                    )
                }

                let tokenAddress = store.tokenAddresses[store.sendForm.token] ?? ""
                _ = try await pxeBridge.transfer(
                    to: store.sendForm.to,
                    amount: store.sendForm.amount,
                    tokenAddress: tokenAddress,
                    transferType: store.sendForm.transferType.rawValue
                )

                // Add to activity history
                store.activities.insert(
                    Activity(type: .send, label: "Transfer", amount: "-\(store.sendForm.amount) \(store.sendForm.token)", isPrivate: store.sendForm.transferType.isPrivate),
                    at: 0
                )
                store.saveActivities()

                store.showToast("Transaction sent successfully")
                store.sendForm = SendForm()
                store.screen = .dashboard
                await store.fetchBalances()
            } catch {
                store.showToast("Transaction failed: \(error.localizedDescription)", type: .error)
            }
            sending = false
        }
    }

    private func isValidAddress(_ addr: String) -> Bool {
        addr.hasPrefix("0x") && addr.count >= 42
    }

    private func isValidAmount(_ amount: String) -> Bool {
        guard let num = Double(amount.replacingOccurrences(of: ",", with: "")) else { return false }
        return num > 0 && num < 1e15
    }
}
