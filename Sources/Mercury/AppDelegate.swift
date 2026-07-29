import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private var imapClients: [AccountSlot: IMAPClient] = [:]
    private var unreadCounts: [AccountSlot: Int] = [:]
    private var recentMessages: [AccountSlot: [MailHeader]] = [:]
    private let notificationManager = NotificationManager()
    private let hotKeyManager = GlobalHotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationManager.requestAuthorization()

        statusBarController = StatusBarController(
            onCheckNow: { [weak self] in self?.imapClients.values.forEach { $0.checkNow() } },
            onOpenGmail: { [weak self] in self?.openGmail() },
            onOpenMessage: { message in
                MessageOpener.open(messageID: message.messageID)
            },
            onTestNotification: { [weak self] in self?.notificationManager.sendTestNotification() },
            onMarkAllAsRead: { [weak self] in
                self?.statusBarController?.markAllAsReadOptimistically()
                self?.imapClients.values.forEach { $0.markAllAsRead() }
            },
            onPreferences: { [weak self] in self?.showPreferences() },
            onQuit: { NSApp.terminate(nil) }
        )

        startAllConfiguredClients()
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

    private func startAllConfiguredClients() {
        var startedAny = false
        for slot in AccountSlot.allCases {
            guard let email = Credentials.email(for: slot), let password = Credentials.appPassword(for: email) else {
                continue
            }
            startClient(email: email, password: password, slot: slot)
            startedAny = true
        }
        if !startedAny {
            showPreferences()
        }
    }

    private func startClient(email: String, password: String, slot: AccountSlot) {
        imapClients[slot]?.stop()

        let client = IMAPClient(email: email, appPassword: password)
        client.onNewMail = { [weak self] messages in
            DispatchQueue.main.async {
                for message in messages {
                    self?.notificationManager.notifyNewMail(
                        from: message.from,
                        subject: message.subject,
                        messageID: message.messageID,
                        accountEmail: message.accountEmail
                    )
                }
            }
            if !messages.isEmpty && Settings.autoRefreshMailApp {
                MailAppRefresher.refreshAndCloseIfNeeded()
            }
        }
        client.onUnreadCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.unreadCounts[slot] = count
                self?.refreshStatusBar()
            }
        }
        client.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusBarController?.updateConnectionStatus(status)
            }
        }
        client.onLatestMessagesChanged = { [weak self] messages in
            DispatchQueue.main.async {
                self?.recentMessages[slot] = messages
                self?.refreshStatusBar()
            }
        }
        client.start()
        imapClients[slot] = client
    }

    private func stopClient(slot: AccountSlot) {
        imapClients[slot]?.stop()
        imapClients[slot] = nil
        unreadCounts[slot] = nil
        recentMessages[slot] = nil
    }

    /// Rebuilds the combined menu-bar/menu state from whichever accounts
    /// are currently running. Called every time either account reports new
    /// counts or messages, so the two stay in sync in the shared UI.
    private func refreshStatusBar() {
        let accounts: [AccountDisplayState] = AccountSlot.allCases.compactMap { slot in
            guard let email = Credentials.email(for: slot), imapClients[slot] != nil else { return nil }
            return AccountDisplayState(
                slot: slot,
                email: email,
                unreadCount: unreadCounts[slot] ?? 0,
                recentMessages: recentMessages[slot] ?? []
            )
        }
        statusBarController?.update(accounts: accounts)
    }

    private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                onSaveAccount: { [weak self] email, password, slot in
                    Credentials.save(email: email, appPassword: password, slot: slot)
                    self?.startClient(email: email, password: password, slot: slot)
                },
                onRemoveAccount: { [weak self] slot in
                    Credentials.clear(slot: slot)
                    self?.stopClient(slot: slot)
                    self?.refreshStatusBar()
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
                onDisplaySettingsChanged: { [weak self] in self?.imapClients.values.forEach { $0.checkNow() } }
            )
        }
        preferencesWindowController?.show()
    }
}
