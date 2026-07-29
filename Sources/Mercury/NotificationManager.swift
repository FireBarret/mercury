import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        // Without a delegate, macOS silently suppresses the banner whenever
        // it doesn't consider the app "in the background" (which a menubar
        // accessory app frequently isn't) — this is what was swallowing
        // every notification. Implementing willPresent forces it to show.
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("Mercury: notification authorization error: \(error)")
            } else {
                NSLog("Mercury: notification authorization granted: \(granted)")
            }
        }
    }

    func notifyNewMail(from: String, subject: String, messageID: String?, accountEmail: String) {
        let content = UNMutableNotificationContent()
        if Settings.showPreviews {
            content.title = from.isEmpty ? "New Mail" : from
            content.body = subject.isEmpty ? "(no subject)" : subject
        } else {
            content.title = "New Mail"
            content.body = "You have a new message"
        }
        content.sound = .default
        if let messageID = messageID {
            content.userInfo = ["messageID": messageID]
        }
        // Only worth labeling which inbox it came from when there's more
        // than one configured -- otherwise it's just noise.
        if Credentials.email(for: .secondary) != nil {
            content.subtitle = accountEmail
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("Mercury: failed to deliver notification: \(error)")
            }
        }
    }

    func sendTestNotification() {
        notifyNewMail(
            from: "Mercury",
            subject: "This is a test notification 🎉",
            messageID: nil,
            accountEmail: Credentials.email(for: .primary) ?? ""
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Fired when the user clicks a notification — jump straight to that
    /// message instead of leaving them to go find it themselves.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        MessageOpener.open(messageID: response.notification.request.content.userInfo["messageID"] as? String)
        completionHandler()
    }
}
