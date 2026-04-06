import Foundation
import os.log
import UserNotifications

private let guardianLog = Logger(subsystem: "com.celari.wallet", category: "GuardianManager")

// MARK: - GuardianManager
//
// Owns guardian recovery state, status checks, and notification scheduling
// that were previously scattered through WalletStore. WalletStore forwards
// via computed properties so all existing call sites remain unchanged.

@MainActor
@Observable
class GuardianManager {

    // MARK: - State

    var guardianStatus: GuardianStatus = .notSetup
    var guardians: [String] = []

    // MARK: - Dependencies

    private let persistence: WalletPersistence

    // MARK: - Initialization

    init(persistence: WalletPersistence) {
        self.persistence = persistence
        if let status = persistence.loadGuardianStatus() {
            guardianStatus = status
        }
        guardians = persistence.loadGuardians()
    }

    // MARK: - Guardian Status Check

    func checkGuardianStatus(pxeBridge: PXEBridge) async {
        do {
            let isConfigured = try await pxeBridge.isGuardianConfigured()
            if isConfigured {
                self.guardianStatus = .configured(guardianCount: 3)
                guardianLog.notice("[GuardianManager] Guardian recovery configured")

                // Check if recovery is active
                do {
                    let recoveryResult = try await pxeBridge.checkRecoveryStatus()
                    if let active = recoveryResult["active"] as? Bool, active {
                        let deadline = Date().addingTimeInterval(24 * 3600) // ~24h from now
                        self.guardianStatus = .recoveryPending(initiatedAt: Date(), deadline: deadline)
                        scheduleRecoveryNotification(deadline: deadline)
                        guardianLog.notice("[GuardianManager] Active recovery detected!")
                    }
                } catch {
                    // Recovery check failed, keep configured status
                }
            } else {
                self.guardianStatus = .notSetup
            }
        } catch {
            guardianLog.error("[GuardianManager] Guardian status check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Notification Scheduling

    func scheduleRecoveryNotification(deadline: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Recovery Alert"
        content.body = "A guardian recovery was initiated on your account. Cancel before \(deadline.formatted(.dateTime.hour().minute())) if this wasn't you."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "recovery-alert-\(UUID().uuidString.prefix(6))", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        // Schedule reminder 1 hour before deadline
        let reminderInterval = max(1, deadline.timeIntervalSinceNow - 3600)
        if reminderInterval > 1 {
            let reminder = UNMutableNotificationContent()
            reminder.title = "Recovery Deadline Approaching"
            reminder.body = "1 hour left to cancel the guardian recovery."
            reminder.sound = .defaultCritical

            let reminderTrigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderInterval, repeats: false)
            let reminderRequest = UNNotificationRequest(identifier: "recovery-reminder", content: reminder, trigger: reminderTrigger)
            UNUserNotificationCenter.current().add(reminderRequest)
        }

        guardianLog.notice("[GuardianManager] Recovery notification scheduled, deadline: \(deadline.formatted(), privacy: .public)")
    }

    // MARK: - Persistence

    func saveGuardianStatus() {
        persistence.saveGuardianStatus(guardianStatus, guardians: guardians)
    }
}
