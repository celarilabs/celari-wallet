import SwiftUI

struct RecoverAccountViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @Environment(\.dismiss) private var dismiss

    enum Step { case input, waiting, timeLock, complete }

    @State private var step: Step = .input
    @State private var accountAddress = ""
    @State private var password = ""
    @State private var processing = false
    @State private var recoveryId = ""
    @State private var approvalCount = 0
    @State private var thresholdMet = false
    @State private var guardianStatuses: [Bool] = [false, false, false]
    @State private var newPubKeyX = ""
    @State private var newPubKeyY = ""
    @State private var polling = false
    @State private var pollAttempts = 0
    @State private var timeLockStart: Date?
    @State private var timeLockRemaining: String = "24:00:00"
    @State private var canExecuteChain: Bool = false
    @State private var recoveryDeadline: Date = .distantFuture

    private let relayBaseUrl = "https://recovery.celariwallet.com"
    private let maxPollAttempts = 120 // Max status checks before showing "contact guardians" message

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch step {
                    case .input:
                        inputStep
                    case .waiting:
                        waitingStep
                    case .timeLock:
                        timeLockStep
                    case .complete:
                        completeStep
                    }
                }
                .padding(24)
            }
            .background(V2Colors.bgCanvas)
            .navigationTitle("Recover Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.screen = .onboarding
                        dismiss()
                    }
                    .foregroundColor(V2Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Step 1: Input

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account Recovery")
                    .font(V2Fonts.heading(20))
                    .foregroundColor(V2Colors.textPrimary)
                Text("Enter your account address and recovery password to start the recovery process.")
                    .font(V2Fonts.body(14))
                    .foregroundColor(V2Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCOUNT ADDRESS")
                        .font(V2Fonts.label(10))
                        .tracking(1)
                        .foregroundColor(V2Colors.textTertiary)
                    TextField("0x...", text: $accountAddress)
                        .font(V2Fonts.mono(14))
                        .autocapitalization(.none)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.bgControl)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOVERY PASSWORD")
                        .font(V2Fonts.label(10))
                        .tracking(1)
                        .foregroundColor(V2Colors.textTertiary)
                    SecureField("Password", text: $password)
                        .font(V2Fonts.body(15))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(V2Colors.bgControl)
                        )
                }
            }

            Button {
                Task { await startRecovery() }
            } label: {
                HStack(spacing: 8) {
                    if processing {
                        ProgressView().tint(V2Colors.textWhite)
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Start Recovery")
                    }
                }
                .font(V2Fonts.bodySemibold(16))
                .foregroundColor(V2Colors.textWhite)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(!accountAddress.isEmpty && !password.isEmpty ? V2Colors.aztecDark : V2Colors.textDisabled)
                )
            }
            .disabled(accountAddress.isEmpty || password.isEmpty || processing)
        }
    }

    // MARK: - Step 2: Waiting for Guardians

    private var waitingStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 30)

            Image(systemName: "envelope.badge")
                .font(.system(size: 40))
                .foregroundColor(V2Colors.soOrange)

            Text("WAITING FOR GUARDIANS")
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.textTertiary)

            Text("Approval requests have been sent to your guardians. Ask 2 of 3 to approve.")
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Guardian approval indicators
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(guardianStatuses[i] ? V2Colors.successGreen : V2Colors.bgControl)
                            .overlay(
                                Image(systemName: guardianStatuses[i] ? "checkmark" : "person")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(guardianStatuses[i] ? V2Colors.textWhite : V2Colors.textMuted)
                            )
                            .frame(width: 44, height: 44)
                        Text("Guardian \(i + 1)")
                            .font(V2Fonts.mono(10))
                            .foregroundColor(V2Colors.textTertiary)
                    }
                }
            }

            Text("\(approvalCount)/2 approvals")
                .font(V2Fonts.monoSemibold(14))
                .foregroundColor(thresholdMet ? V2Colors.successGreen : V2Colors.soOrange)

            Button {
                Task { await checkStatus() }
            } label: {
                HStack(spacing: 8) {
                    if polling {
                        ProgressView().tint(V2Colors.soBlue)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Check Status")
                }
                .font(V2Fonts.bodyMedium(15))
                .foregroundColor(V2Colors.soBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(V2Colors.soBlue.opacity(0.1))
                )
            }
            .disabled(polling)

            Spacer()
        }
    }

    // MARK: - Step 3: Time-Lock

    private var timeLockStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "lock.badge.clock")
                .font(.system(size: 44))
                .foregroundColor(V2Colors.soOrange)

            Text("24H TIME-LOCK")
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.soOrange)

            Text("Guardian threshold reached. For security, there is a 24-hour waiting period before recovery can be finalized.")
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Countdown timer
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, recoveryDeadline.timeIntervalSince(context.date))
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                let seconds = Int(remaining) % 60

                VStack(spacing: 16) {
                    Text("Recovery Time-Lock")
                        .font(.headline)

                    Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(remaining > 0 ? Color.secondary : V2Colors.successGreen)

                    if remaining <= 0 {
                        Button {
                            Task { await finalizeRecovery() }
                        } label: {
                            HStack(spacing: 8) {
                                if processing {
                                    ProgressView().tint(V2Colors.textWhite)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                    Text("Finalize Recovery")
                                }
                            }
                            .font(V2Fonts.bodySemibold(16))
                            .foregroundColor(V2Colors.textWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(V2Colors.aztecDark)
                            )
                        }
                        .disabled(processing)
                    } else {
                        Text("Recovery will be available when countdown reaches zero")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .onAppear {
                if timeLockStart == nil { timeLockStart = Date() }
                // Seed deadline from local 24h timer if chain hasn't provided one yet
                if recoveryDeadline == .distantFuture, let start = timeLockStart {
                    recoveryDeadline = start.addingTimeInterval(86400)
                }
                Task { await refreshCountdownFromChain() }
            }

            Spacer()
        }
    }

    private var isTimeLockExpired: Bool {
        if canExecuteChain { return true }
        guard let start = timeLockStart else { return false }
        return Date().timeIntervalSince(start) >= 86400
    }

    // MARK: - Step 4: Complete

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(V2Colors.successGreen)

            Text("ACCOUNT RECOVERED")
                .font(V2Fonts.label(11))
                .tracking(2)
                .foregroundColor(V2Colors.successGreen)

            Text("Your account has been recovered with a new signing key. You can now use your wallet normally.")
                .font(V2Fonts.body(14))
                .foregroundColor(V2Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                store.screen = .dashboard
            } label: {
                Text("Go to Dashboard")
                    .font(V2Fonts.bodySemibold(16))
                    .foregroundColor(V2Colors.textWhite)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.aztecDark)
                    )
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func startRecovery() async {
        processing = true
        do {
            // Generate new key pair for the recovered account
            let keys = try await pxeBridge.generateKeys()
            newPubKeyX = keys["pubKeyX"] as? String ?? ""
            newPubKeyY = keys["pubKeyY"] as? String ?? ""

            // Send recovery request to relay
            guard let url = URL(string: "\(relayBaseUrl)/api/initiate") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "accountAddress": accountAddress,
                "newPubKeyX": newPubKeyX,
                "newPubKeyY": newPubKeyY
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rid = json["recoveryId"] as? String {
                recoveryId = rid
                step = .waiting
            }
        } catch {
            store.showToast("Recovery start failed: \(error.localizedDescription)", type: .error)
        }
        processing = false
    }

    private func checkStatus() async {
        pollAttempts += 1
        if pollAttempts > maxPollAttempts {
            store.showToast("Max status checks reached. Contact your guardians directly to approve.", type: .error)
            return
        }
        polling = true
        do {
            guard let url = URL(string: "\(relayBaseUrl)/api/status?rid=\(recoveryId)") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                approvalCount = json["approvalCount"] as? Int ?? 0
                thresholdMet = json["thresholdMet"] as? Bool ?? false
                if let statuses = json["guardianStatuses"] as? [Bool] {
                    guardianStatuses = statuses
                }
                if thresholdMet {
                    timeLockStart = Date()
                    step = .timeLock
                }
            }
        } catch {
            store.showToast("Status check failed (attempt \(pollAttempts)/\(maxPollAttempts))", type: .error)
        }
        polling = false
    }

    func refreshCountdownFromChain() async {
        do {
            let status = try await pxeBridge.checkRecoveryStatus()
            if let active = status["active"] as? Bool, active,
               let startBlock = status["startBlock"] as? Int,
               let currentBlock = status["currentBlock"] as? Int {
                let blocksRemaining = max(0, 7200 - (currentBlock - startBlock))
                let secondsRemaining = blocksRemaining * 12
                let hours = secondsRemaining / 3600
                let minutes = (secondsRemaining % 3600) / 60
                let secs = secondsRemaining % 60
                timeLockRemaining = String(format: "%02d:%02d:%02d", hours, minutes, secs)

                let remainingSeconds = Double(blocksRemaining) * 12.0  // ~12s per block
                recoveryDeadline = Date().addingTimeInterval(remainingSeconds)
                store.scheduleRecoveryNotification(deadline: recoveryDeadline)

                if blocksRemaining == 0 {
                    canExecuteChain = true
                }
            }
        } catch {
            // Silently fall back to local timer on failure
        }
    }

    private func finalizeRecovery() async {
        processing = true
        do {
            _ = try await pxeBridge.initiateRecovery(
                newKeyX: newPubKeyX,
                newKeyY: newPubKeyY,
                guardianKeyA: "",
                guardianKeyB: ""
            )
            _ = try await pxeBridge.executeRecovery(
                newKeyX: newPubKeyX,
                newKeyY: newPubKeyY
            )
            step = .complete
            store.showToast("Account recovered!")
        } catch {
            store.showToast("Recovery failed: \(error.localizedDescription)", type: .error)
        }
        processing = false
    }
}
