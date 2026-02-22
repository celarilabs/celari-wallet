import SwiftUI

struct OnboardingView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                DiamondShape()
                    .fill(CelariColors.burgundy)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text("C")
                            .font(CelariTypography.heading)
                            .foregroundColor(CelariColors.textWarm)
                    )

                Text("Celari")
                    .font(CelariTypography.heading)
                    .tracking(8)
                    .foregroundColor(CelariColors.textWarm)
            }

            DecoSeparator()
                .padding(.vertical, 16)

            Text("celāre — to hide, to conceal")
                .font(CelariTypography.accentItalic)
                .foregroundColor(CelariColors.textMuted)

            // Features
            VStack(spacing: 12) {
                featureRow(icon: "lock.shield", text: "Privacy-first Aztec Network wallet")
                featureRow(icon: "faceid", text: "Passkey authentication — no seed phrases")
                featureRow(icon: "arrow.left.arrow.right", text: "Private transfers invisible to observers")
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    createWallet()
                } label: {
                    if creating {
                        ProgressView()
                            .tint(CelariColors.textWarm)
                    } else {
                        Text("Create Wallet")
                    }
                }
                .buttonStyle(CelariPrimaryButtonStyle())
                .disabled(creating)

                Button("Restore from Backup") {
                    store.screen = .restore
                }
                .buttonStyle(CelariSecondaryButtonStyle())

                Button("Demo Mode") {
                    store.enterDemoMode()
                }
                .buttonStyle(CelariSecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func createWallet() {
        creating = true
        Task {
            do {
                try await store.createPasskeyAccount(pxeBridge: pxeBridge)
            } catch {
                store.showToast("Wallet creation failed: \(error.localizedDescription)", type: .error)
            }
            creating = false
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(CelariColors.copper)
                .frame(width: 24)

            Text(text)
                .font(CelariTypography.monoSmall)
                .foregroundColor(CelariColors.textBody)
                .tracking(0.5)

            Spacer()
        }
    }
}
