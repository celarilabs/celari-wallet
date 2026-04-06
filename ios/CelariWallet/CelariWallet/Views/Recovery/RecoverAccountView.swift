import SwiftUI

/// Account recovery screen for a new device.
/// User enters account address + recovery password + guardian keys to start the process.
/// Guardian keys are obtained out-of-band from the guardians who received them during setup.
struct RecoverAccountView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var accountAddress = ""
    @State private var recoveryPassword = ""
    @State private var guardianKeyA = ""
    @State private var guardianKeyB = ""
    @State private var recovering = false
    @State private var step: RecoveryStep = .input
    @State private var newPubKeyX = ""
    @State private var newPubKeyY = ""

    // 24h countdown timer
    @State private var countdownText = ""
    @State private var timeLockReady = false
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let recoveryStartKey = "celari_recovery_start_time"
    private static let timeLockDuration: TimeInterval = 24 * 60 * 60 // 24 hours

    enum RecoveryStep {
        case input            // Enter address + password + guardian keys
        case timeLock         // 24h waiting period after initiate_recovery
        case complete         // Recovery done
    }

    // Relay server — not yet deployed, kept for future use
    // private let relayBaseUrl = "https://recovery.celariwallet.com"

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Recover Account")

            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .input:
                        inputView
                    case .timeLock:
                        timeLockView
                    case .complete:
                        completeView
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            restoreTimeLockState()
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

                Text("Enter your account address, recovery password, and two guardian keys to start the recovery process.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(CelariColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DecoSeparator()

            FormField(label: "Account Address", text: $accountAddress, placeholder: "0x...")
            FormField(label: "Recovery Password", text: $recoveryPassword, placeholder: "Your recovery password", isSecure: true)

            DecoSeparator()

            VStack(alignment: .leading, spacing: 8) {
                Text("GUARDIAN KEYS")
                    .font(CelariTypography.monoLabel)
                    .tracking(2)
                    .foregroundColor(CelariColors.textDim)

                Text("Ask two of your guardians for their keys. These are the 64-character hex strings they received during guardian setup.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CelariColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FormField(label: "Guardian Key A", text: $guardianKeyA, placeholder: "64-char hex from Guardian A")
            FormField(label: "Guardian Key B", text: $guardianKeyB, placeholder: "64-char hex from Guardian B")

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
            .disabled(!isInputValid || recovering)
            .opacity(isInputValid ? 1 : 0.5)
        }
    }

    private var timeLockView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.badge.clock")
                .font(.system(size: 40))
                .foregroundColor(timeLockReady ? CelariColors.green : CelariColors.copper)

            Text(timeLockReady ? "TIME-LOCK COMPLETE" : "24H TIME-LOCK")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(timeLockReady ? CelariColors.green : CelariColors.textDim)

            Text(timeLockReady
                 ? "The 24-hour safety period has passed. You can now finalize the recovery."
                 : "Recovery initiated on-chain. The original owner can cancel during this 24-hour safety period.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CelariColors.textMuted)
                .multilineTextAlignment(.center)

            DecoSeparator()

            // Countdown display
            VStack(spacing: 8) {
                Text(timeLockReady ? "READY" : "TIME REMAINING")
                    .font(CelariTypography.monoTiny)
                    .tracking(1)
                    .foregroundColor(CelariColors.textFaint)

                Text(timeLockReady ? "00:00:00" : countdownText)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(timeLockReady ? CelariColors.green : CelariColors.copper)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(CelariColors.bgInput)
            .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
            .onReceive(countdownTimer) { _ in
                updateCountdown()
            }

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
            .disabled(!timeLockReady || recovering)
            .opacity(timeLockReady ? 1 : 0.5)
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
                clearTimeLockState()
                store.screen = .dashboard
            } label: {
                Text("Go to Dashboard")
            }
            .buttonStyle(CelariPrimaryButtonStyle())
        }
    }

    // MARK: - Validation

    private var isInputValid: Bool {
        !accountAddress.isEmpty
            && !recoveryPassword.isEmpty
            && guardianKeyA.count == 64
            && guardianKeyB.count == 64
    }

    // MARK: - 24h Countdown Timer

    private func saveTimeLockStart() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.recoveryStartKey)
        // Also persist the new key coordinates for execute step
        UserDefaults.standard.set(newPubKeyX, forKey: "celari_recovery_newKeyX")
        UserDefaults.standard.set(newPubKeyY, forKey: "celari_recovery_newKeyY")
    }

    private func restoreTimeLockState() {
        let startTime = UserDefaults.standard.double(forKey: Self.recoveryStartKey)
        guard startTime > 0 else { return }

        // Restore persisted key coordinates
        newPubKeyX = UserDefaults.standard.string(forKey: "celari_recovery_newKeyX") ?? ""
        newPubKeyY = UserDefaults.standard.string(forKey: "celari_recovery_newKeyY") ?? ""

        // Only restore to timeLock step if we have valid keys
        guard !newPubKeyX.isEmpty, !newPubKeyY.isEmpty else { return }

        step = .timeLock
        updateCountdown()
    }

    private func updateCountdown() {
        let startTime = UserDefaults.standard.double(forKey: Self.recoveryStartKey)
        guard startTime > 0 else {
            countdownText = "--:--:--"
            return
        }

        let elapsed = Date().timeIntervalSince1970 - startTime
        let remaining = Self.timeLockDuration - elapsed

        if remaining <= 0 {
            timeLockReady = true
            countdownText = "00:00:00"
        } else {
            timeLockReady = false
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let seconds = Int(remaining) % 60
            countdownText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }

    private func clearTimeLockState() {
        UserDefaults.standard.removeObject(forKey: Self.recoveryStartKey)
        UserDefaults.standard.removeObject(forKey: "celari_recovery_newKeyX")
        UserDefaults.standard.removeObject(forKey: "celari_recovery_newKeyY")
    }

    // MARK: - Actions

    private func startRecovery() {
        recovering = true
        Task {
            do {
                // 1. Generate new P256 key pair for this device
                let keyResult = try await pxeBridge.generateKeys()
                guard let pubKeyX = keyResult["publicKeyX"] as? String,
                      let pubKeyY = keyResult["publicKeyY"] as? String else {
                    throw RecoveryError.keyGenerationFailed
                }
                newPubKeyX = pubKeyX
                newPubKeyY = pubKeyY

                // 2. Use manually entered guardian keys (relay server fallback below)
                let keyA = guardianKeyA.hasPrefix("0x") ? guardianKeyA : guardianKeyA
                let keyB = guardianKeyB.hasPrefix("0x") ? guardianKeyB : guardianKeyB

                // 3. Call initiate_recovery on-chain with guardian keys
                _ = try await pxeBridge.initiateRecovery(
                    newKeyX: newPubKeyX,
                    newKeyY: newPubKeyY,
                    guardianKeyA: keyA,
                    guardianKeyB: keyB
                )

                // 4. Persist the recovery start time for 24h countdown
                saveTimeLockStart()

                step = .timeLock
                updateCountdown()
                store.showToast("Recovery initiated. 24h time-lock started.")

                // --- Relay server path (not yet deployed) ---
                // When recovery.celariwallet.com is live, uncomment below to send
                // recovery requests via the relay instead of manual key entry:
                //
                // let body: [String: Any] = [
                //     "accountAddress": accountAddress,
                //     "newPubKeyX": newPubKeyX,
                //     "newPubKeyY": newPubKeyY,
                //     "guardians": [
                //         ["email": "guardian@example.com"]
                //     ]
                // ]
                // let url = URL(string: "\(relayBaseUrl)/api/initiate")!
                // var request = URLRequest(url: url)
                // request.httpMethod = "POST"
                // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // request.httpBody = try JSONSerialization.data(withJSONObject: body)
                // let (data, response) = try await URLSession.shared.data(for: request)
                // guard let httpResponse = response as? HTTPURLResponse,
                //       httpResponse.statusCode == 200 else {
                //     throw RecoveryError.relayRequestFailed
                // }
                // let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                // recoveryId = json?["recoveryId"] as? String
            } catch {
                store.showToast("Recovery failed: \(error.localizedDescription)", type: .error)
            }
            recovering = false
        }
    }

    private func executeRecovery() {
        recovering = true
        Task {
            do {
                // Restore keys from persistence if needed
                let keyX = newPubKeyX.isEmpty
                    ? (UserDefaults.standard.string(forKey: "celari_recovery_newKeyX") ?? "")
                    : newPubKeyX
                let keyY = newPubKeyY.isEmpty
                    ? (UserDefaults.standard.string(forKey: "celari_recovery_newKeyY") ?? "")
                    : newPubKeyY

                guard !keyX.isEmpty, !keyY.isEmpty else {
                    throw RecoveryError.keyGenerationFailed
                }

                // Execute recovery (finalizes key rotation after 24h time-lock)
                _ = try await pxeBridge.executeRecovery(
                    newKeyX: keyX,
                    newKeyY: keyY
                )

                clearTimeLockState()
                step = .complete
                store.showToast("Account recovered successfully!")

                // --- Relay server path (not yet deployed) ---
                // When recovery.celariwallet.com is live, the relay can supply
                // key coordinates and guardian keys from its stored session:
                //
                // let url = URL(string: "\(relayBaseUrl)/api/status?rid=\(recoveryId ?? "")")!
                // let (statusData, _) = try await URLSession.shared.data(from: url)
                // let statusJson = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
                // let newKeyX = statusJson?["newPubKeyX"] as? String ?? ""
                // let newKeyY = statusJson?["newPubKeyY"] as? String ?? ""
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
