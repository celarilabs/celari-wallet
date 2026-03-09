import SwiftUI

/// Account recovery screen for a new device.
/// User enters account address + recovery password to start the process.
struct RecoverAccountView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var accountAddress = ""
    @State private var recoveryPassword = ""
    @State private var recovering = false
    @State private var recoveryId: String?
    @State private var approvedCount = 0
    @State private var thresholdMet = false
    @State private var guardianKeys: [String] = []
    @State private var step: RecoveryStep = .input
    @State private var polling = false

    enum RecoveryStep {
        case input            // Enter address + password
        case waitingGuardians // Waiting for guardian approvals
        case timeLock         // 24h waiting period
        case complete         // Recovery done
    }

    private let relayBaseUrl = "https://recovery.celariwallet.com"

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Recover Account")

            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .input:
                        inputView
                    case .waitingGuardians:
                        waitingView
                    case .timeLock:
                        timeLockView
                    case .complete:
                        completeView
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
                Text("ACCOUNT RECOVERY")
                    .font(CelariTypography.monoLabel)
                    .tracking(2)
                    .foregroundColor(CelariColors.textDim)

                Text("Enter the account address and your recovery password to start the guardian approval process.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(CelariColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DecoSeparator()

            FormField(label: "Account Address", text: $accountAddress, placeholder: "0x...")
            FormField(label: "Recovery Password", text: $recoveryPassword, placeholder: "Your recovery password", isSecure: true)

            DecoSeparator()

            Button {
                startRecovery()
            } label: {
                if recovering {
                    ProgressView()
                        .tint(CelariColors.textWarm)
                } else {
                    Text("Start Recovery")
                }
            }
            .buttonStyle(CelariPrimaryButtonStyle())
            .disabled(accountAddress.isEmpty || recoveryPassword.isEmpty || recovering)
            .opacity(accountAddress.isEmpty || recoveryPassword.isEmpty ? 0.5 : 1)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40))
                .foregroundColor(CelariColors.copper)

            Text("WAITING FOR GUARDIANS")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.textDim)

            Text("Approval emails have been sent to your guardians. Ask them to check their email and approve the recovery.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)

            DecoSeparator()

            // Approval progress
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 4) {
                        Image(systemName: i < approvedCount ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(i < approvedCount ? CelariColors.green : CelariColors.textFaint)
                        Text("Guardian \(i + 1)")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textDim)
                    }
                }
            }
            .padding(.vertical, 12)

            Text("\(approvedCount)/2 approvals")
                .font(CelariTypography.monoSmall)
                .foregroundColor(CelariColors.copper)

            Button {
                checkStatus()
            } label: {
                HStack(spacing: 6) {
                    if polling {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(CelariColors.textDim)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    Text("CHECK STATUS")
                        .font(CelariTypography.monoTiny)
                        .tracking(1)
                }
                .foregroundColor(CelariColors.textDim)
            }
            .disabled(polling)
            .padding(.top, 8)
        }
    }

    private var timeLockView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.badge.clock")
                .font(.system(size: 40))
                .foregroundColor(CelariColors.copper)

            Text("24H TIME-LOCK")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.textDim)

            Text("Guardian threshold met. The recovery will complete after a 24-hour safety period. The original owner can cancel during this time.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)

            DecoSeparator()

            Button {
                executeRecovery()
            } label: {
                if recovering {
                    ProgressView()
                        .tint(CelariColors.textWarm)
                } else {
                    Text("Finalize Recovery")
                }
            }
            .buttonStyle(CelariPrimaryButtonStyle())
            .disabled(recovering)
        }
    }

    private var completeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(CelariColors.green)

            Text("ACCOUNT RECOVERED")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.green)

            Text("Your account has been recovered with a new signing key. You can now use your wallet.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)

            Button {
                store.screen = .dashboard
            } label: {
                Text("Go to Dashboard")
            }
            .buttonStyle(CelariPrimaryButtonStyle())
        }
    }

    // MARK: - Actions

    private func startRecovery() {
        recovering = true
        Task {
            do {
                // 1. Generate new P256 key pair for this device
                let keyResult = try await pxeBridge.generateKeys()
                guard let newPubKeyX = keyResult["publicKeyX"] as? String,
                      let newPubKeyY = keyResult["publicKeyY"] as? String else {
                    throw RecoveryError.keyGenerationFailed
                }

                // 2. Send recovery request to relay server
                let body: [String: Any] = [
                    "accountAddress": accountAddress,
                    "newPubKeyX": newPubKeyX,
                    "newPubKeyY": newPubKeyY,
                    "guardians": [
                        ["email": "guardian@example.com"] // Relay fetches emails from CID
                    ]
                ]

                let url = URL(string: "\(relayBaseUrl)/api/initiate")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw RecoveryError.relayRequestFailed
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                recoveryId = json?["recoveryId"] as? String

                step = .waitingGuardians
                store.showToast("Recovery emails sent to guardians")
            } catch {
                store.showToast("Recovery failed: \(error.localizedDescription)", type: .error)
            }
            recovering = false
        }
    }

    private func checkStatus() {
        guard let rid = recoveryId else { return }
        polling = true
        Task {
            do {
                let url = URL(string: "\(relayBaseUrl)/api/status?rid=\(rid)")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                approvedCount = json?["approvedCount"] as? Int ?? 0
                thresholdMet = json?["thresholdMet"] as? Bool ?? false

                if thresholdMet {
                    // Collect approved guardian keys from relay
                    if let keys = json?["guardianKeys"] as? [String] {
                        guardianKeys = keys
                    }
                    step = .timeLock
                    store.showToast("Guardian threshold met!")
                }
            } catch {
                store.showToast("Status check failed", type: .error)
            }
            polling = false
        }
    }

    private func executeRecovery() {
        recovering = true
        Task {
            do {
                // 1. Call initiate_recovery on-chain with guardian keys
                guard guardianKeys.count >= 2 else {
                    throw RecoveryError.insufficientGuardians
                }

                // Get the new key coordinates from the relay status
                let url = URL(string: "\(relayBaseUrl)/api/status?rid=\(recoveryId ?? "")")!
                let (statusData, _) = try await URLSession.shared.data(from: url)
                let statusJson = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]

                let newKeyX = statusJson?["newPubKeyX"] as? String ?? ""
                let newKeyY = statusJson?["newPubKeyY"] as? String ?? ""

                // 2. Call initiate_recovery via PXE bridge
                _ = try await pxeBridge.initiateRecovery(
                    newKeyX: newKeyX,
                    newKeyY: newKeyY,
                    guardianKeyA: guardianKeys[0],
                    guardianKeyB: guardianKeys[1]
                )

                store.showToast("Recovery initiated on-chain. 24h time-lock started.")

                // 3. After time-lock (in production, user comes back later)
                // For now, try execute_recovery immediately (will fail if time-lock not expired)
                // TODO: Add timer/reminder to come back after 24h

                // 4. Execute recovery (finalizes key rotation)
                _ = try await pxeBridge.executeRecovery(
                    newKeyX: newKeyX,
                    newKeyY: newKeyY
                )

                step = .complete
                store.showToast("Account recovered successfully!")
            } catch {
                store.showToast("Recovery failed: \(error.localizedDescription)", type: .error)
            }
            recovering = false
        }
    }
}

// MARK: - Errors

enum RecoveryError: LocalizedError {
    case keyGenerationFailed
    case relayRequestFailed
    case insufficientGuardians

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed: return "Failed to generate new signing key"
        case .relayRequestFailed: return "Relay server request failed"
        case .insufficientGuardians: return "Not enough guardian approvals"
        }
    }
}
