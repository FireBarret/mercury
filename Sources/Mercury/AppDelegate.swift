import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private var imapClient: IMAPClient?
    private let notificationManager = NotificationManager()
    private let hotKeyManager = GlobalHotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationManager.requestAuthorization()

        statusBarController = StatusBarController(
            onCheckNow: { [weak self] in self?.imapClient?.checkNow() },
            onOpenGmail: { [weak self] in self?.openGmail() },
            onOpenMessage: { message in
                MessageOpener.open(messageID: message.messageID)
            },
            onTestNotification: { [weak self] in self?.notificationManager.sendTestNotification() },
            onMarkAllAsRead: { [weak self] in
                self?.statusBarController?.markAllAsReadOptimistically()
                self?.imapClient?.markAllAsRead()
            },
            onPreferences: { [weak self] in self?.showPreferences() },
            onQuit: { NSApp.terminate(nil) }
        )

        startClientIfConfigured()
        registerSavedShortcutIfNeeded()
    }

    private func registerSavedShortcutIfNeeded() {
        guard let keyCode = Settings.shortcutKeyCode, let modifiers = Settings.shortcutModifiers else { return }
        hotKeyManager.onHotKeyPressed = { [weak self] in self?.statusBarController?.showMenu() }
        hotKeyManager.register(keyCode: keyCode, carbonModifiers: modifiers)
    }

    private func openGmail() {
        if let url = URL(string: "https://mail.google.com") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startClientIfConfigured() {
        guard let email = Credentials.email, let password = Credentials.appPassword(for: email) else {
            showPreferences()
            return
        }
        startClient(email: email, password: password)
    }

    private func startClient(email: String, password: String) {
        imapClient?.stop()

        let client = IMAPClient(email: email, appPassword: password)
        client.onNewMail = { [weak self] messages in
            DispatchQueue.main.async {
                for message in messages {
                    self?.notificationManager.notifyNewMail(
                        from: message.from,
                        subject: message.subject,
                        messageID: message.messageID
                    )
                }
            }
            if !messages.isEmpty && Settings.autoRefreshMailApp {
                MailAppRefresher.refreshAndCloseIfNeeded()
            }
        }
        client.onUnreadCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.statusBarController?.updateUnreadCount(count)
            }
        }
        client.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusBarController?.updateConnectionStatus(status)
            }
        }
        client.onLatestMessagesChanged = { [weak self] messages in
            DispatchQueue.main.async {
                self?.statusBarController?.updateRecentMessages(messages)
            }
        }
        client.start()
        imapClient = client
    }

    private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                onSave: { [weak self] email, password in
                    Credentials.save(email: email, appPassword: password)
                    self?.startClient(email: email, password: password)
                },
                onShortcutChanged: { [weak self] keyCode, modifiers in
                    Settings.shortcutKeyCode = keyCode
                    Settings.shortcutModifiers = modifiers
                    guard let self = self else { return }
                    if let keyCode = keyCode, let modifiers = modifiers {
                        self.hotKeyManager.onHotKeyPressed = { [weak self] in self?.statusBarController?.showMenu() }
                        self.hotKeyManager.register(keyCode: keyCode, carbonModifiers: modifiers)
                    } else {
                        self.hotKeyManager.unregister()
                    }
                },
                onDisplaySettingsChanged: { [weak self] in self?.imapClient?.checkNow() }
            )
        }
        preferencesWindowController?.show()
    }
}
