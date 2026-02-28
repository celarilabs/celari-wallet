import SwiftUI

/// Account recovery screen for a new device.
/// User enters account address + recovery password to start the process.
struct RecoverAccountView: View {
    @Environment(WalletStore.self) private var store
    @State private var accountAddress = ""
    @State private var recoveryPassword = ""
    @State private var recovering = false
    @State private var recoveryId: String?
    @State private var approvedCount = 0
    @State private var thresholdMet = false
    @State private var step: RecoveryStep = .input

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

            // Refresh button
            Button {
                checkStatus()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("CHECK STATUS")
                        .font(CelariTypography.monoTiny)
                        .tracking(1)
                }
                .foregroundColor(CelariColors.textDim)
            }
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

            // TODO: Countdown timer

            Button {
                executeRecovery()
            } label: {
                Text("Finalize Recovery")
            }
            .buttonStyle(CelariPrimaryButtonStyle())
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
                // 1. Fetch CID from chain (TODO: read from contract)
                // let cid = try await pxeBridge.call("get_recovery_cid", accountAddress)

                // 2. Download encrypted bundle from IPFS (TODO)
                // let encryptedBundle = try await IPFSManager.download(cid)

                // 3. Decrypt with recovery password (TODO)
                // let bundle = try BackupManager.decryptAsync(encryptedBundle, password: recoveryPassword)

                // 4. Generate new P256 key pair for this device
                // let newKeyPair = P256.Signing.PrivateKey()

                // 5. Send recovery request to relay server
                // let response = try await sendToRelay(...)
                // recoveryId = response.recoveryId

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
        Task {
            // TODO: Poll relay server for approval status
            // GET /api/status?rid=\(rid)
            // Update approvedCount and check thresholdMet
            if thresholdMet {
                step = .timeLock
            }
        }
    }

    private func executeRecovery() {
        Task {
            // TODO: Submit on-chain execute_recovery transaction
            // This calls the contract's execute_recovery() function
            // which reads the matured SharedMutable values and
            // replaces the signing key.
            step = .complete
        }
    }
}
