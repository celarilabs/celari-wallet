import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @Environment(WalletStore.self) private var store
    @State private var password: String = ""
    @State private var showFilePicker = false
    @State private var selectedFileData: Data?
    @State private var fileName: String = ""
    @State private var restoring = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Restore Wallet")

            ScrollView {
                VStack(spacing: 16) {
                    // File picker
                    VStack(spacing: 8) {
                        Text("BACKUP FILE")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showFilePicker = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(CelariColors.textDim)

                                Text(fileName.isEmpty ? "TAP TO SELECT FILE" : fileName)
                                    .font(CelariTypography.monoTiny)
                                    .tracking(1)
                                    .foregroundColor(fileName.isEmpty ? CelariColors.textDim : CelariColors.copper)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(CelariColors.bgInput)
                            .overlay(
                                Rectangle().stroke(
                                    style: StrokeStyle(lineWidth: 1, dash: fileName.isEmpty ? [6] : [])
                                )
                                .foregroundColor(fileName.isEmpty ? CelariColors.border : CelariColors.copper.opacity(0.3))
                            )
                        }
                    }

                    FormField(label: "Password", text: $password, placeholder: "Backup password", isSecure: true)

                    DecoSeparator()

                    Button {
                        performRestore()
                    } label: {
                        if restoring {
                            ProgressView()
                                .tint(CelariColors.textWarm)
                        } else {
                            Text("Restore Wallet")
                        }
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(selectedFileData == nil || password.isEmpty || restoring)
                    .opacity(selectedFileData == nil || password.isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    selectedFileData = data
                    fileName = url.lastPathComponent
                }
            case .failure:
                store.showToast("Could not read file", type: .error)
            }
        }
    }

    private func performRestore() {
        restoring = true
        Task {
            guard let data = selectedFileData else {
                store.showToast("No file selected", type: .error)
                restoring = false
                return
            }

            do {
                // Decrypt backup using BackupManager (AES-256-GCM + PBKDF2)
                let payload = try BackupManager.decrypt(encryptedData: data, password: password)

                // Restore account with Keychain key storage
                let account = try BackupManager.restoreAccount(from: payload)

                // Check for duplicates
                if store.accounts.contains(where: { $0.address == account.address }) {
                    store.showToast("This account is already imported", type: .error)
                    restoring = false
                    return
                }

                store.accounts.append(account)
                store.activeAccountIndex = store.accounts.count - 1
                store.saveAccounts()
                store.tokens = Token.defaults
                store.showToast("Account restored!")
                store.screen = .dashboard
            } catch {
                store.showToast("Restore failed: \(error.localizedDescription)", type: .error)
            }
            restoring = false
        }
    }
}
