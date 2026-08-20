import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private var imapClients: [AccountSlot: IMAPClient] = [:]
    private var unreadCounts: [AccountSlot: Int] = [:]
    private var recentMessages: [AccountSlot: [MailHeader]] = [:]
    private let notificationManager = NotificationManager()
    private let hotKeyManager = GlobalHotKeyManager()
    private var notificationsPausedUntil: Date?

    private var notificationsPaused: Bool {
        guard let until = notificationsPausedUntil else { return false }
        return until > Date()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationManager.requestAuthorization()

        statusBarController = StatusBarController(
            onCheckNow: { [weak self] in self?.imapClients.values.forEach { $0.checkNow() } },
            onOpenGmail: { [weak self] in self?.openGmail() },
            onOpenMessageInGmail: { message in
                MessageOpener.openInGmailBrowser(messageID: message.messageID)
            },
            onOpenMessageInMailApp: { message in
                MessageOpener.openInMailApp(messageID: message.messageID)
            },
            onTestNotification: { [weak self] in self?.notificationManager.sendTestNotification() },
            onMarkAllAsRead: { [weak self] in
                self?.statusBarController?.markAllAsReadOptimistically()
                self?.imapClients.values.forEach { $0.markAllAsRead() }
            },
            onTogglePauseNotifications: { [weak self] in self?.togglePauseNotifications() },
            onFlagMessage: { [weak self] message, flagged in
                guard let uid = message.uid else { return }
                self?.imapClient(forAccountEmail: message.accountEmail)?.setFlag(uid: uid, flag: "\\Flagged", on: flagged)
            },
            onMarkReadMessage: { [weak self] message, markAsRead in
                guard let uid = message.uid else { return }
                self?.imapClient(forAccountEmail: message.accountEmail)?.setFlag(uid: uid, flag: "\\Seen", on: markAsRead)
            },
            onCopyCode: { [weak self] message in self?.copyCode(from: message) },
            onCheckLinks: { [weak self] message in self?.checkLinks(in: message) },
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

    /// Toggles a 1-hour notification pause. Only silences banners -- badge
    /// counts, the recent-message list, and the Mail.app auto-refresh all
    /// keep working normally, since the point is not missing mail, just not
    /// being interrupted by it for a while.
    private func togglePauseNotifications() {
        if notificationsPaused {
            notificationsPausedUntil = nil
        } else {
            let until = Date().addingTimeInterval(3600)
            notificationsPausedUntil = until
            DispatchQueue.main.asyncAfter(deadline: .now() + 3600) { [weak self] in
                guard let self = self, self.notificationsPausedUntil == until else { return }
                self.notificationsPausedUntil = nil
                self.statusBarController?.updatePauseState(isPaused: false)
            }
        }
        statusBarController?.updatePauseState(isPaused: notificationsPaused)
    }

    private func imapClient(forAccountEmail email: String) -> IMAPClient? {
        for slot in AccountSlot.allCases where Credentials.email(for: slot) == email {
            return imapClients[slot]
        }
        return nil
    }

    private func copyCode(from message: MailHeader) {
        guard let uid = message.uid, let client = imapClient(forAccountEmail: message.accountEmail) else {
            notificationManager.notifyQuickActionResult(title: "Copy Code", body: "Couldn't fetch that message.")
            return
        }
        client.fetchMessageBody(uid: uid) { [weak self] rawBody in
            guard let rawBody = rawBody else {
                self?.notificationManager.notifyQuickActionResult(title: "Copy Code", body: "Couldn't fetch that message.")
                return
            }
            let text = MessageBodyParser.extractPlainText(fromRawMessage: rawBody)
            guard let code = MessageBodyParser.findOTPCode(inText: text) else {
                self?.notificationManager.notifyQuickActionResult(title: "Copy Code", body: "No code found in that message.")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            self?.notificationManager.notifyQuickActionResult(title: "Copy Code", body: "Copied \"\(code)\" to the clipboard.")
        }
    }

    private func checkLinks(in message: MailHeader) {
        guard let uid = message.uid, let client = imapClient(forAccountEmail: message.accountEmail) else {
            notificationManager.notifyQuickActionResult(title: "Check for Links", body: "Couldn't fetch that message.")
            return
        }
        client.fetchMessageBody(uid: uid) { [weak self] rawBody in
            guard let rawBody = rawBody else {
                self?.notificationManager.notifyQuickActionResult(title: "Check for Links", body: "Couldn't fetch that message.")
                return
            }
            let links = MessageBodyParser.extractLinks(fromRawMessage: rawBody)
            guard !links.isEmpty else {
                self?.notificationManager.notifyQuickActionResult(title: "Check for Links", body: "No links found in that message.")
                return
            }
            self?.statusBarController?.showLinkPicker(links: links)
        }
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
                guard let self = self, !self.notificationsPaused, Credentials.notificationsEnabled(for: slot) else { return }
                for message in messages {
                    self.notificationManager.notifyNewMail(
                        from: message.from,
                        subject: message.subject,
                        messageID: message.messageID,
                        accountLabel: Credentials.displayName(for: slot)
                    )
                }
            }
            if !messages.isEmpty {
                MailAppRefresher.refresh()
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
                displayName: Credentials.displayName(for: slot),
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
                onDisplaySettingsChanged: { [weak self] in
                    // Local-only changes (e.g. a rename) show up immediately by
                    // re-rendering already-cached data; checkNow() additionally
                    // covers the min/max-count case, which needs a real refresh
                    // to actually fetch more or fewer messages.
                    self?.statusBarController?.applyInterfaceMode()
                    self?.refreshStatusBar()
                    self?.imapClients.values.forEach { $0.checkNow() }
                }
            )
        }
        preferencesWindowController?.show()
    }
}
