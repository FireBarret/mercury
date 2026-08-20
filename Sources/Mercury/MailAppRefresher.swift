import AppKit

/// Keeps Mail.app's local store in sync with new mail as it arrives, per
/// Settings.mailAppRefreshMode, so its own search / the "open in Mail.app"
/// links resolve without a long wait instead of needing a manual refresh.
/// Never disrupts a session the user started themselves beyond asking it to
/// check for new mail -- launching, hiding, or quitting only ever applies
/// to an instance Mercury itself started.
///
/// The .quitAfterRefresh and .hideAfterRefresh modes' first use triggers a
/// one-time macOS "Mercury wants to control Mail" permission prompt
/// (Automation), which needs approval.
enum MailAppRefresher {
    private static let mailBundleID = "com.apple.mail"
    private static var isRefreshing = false
    private static let queue = DispatchQueue(label: "MailAppRefresher")

    static func refresh() {
        let mode = Settings.mailAppRefreshMode
        guard mode != .disabled else { return }

        queue.async {
            guard !isRefreshing else { return }
            isRefreshing = true
            defer { isRefreshing = false }

            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID).isEmpty

            if mode == .refreshIfAlreadyOpen {
                guard wasRunning else { return }
                runAppleScript("tell application \"Mail\" to check for new mail")
                return
            }

            guard let mailURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mailBundleID) else {
                NSLog("MailAppRefresher: Mail.app not found")
                return
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false

            let launchSemaphore = DispatchSemaphore(value: 0)
            var launchedApp: NSRunningApplication?
            NSWorkspace.shared.openApplication(at: mailURL, configuration: config) { app, error in
                launchedApp = app
                if let error = error {
                    NSLog("MailAppRefresher: failed to launch Mail: \(error)")
                }
                launchSemaphore.signal()
            }
            launchSemaphore.wait()

            // Give Mail a moment to finish launching and become scriptable.
            Thread.sleep(forTimeInterval: 3)
            runAppleScript("tell application \"Mail\" to check for new mail")

            // Only ever hide/quit an instance we just launched ourselves --
            // if it was already running, leave it exactly as the user had it.
            guard !wasRunning else { return }

            switch mode {
            case .hideAfterRefresh:
                // Hiding doesn't interrupt syncing the way quitting would,
                // so there's no need to wait as long as the quit path does.
                Thread.sleep(forTimeInterval: 3)
                let app = launchedApp ?? NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID).first
                app?.hide()
            case .quitAfterRefresh:
                // Give it real time to finish syncing before quitting, since
                // quitting stops everything mid-sync otherwise.
                Thread.sleep(forTimeInterval: 10)
                runAppleScript("tell application \"Mail\" to quit")
            case .refreshIfAlreadyOpen, .disabled:
                break
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
