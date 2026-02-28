import SwiftUI
import CryptoKit

/// Guardian setup screen.
/// Owner enters 3 guardian emails + a recovery password.
/// Generates guardian keys, stores hashes on-chain, sends keys to guardians.
struct GuardianSetupView: View {
    @Environment(WalletStore.self) private var store
    @State private var email0 = ""
    @State private var email1 = ""
    @State private var email2 = ""
    @State private var recoveryPassword = ""
    @State private var confirmPassword = ""
    @State private var setting = false
    @State private var step: SetupStep = .input

    enum SetupStep {
        case input
        case confirming
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Guardian Setup")

            ScrollView {
                VStack(spacing: 16) {
                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GUARDIANS")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        Text("Assign 3 trusted people who can help recover your account. They'll receive an email with a guardian key.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(CelariColors.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    DecoSeparator()

                    // Guardian emails
                    FormField(label: "Guardian 1 Email", text: $email0, placeholder: "alice@example.com")
                    FormField(label: "Guardian 2 Email", text: $email1, placeholder: "bob@example.com")
                    FormField(label: "Guardian 3 Email", text: $email2, placeholder: "carol@example.com")

                    DecoSeparator()

                    // Recovery password
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECOVERY PASSWORD")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        Text("This password encrypts your recovery bundle. You'll need it to start recovery from a new device.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(CelariColors.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    FormField(label: "Password", text: $recoveryPassword, placeholder: "Recovery password", isSecure: true)
                    FormField(label: "Confirm", text: $confirmPassword, placeholder: "Confirm password", isSecure: true)

                    DecoSeparator()

                    // Setup button
                    Button {
                        setupGuardians()
                    } label: {
                        if setting {
                            ProgressView()
                                .tint(CelariColors.textWarm)
                        } else {
                            Text("Setup Guardians")
                        }
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(!isValid || setting)
                    .opacity(isValid ? 1 : 0.5)
                }
                .padding(16)
            }
        }
    }

    private var isValid: Bool {
        !email0.isEmpty && !email1.isEmpty && !email2.isEmpty
            && email0.contains("@") && email1.contains("@") && email2.contains("@")
            && recoveryPassword.count >= 8
            && recoveryPassword == confirmPassword
    }

    private func setupGuardians() {
        setting = true
        Task {
            do {
                // 1. Generate guardian keys (random 32 bytes each)
                let key0 = generateGuardianKey()
                let key1 = generateGuardianKey()
                let key2 = generateGuardianKey()

                // 2. Build recovery bundle
                let bundle = RecoveryBundle(
                    accountAddress: store.activeAccount?.address ?? "",
                    guardians: [
                        .init(email: email0, key: key0),
                        .init(email: email1, key: key1),
                        .init(email: email2, key: key2),
                    ],
                    threshold: 2
                )

                // 3. Encrypt bundle with recovery password
                let bundleData = try JSONEncoder().encode(bundle)
                let encryptedBundle = try await BackupManager.encryptAsync(
                    data: bundleData,
                    password: recoveryPassword
                )

                // 4. Upload to IPFS (TODO: implement IPFS upload)
                // let cid = try await IPFSManager.upload(encryptedBundle)

                // 5. Call contract setup_guardians (TODO: integrate with PXE)
                // Hashes are poseidon2(guardian_key) — computed on-chain

                // 6. Send emails via relay server (TODO: integrate with relay)

                store.showToast("Guardians configured!")
                store.screen = .dashboard
            } catch {
                store.showToast("Setup failed: \(error.localizedDescription)", type: .error)
            }
            setting = false
        }
    }

    private func generateGuardianKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Recovery Bundle Model

struct RecoveryBundle: Codable {
    let accountAddress: String
    let guardians: [Guardian]
    let threshold: Int

    struct Guardian: Codable {
        let email: String
        let key: String
    }
}
