import SwiftUI

struct AddAccountView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Add Account")

            VStack(spacing: 24) {
                Spacer()

                DiamondShape()
                    .stroke(CelariColors.copper.opacity(0.3), lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("+")
                            .font(CelariTypography.heading)
                            .foregroundColor(CelariColors.copper)
                    )

                Text("CREATE NEW ACCOUNT")
                    .font(CelariTypography.monoLabel)
                    .tracking(3)
                    .foregroundColor(CelariColors.textDim)

                Text("Create a new passkey-authenticated account with Face ID or Touch ID")
                    .font(CelariTypography.monoTiny)
                    .foregroundColor(CelariColors.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    createAccount()
                } label: {
                    if creating {
                        ProgressView()
                            .tint(CelariColors.textWarm)
                    } else {
                        Text("Create with Passkey")
                    }
                }
                .buttonStyle(CelariPrimaryButtonStyle())
                .disabled(creating)
                .padding(.horizontal, 16)

                Button {
                    store.screen = .restore
                } label: {
                    Text("Restore from Backup")
                }
                .buttonStyle(CelariSecondaryButtonStyle())
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private func createAccount() {
        creating = true
        Task {
            do {
                // Use proper account creation flow with Keychain + passkey (3.2 audit fix)
                try await store.createPasskeyAccount(pxeBridge: pxeBridge)
            } catch {
                store.showToast("Failed: \(error.localizedDescription)", type: .error)
            }
            creating = false
        }
    }
}
