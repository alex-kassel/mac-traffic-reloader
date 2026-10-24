import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let err = error {
                Logger.log("[NotificationManager] Permission error: %@", err.localizedDescription)
            } else {
                Logger.log("[NotificationManager] Notification permission: %@", granted ? "AUTHORIZED" : "DENIED")
            }
        }
    }

    func send(title: String, body: String) {
        guard ConfigManager.shared.config.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let err = error {
                Logger.log("[NotificationManager] Error posting notification: %@", err.localizedDescription)
            }
        }
    }
}
