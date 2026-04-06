import SwiftUI

struct OnboardingViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var creating = false
    @State private var showNetworkPicker = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo + brand
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(V2Colors.aztecDark)
                        .frame(width: 80, height: 80)
                    Text("C")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundColor(V2Colors.aztecGreen)
                }

                Text("Celari")
                    .font(V2Fonts.heading(32))
                    .foregroundColor(V2Colors.textPrimary)

                Text("celāre — to hide, to conceal")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(V2Colors.textTertiary)
            }

            // Features
            VStack(spacing: 14) {
                featureRow(icon: "shield.checkered", text: "Privacy-first Aztec Network wallet")
                featureRow(icon: "faceid", text: "Passkey authentication — no seed phrases")
                featureRow(icon: "eye.slash", text: "Private transfers invisible to observers")
            }
            .padding(.top, 40)
            .padding(.horizontal, 32)

            // Network selector + connection status
            Button { showNetworkPicker = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.connected ? V2Colors.aztecGreen : V2Colors.soOrange)
                        .frame(width: 8, height: 8)
                    Text(currentNetworkName)
                        .font(V2Fonts.mono(12))
                        .foregroundColor(V2Colors.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(V2Colors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(V2Colors.bgControl)
                        .overlay(
                            Capsule()
                                .stroke(store.connected ? V2Colors.aztecGreen.opacity(0.3) : V2Colors.soOrange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.top, 16)

            // Alpha warning
            Text("Alpha • Experimental • Not audited")
                .font(V2Fonts.mono(10))
                .foregroundColor(V2Colors.textMuted)
                .padding(.top, 6)

            Spacer()
            Spacer()

            // Buttons
            VStack(spacing: 12) {
                // Create Wallet — primary
                Button {
                    createWallet()
                } label: {
                    HStack(spacing: 8) {
                        if creating {
                            ProgressView().tint(V2Colors.textWhite)
                        } else {
                            Image(systemName: "faceid")
                            Text("Create Wallet")
                        }
                    }
                    .font(V2Fonts.bodySemibold(16))
                    .foregroundColor(V2Colors.textWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(V2Colors.aztecDark)
                    )
                }
                .disabled(creating)

                // Restore from Backup
                Button {
                    store.screen = .restore
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                        Text("Restore from Backup")
                    }
                    .font(V2Fonts.bodyMedium(15))
                    .foregroundColor(V2Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(V2Colors.bgControl)
                    )
                }

                // Recover Account
                Button {
                    store.screen = .recoverAccount
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key")
                        Text("Recover Account")
                    }
                    .font(V2Fonts.bodyMedium(15))
                    .foregroundColor(V2Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(V2Colors.bgControl)
                    )
                }

                // Demo Mode
                Button {
                    store.enterDemoMode()
                } label: {
                    Text("Demo Mode")
                        .font(V2Fonts.bodyMedium(14))
                        .foregroundColor(V2Colors.textMuted)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(V2Colors.bgCanvas)
        .sheet(isPresented: $showNetworkPicker) {
            NetworkPickerSheet()
        }
        .task {
            await store.checkConnection()
        }
    }

    private var currentNetworkName: String {
        NetworkPreset(rawValue: store.network)?.name ?? store.network.capitalized
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
                .font(.system(size: 15))
                .foregroundColor(V2Colors.aztecGreen)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(V2Colors.aztecDark.opacity(0.08))
                )

            Text(text)
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)

            Spacer()
        }
    }
}
