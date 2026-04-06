import Foundation
import UserNotifications
import os

private let notifLog = Logger(subsystem: "com.celari.wallet", category: "Notifications")

/// Manages local and remote push notifications for Celari Wallet.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            notifLog.notice("[Notifications] Permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        } catch {
            notifLog.error("[Notifications] Permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Local Notifications

    func notifyTransactionConfirmed(token: String, amount: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transfer Confirmed"
        content.body = "Your transfer of \(amount) \(token) has been confirmed."
        content.sound = .default

        schedule(content: content, id: "tx-confirmed-\(UUID().uuidString.prefix(6))")
    }

    func notifyTransactionFailed(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transfer Failed"
        content.body = reason
        content.sound = .default

        schedule(content: content, id: "tx-failed-\(UUID().uuidString.prefix(6))")
    }

    func notifyBridgeClaimReady(token: String, amount: String) {
        let content = UNMutableNotificationContent()
        content.title = "Bridge Deposit Ready"
        content.body = "Your \(amount) \(token) is ready to claim on Aztec."
        content.sound = .default

        schedule(content: content, id: "bridge-claim-\(UUID().uuidString.prefix(6))")
    }

    func notifyWalletConnectRequest(dappName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Connection Request"
        content.body = "\(dappName) wants to connect to your wallet."
        content.sound = .default

        schedule(content: content, id: "wc-request-\(UUID().uuidString.prefix(6))")
    }

    // MARK: - Delegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        notifLog.notice("[Notifications] User tapped: \(response.notification.request.identifier, privacy: .public)")
    }

    // MARK: - Private

    private func schedule(content: UNMutableNotificationContent, id: String, delay: TimeInterval = 1) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                notifLog.error("[Notifications] Schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
