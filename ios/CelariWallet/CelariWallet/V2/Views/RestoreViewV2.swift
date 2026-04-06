import SwiftUI
import UniformTypeIdentifiers

struct RestoreViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFileUrl: URL?
    @State private var selectedFileName = ""
    @State private var fileData: Data?
    @State private var password = ""
    @State private var restoring = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // File picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BACKUP FILE")
                            .font(V2Fonts.label(10))
                            .tracking(1)
                            .foregroundColor(V2Colors.textTertiary)

                        Button { showFilePicker = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: fileData != nil ? "doc.fill" : "doc.badge.plus")
                                    .font(.system(size: 22))
                                    .foregroundColor(fileData != nil ? V2Colors.successGreen : V2Colors.textMuted)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fileData != nil ? selectedFileName : "Tap to select file")
                                        .font(V2Fonts.bodyMedium(14))
                                        .foregroundColor(fileData != nil ? V2Colors.textPrimary : V2Colors.textMuted)
                                    if fileData != nil {
                                        Text("\(fileData!.count / 1024) KB")
                                            .font(V2Fonts.mono(11))
                                            .foregroundColor(V2Colors.textTertiary)
                                    }
                                }

                                Spacer()

                                if fileData != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(V2Colors.successGreen)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(V2Colors.bgControl)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                fileData != nil ? V2Colors.successGreen.opacity(0.3) : V2Colors.borderPrimary,
                                                style: fileData != nil ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1, dash: [6])
                                            )
                                    )
                            )
                        }
                    }

                    // Password
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PASSWORD")
                            .font(V2Fonts.label(10))
                            .tracking(1)
                            .foregroundColor(V2Colors.textTertiary)
                        SecureField("Backup password", text: $password)
                            .font(V2Fonts.body(15))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(V2Colors.bgControl)
                            )
                    }

                    Divider().foregroundColor(V2Colors.borderDivider)

                    // Restore button
                    Button {
                        Task { await restoreWallet() }
                    } label: {
                        HStack(spacing: 8) {
                            if restoring {
                                ProgressView().tint(V2Colors.textWhite)
                            } else {
                                Image(systemName: "arrow.down.doc")
                                Text("Restore Wallet")
                            }
                        }
                        .font(V2Fonts.bodySemibold(16))
                        .foregroundColor(V2Colors.textWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canRestore ? V2Colors.aztecDark : V2Colors.textDisabled)
                        )
                    }
                    .disabled(!canRestore || restoring)
                }
                .padding(24)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Restore Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.screen = store.accounts.isEmpty ? .onboarding : .dashboard
                        dismiss()
                    }
                    .foregroundColor(V2Colors.textSecondary)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        fileData = data
                        selectedFileName = url.lastPathComponent
                        selectedFileUrl = url
                    }
                }
            }
        }
    }

    private var canRestore: Bool {
        fileData != nil && !password.isEmpty
    }

    private func restoreWallet() async {
        guard let data = fileData else { return }
        restoring = true
        do {
            let payload = try await BackupManager.decryptAsync(encryptedData: data, password: password)
            let account = try BackupManager.restoreAccount(from: payload)

            if store.accounts.contains(where: { $0.address == account.address }) {
                store.showToast("This account is already imported", type: .error)
                restoring = false
                return
            }

            store.accounts.append(account)
            store.activeAccountIndex = store.accounts.count - 1
            store.saveAccounts()
            store.tokens = Token.defaults

            if account.deployed && store.pxeInitialized {
                await store.reRegisterAccount(pxeBridge: pxeBridge, account: account)
            }
            await store.fetchBalances()

            store.screen = .dashboard
            store.showToast("Wallet restored!")
        } catch {
            store.showToast("Restore failed: \(error.localizedDescription)", type: .error)
        }
        restoring = false
    }
}
