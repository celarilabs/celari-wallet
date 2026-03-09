import SwiftUI
import CryptoKit

/// Guardian setup screen.
/// Owner enters 3 guardian emails + a recovery password.
/// Generates guardian keys, stores hashes on-chain, sends keys to guardians.
struct GuardianSetupView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var email0 = ""
    @State private var email1 = ""
    @State private var email2 = ""
    @State private var recoveryPassword = ""
    @State private var confirmPassword = ""
    @State private var setting = false
    @State private var step: SetupStep = .input
    @State private var generatedKeys: [GuardianKey] = []

    enum SetupStep {
        case input
        case processing
        case done
    }

    struct GuardianKey: Identifiable {
        let id = UUID()
        let email: String
        let key: String
    }

    private let relayBaseUrl = "https://recovery.celariwallet.com"

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Guardian Setup")

            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .input:
                        inputView
                    case .processing:
                        processingView
                    case .done:
                        doneView
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Step Views

    private var inputView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GUARDIANS")
                    .font(CelariTypography.monoLabel)
                    .tracking(2)
                    .foregroundColor(CelariColors.textDim)

                Text("Assign 3 trusted people who can help recover your account. They'll receive a guardian key to keep safe.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(CelariColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DecoSeparator()

            FormField(label: "Guardian 1 Email", text: $email0, placeholder: "alice@example.com")
            FormField(label: "Guardian 2 Email", text: $email1, placeholder: "bob@example.com")
            FormField(label: "Guardian 3 Email", text: $email2, placeholder: "carol@example.com")

            DecoSeparator()

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
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: CelariColors.copper))
                .scaleEffect(1.5)

            Text("SETTING UP GUARDIANS")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.textDim)

            Text("Storing guardian hashes on-chain. This may take a few minutes.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(CelariColors.green)

            Text("GUARDIANS CONFIGURED")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.green)

            Text("Share each guardian key with the corresponding person. They must keep it safe for account recovery.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)

            DecoSeparator()

            // Show guardian keys for sharing
            ForEach(generatedKeys) { gk in
                VStack(alignment: .leading, spacing: 4) {
                    Text(gk.email)
                        .font(CelariTypography.monoSmall)
                        .foregroundColor(CelariColors.textBody)

                    HStack {
                        Text(gk.key.prefix(16) + "...")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textDim)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = gk.key
                            store.showToast("Key copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(CelariColors.copper)
                        }
                    }
                }
                .padding(12)
                .background(CelariColors.bgInput)
                .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
            }

            DecoSeparator()

            Button {
                store.screen = .dashboard
            } label: {
                Text("Done")
            }
            .buttonStyle(CelariPrimaryButtonStyle())
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !email0.isEmpty && !email1.isEmpty && !email2.isEmpty
            && email0.contains("@") && email1.contains("@") && email2.contains("@")
            && recoveryPassword.count >= 8
            && recoveryPassword == confirmPassword
    }

    // MARK: - Setup Logic

    private func setupGuardians() {
        setting = true
        step = .processing
        Task {
            do {
                // 1. Generate random guardian keys (32 bytes each)
                let key0 = generateGuardianKey()
                let key1 = generateGuardianKey()
                let key2 = generateGuardianKey()

                // 2. Compute SHA-256 hashes (truncated to 31 bytes for BN254 Field)
                let hash0 = guardianKeyToFieldHash(key0)
                let hash1 = guardianKeyToFieldHash(key1)
                let hash2 = guardianKeyToFieldHash(key2)

                // 3. Build and encrypt recovery bundle
                let bundle = RecoveryBundle(
                    accountAddress: store.activeAccount?.address ?? "",
                    guardians: [
                        .init(email: email0, key: key0),
                        .init(email: email1, key: key1),
                        .init(email: email2, key: key2),
                    ],
                    threshold: 2
                )
                let bundleData = try JSONEncoder().encode(bundle)
                let bundleDict = try JSONSerialization.jsonObject(with: bundleData) as? [String: Any] ?? [:]
                _ = try await BackupManager.encryptAsync(
                    data: bundleDict,
                    password: recoveryPassword
                )

                // 4. IPFS upload (TODO: use actual IPFS service)
                // For now, store encrypted bundle locally and use placeholder CID.
                let cidPart1 = "0"
                let cidPart2 = "0"

                // 5. Call contract setup_guardians via PXE bridge
                _ = try await pxeBridge.setupGuardians(
                    guardianHash0: hash0,
                    guardianHash1: hash1,
                    guardianHash2: hash2,
                    threshold: 2,
                    cidPart1: cidPart1,
                    cidPart2: cidPart2
                )

                // 6. Send guardian keys via relay (TODO: wire up when deployed)
                // For now, show keys for manual sharing.
                // try await sendGuardianEmails(keys: [(email0, key0), (email1, key1), (email2, key2)])

                generatedKeys = [
                    GuardianKey(email: email0, key: key0),
                    GuardianKey(email: email1, key: key1),
                    GuardianKey(email: email2, key: key2),
                ]

                step = .done
                store.showToast("Guardians configured on-chain!")
            } catch {
                store.showToast("Setup failed: \(error.localizedDescription)", type: .error)
                step = .input
            }
            setting = false
        }
    }

    // MARK: - Crypto Helpers

    private func generateGuardianKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA-256 of a hex key, truncate to 31 bytes, return as "0x..." Field hex string.
    /// Matches the contract's bytes31_to_field(sha256::digest(key_bytes)).
    private func guardianKeyToFieldHash(_ hexKey: String) -> String {
        let keyData = Data(hexString: hexKey)
        let hash = SHA256.hash(data: keyData)
        let hashBytes = Array(hash)
        // Take first 31 bytes (BN254 field fits 248 bits = 31 bytes)
        let first31 = Array(hashBytes.prefix(31))
        let hex = first31.map { String(format: "%02x", $0) }.joined()
        return "0x" + hex
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

// MARK: - Data hex helper

extension Data {
    init(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        self = data
    }
}
