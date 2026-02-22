import SwiftUI

struct ConfirmTxView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Confirm Transaction")

            VStack(spacing: 20) {
                Spacer()

                DiamondShape()
                    .stroke(CelariColors.copper, lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(CelariColors.copper)
                    )

                Text("APPROVE TRANSACTION")
                    .font(CelariTypography.monoLabel)
                    .tracking(3)
                    .foregroundColor(CelariColors.textWarm)

                // Transaction details
                VStack(spacing: 8) {
                    detailRow("Type", store.sendForm.transferType.label)
                    detailRow("Token", store.sendForm.token)
                    detailRow("Amount", store.sendForm.amount)
                    if !store.sendForm.to.isEmpty {
                        detailRow("To", String(store.sendForm.to.prefix(12)) + "...")
                    }
                }
                .padding(16)
                .background(CelariColors.bgCard)
                .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button {
                        store.screen = .dashboard
                    } label: {
                        Text("Reject")
                    }
                    .buttonStyle(CelariSecondaryButtonStyle())

                    Button {
                        confirm()
                    } label: {
                        if confirming {
                            ProgressView()
                                .tint(CelariColors.textWarm)
                        } else {
                            Text("Approve")
                        }
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(confirming)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(CelariTypography.monoTiny)
                .foregroundColor(CelariColors.textDim)
            Spacer()
            Text(value)
                .font(CelariTypography.monoSmall)
                .foregroundColor(CelariColors.textBody)
        }
    }

    private func confirm() {
        confirming = true
        Task {
            do {
                let tokenAddress = store.tokenAddresses[store.sendForm.token] ?? ""
                _ = try await pxeBridge.transfer(
                    to: store.sendForm.to,
                    amount: store.sendForm.amount,
                    tokenAddress: tokenAddress,
                    transferType: store.sendForm.transferType.rawValue
                )
                store.showToast("Transaction confirmed")
                store.sendForm = SendForm()
                store.screen = .dashboard
            } catch {
                store.showToast("Failed: \(error.localizedDescription)", type: .error)
            }
            confirming = false
        }
    }
}
