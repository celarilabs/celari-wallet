import SwiftUI

struct AddAccountViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 44))
                    .foregroundColor(V2Colors.aztecGreen)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(V2Colors.aztecDark.opacity(0.08))
                    )

                VStack(spacing: 8) {
                    Text("Add Account")
                        .font(V2Fonts.heading(22))
                        .foregroundColor(V2Colors.textPrimary)
                    Text("Create a new passkey-authenticated account with Face ID or Touch ID.")
                        .font(V2Fonts.body(14))
                        .foregroundColor(V2Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        createAccount()
                    } label: {
                        HStack(spacing: 8) {
                            if creating {
                                ProgressView().tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "faceid")
                                Text("Create with Passkey")
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

                    Button {
                        dismiss()
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(V2Colors.bgCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(V2Colors.textSecondary)
                }
            }
        }
    }

    private func createAccount() {
        creating = true
        Task {
            do {
                try await store.createPasskeyAccount(pxeBridge: pxeBridge)
                dismiss()
            } catch {
                store.showToast("Account creation failed: \(error.localizedDescription)", type: .error)
            }
            creating = false
        }
    }
}
