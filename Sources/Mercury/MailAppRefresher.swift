import AppKit

/// Every time new mail is detected, briefly opens Mail.app in the
/// background (without stealing focus), asks it to check for new mail so
/// its local store catches up, then quits it again — but only if Mail
/// wasn't already running, so a session the user started themselves is
/// never interrupted.
///
/// First use will trigger a one-time macOS "Mail Notification Buddy wants
/// to control Mail" permission prompt (Automation), which needs approval.
enum MailAppRefresher {
    private static let mailBundleID = "com.apple.mail"
    private static var isRefreshing = false
    private static let queue = DispatchQueue(label: "MailAppRefresher")

    static func refreshAndCloseIfNeeded() {
        queue.async {
            guard !isRefreshing else { return }
            isRefreshing = true
            defer { isRefreshing = false }

            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID).isEmpty

            guard let mailURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mailBundleID) else {
                NSLog("MailAppRefresher: Mail.app not found")
                return
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false

            let launchSemaphore = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: mailURL, configuration: config) { _, error in
                if let error = error {
                    NSLog("MailAppRefresher: failed to launch Mail: \(error)")
                }
                launchSemaphore.signal()
            }
            launchSemaphore.wait()

            // Give Mail a moment to finish launching and become scriptable.
            Thread.sleep(forTimeInterval: 3)
            runAppleScript("tell application \"Mail\" to check for new mail")

            // Give it time to actually sync before we potentially quit it.
            Thread.sleep(forTimeInterval: 10)

            if !wasRunning {
                runAppleScript("tell application \"Mail\" to quit")
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&errorDict)
            if let errorDict = errorDict {
                NSLog("MailAppRefresher: AppleScript error: \(errorDict)")
            }
        }
    }
}
