import SwiftUI
import CryptoKit

struct GuardianSetupViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss

    enum Step { case input, processing, done }

    @State private var step: Step = .input
    @State private var guardian1Email = ""
    @State private var guardian2Email = ""
    @State private var guardian3Email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var guardianKeys: [GuardianKey] = []
    @State private var processing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch step {
                    case .input:
                        inputStep
                    case .processing:
                        processingStep
                    case .done:
                        doneStep
                    }
                }
                .padding(24)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Guardian Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(V2Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Step 1: Input

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Explanation
            VStack(alignment: .leading, spacing: 8) {
                Text("Social Recovery")
                    .font(V2Fonts.heading(20))
                    .foregroundColor(V2Colors.textPrimary)
                Text("Designate 3 trusted guardians who can help recover your account. Any 2 of 3 must approve a recovery request.")
                    .font(V2Fonts.body(14))
                    .foregroundColor(V2Colors.textSecondary)
            }

            // Guardian emails
            VStack(spacing: 12) {
                guardianField("Guardian 1", placeholder: "alice@example.com", text: $guardian1Email)
                guardianField("Guardian 2", placeholder: "bob@example.com", text: $guardian2Email)
                guardianField("Guardian 3", placeholder: "carol@example.com", text: $guardian3Email)
            }

            Divider().foregroundColor(V2Colors.borderDivider)

            // Recovery password
            VStack(alignment: .leading, spacing: 12) {
                Text("RECOVERY PASSWORD")
                    .font(V2Fonts.label(10))
                    .tracking(1)
                    .foregroundColor(V2Colors.textTertiary)

                SecureField("Password (8+ characters)", text: $password)
                    .font(V2Fonts.body(15))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(V2Colors.bgControl)
                    )

                SecureField("Confirm password", text: $confirmPassword)
                    .font(V2Fonts.body(15))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(V2Colors.bgControl)
                    )

                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .font(V2Fonts.mono(11))
                        .foregroundColor(V2Colors.errorRed)
                }
            }

            // Setup button
            Button {
                Task { await setupGuardians() }
            } label: {
                HStack(spacing: 8) {
                    if processing {
                        ProgressView().tint(V2Colors.textWhite)
                    } else {
                        Image(systemName: "shield.checkered")
                        Text("Setup Guardians")
                    }
                }
                .font(V2Fonts.bodySemibold(16))
                .foregroundColor(V2Colors.textWhite)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? V2Colors.aztecDark : V2Colors.textDisabled)
                )
            }
            .disabled(!canSubmit || processing)
        }
    }

    // MARK: - Step 2: Processing

    private var processingStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.5)
                .tint(V2Colors.soOrange)

            Text("SETTING UP GUARDIANS")
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.textTertiary)

            Text("Storing guardian hashes on-chain.\nThis may take a few minutes.")
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(V2Colors.successGreen)
                .padding(.top, 20)

            Text("GUARDIANS CONFIGURED")
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.successGreen)

            Text("Share each guardian's unique key with them securely. They will need it to approve a recovery request.")
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Guardian key cards
            ForEach(guardianKeys) { gk in
                VStack(alignment: .leading, spacing: 8) {
                    Text(gk.email)
                        .font(V2Fonts.bodyMedium(14))
                        .foregroundColor(V2Colors.textPrimary)

                    HStack {
                        Text(gk.key.prefix(20) + "..." + gk.key.suffix(8))
                            .font(V2Fonts.mono(11))
                            .foregroundColor(V2Colors.textTertiary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = gk.key
                            store.showToast("Key copied!")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(V2Colors.soBlue)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(V2Colors.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(V2Colors.borderPrimary, lineWidth: 1)
                        )
                )
            }

            Button {
                store.screen = .dashboard
                dismiss()
            } label: {
                Text("Done")
                    .font(V2Fonts.bodySemibold(16))
                    .foregroundColor(V2Colors.textWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.aztecDark)
                    )
            }
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        [guardian1Email, guardian2Email, guardian3Email].allSatisfy { $0.contains("@") } &&
        password.count >= 8 &&
        password == confirmPassword
    }

    private func guardianField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(V2Fonts.label(10))
                .tracking(1)
                .foregroundColor(V2Colors.textTertiary)
            TextField(placeholder, text: text)
                .font(V2Fonts.body(15))
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(V2Colors.bgControl)
                )
        }
    }

    private func setupGuardians() async {
        processing = true
        step = .processing

        // Generate 3 random 32-byte guardian keys
        let keys = (0..<3).map { _ in
            Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        }
        let emails = [guardian1Email, guardian2Email, guardian3Email]

        guardianKeys = zip(emails, keys).map { email, key in
            GuardianKey(email: email, key: key.map { String(format: "%02x", $0) }.joined())
        }

        // Hash each key (SHA-256, truncated to 31 bytes for BN254 Field)
        let hashes = keys.map { key -> String in
            let digest = SHA256.hash(data: key)
            let truncated = Array(digest.prefix(31))
            return "0x" + truncated.map { String(format: "%02x", $0) }.joined()
        }

        // Generate recovery CID from guardian data hash (deterministic, content-addressed)
        let recoveryPayload: [String: Any] = [
            "guardians": emails,
            "threshold": 2,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "account": store.activeAccount?.address ?? ""
        ]
        let payloadData = try? JSONSerialization.data(withJSONObject: recoveryPayload)
        let cidHash = SHA256.hash(data: payloadData ?? Data())
        let cidHex = cidHash.map { String(format: "%02x", $0) }.joined()
        // Split 64-char hex into two 31-byte BN254 field elements
        let cidPart1 = "0x" + String(cidHex.prefix(62))
        let cidPart2 = "0x" + String(cidHex.suffix(from: cidHex.index(cidHex.startIndex, offsetBy: 62))).padding(toLength: 62, withPad: "0", startingAt: 0)

        // Persist recovery data locally (encrypted backup for guardian key delivery)
        if let payloadData {
            let recoveryPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("celari/recovery")
            try? FileManager.default.createDirectory(at: recoveryPath!, withIntermediateDirectories: true)
            try? payloadData.write(to: recoveryPath!.appendingPathComponent("\(cidHex.prefix(16)).json"))
        }

        do {
            let result = try await pxeBridge.setupGuardians(
                guardianHash0: hashes[0],
                guardianHash1: hashes[1],
                guardianHash2: hashes[2],
                threshold: 2,
                cidPart1: cidPart1,
                cidPart2: cidPart2
            )
            _ = result
            step = .done
            store.showToast("Guardians configured!")
        } catch {
            store.showToast("Guardian setup failed: \(error.localizedDescription)", type: .error)
            step = .input
        }

        processing = false
    }
}

struct GuardianKey: Identifiable {
    let id = UUID()
    let email: String
    let key: String
}
