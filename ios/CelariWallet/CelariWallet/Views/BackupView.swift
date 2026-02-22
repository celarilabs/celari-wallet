import SwiftUI

struct BackupView: View {
    @Environment(WalletStore.self) private var store
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var exporting = false
    @State private var exportData: Data?
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Backup Wallet")

            ScrollView {
                VStack(spacing: 16) {
                    // Warning
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundColor(CelariColors.copper)
                        Text("Your backup will be encrypted with the password you set below.")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textBody)
                    }
                    .padding(12)
                    .background(CelariColors.copper.opacity(0.05))
                    .overlay(Rectangle().stroke(CelariColors.copper.opacity(0.2), lineWidth: 1))

                    FormField(label: "Password", text: $password, placeholder: "Enter password", isSecure: true)
                    FormField(label: "Confirm Password", text: $confirmPassword, placeholder: "Confirm password", isSecure: true)

                    if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                        Text("Passwords do not match")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.red)
                    }

                    DecoSeparator()

                    Button {
                        performBackup()
                    } label: {
                        if exporting {
                            ProgressView()
                                .tint(CelariColors.textWarm)
                        } else {
                            Text("Export Backup")
                        }
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(password.isEmpty || password != confirmPassword || exporting)
                    .opacity(password.isEmpty || password != confirmPassword ? 0.5 : 1)

                    Text("Store your backup file in a safe location. You will need the password to restore.")
                        .font(CelariTypography.monoTiny)
                        .foregroundColor(CelariColors.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showShare) {
            if let data = exportData {
                ShareSheet(items: [data])
            }
        }
    }

    private func performBackup() {
        exporting = true
        Task {
            do {
                // Build backup payload with Keychain keys
                guard let account = store.activeAccount else {
                    store.showToast("No active account", type: .error)
                    exporting = false
                    return
                }

                let payload = BackupManager.buildBackupPayload(account: account)
                let encryptedData = try BackupManager.encrypt(data: payload, password: password)
                exportData = encryptedData
                showShare = true
                store.showToast("Encrypted backup ready")
            } catch {
                store.showToast("Backup failed: \(error.localizedDescription)", type: .error)
            }
            exporting = false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
