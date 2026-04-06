import SwiftUI

struct BackupViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Warning banner
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 18))
                            .foregroundColor(V2Colors.soOrange)
                        Text("Your backup will be encrypted with the password you set below.")
                            .font(V2Fonts.body(13))
                            .foregroundColor(V2Colors.textPrimary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(V2Colors.soOrange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(V2Colors.soOrange.opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Password fields
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PASSWORD")
                                .font(V2Fonts.label(10))
                                .tracking(1)
                                .foregroundColor(V2Colors.textTertiary)
                            SecureField("Enter password", text: $password)
                                .font(V2Fonts.body(15))
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(V2Colors.bgControl)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("CONFIRM PASSWORD")
                                .font(V2Fonts.label(10))
                                .tracking(1)
                                .foregroundColor(V2Colors.textTertiary)
                            SecureField("Confirm password", text: $confirmPassword)
                                .font(V2Fonts.body(15))
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(V2Colors.bgControl)
                                )
                        }

                        if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match")
                                .font(V2Fonts.mono(11))
                                .foregroundColor(V2Colors.errorRed)
                        }
                    }

                    Divider().foregroundColor(V2Colors.borderDivider)

                    // Export button
                    Button {
                        Task { await exportBackup() }
                    } label: {
                        HStack(spacing: 8) {
                            if exporting {
                                ProgressView().tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Backup")
                            }
                        }
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canExport ? V2Colors.aztecDark : V2Colors.textDisabled)
                        )
                    }
                    .disabled(!canExport || exporting)

                    Text("Store your backup file in a safe location. You'll need the password to restore it.")
                        .font(V2Fonts.body(12))
                        .foregroundColor(V2Colors.textMuted)
                }
                .padding(24)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Backup Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(V2Colors.textSecondary)
                }
            }
        }
    }

    private var canExport: Bool {
        password.count >= 8 && password == confirmPassword
    }

    private func exportBackup() async {
        guard let account = store.activeAccount else { return }
        exporting = true
        do {
            try await store.passkeyManager.authenticateWithBiometrics(reason: "Authenticate to export backup")
            let payload = BackupManager.buildBackupPayload(account: account)
            let encrypted = try await BackupManager.encryptAsync(data: payload, password: password)

            // Share encrypted file
            let fileName = "celari-backup-\(account.label.replacingOccurrences(of: " ", with: "-")).enc"
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try encrypted.write(to: tempUrl)

            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [tempUrl], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = windowScene.windows.first?.rootViewController {
                    root.present(activityVC, animated: true)
                }
            }
            store.lastBackupDate = Date().timeIntervalSince1970
            store.showToast("Backup exported!")
        } catch {
            store.showToast("Backup failed: \(error.localizedDescription)", type: .error)
        }
        exporting = false
    }
}
