import AppKit

struct AccountDisplayState {
    let slot: AccountSlot
    let email: String
    let displayName: String
    let unreadCount: Int
    let recentMessages: [MailHeader]
}

final class StatusBarController {
    // .variableLength lets the button's width track its actual content
    // (image + title) automatically -- important now that the dual-account
    // count is real title text of varying width, not a fixed-size bitmap.
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusLabelItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let recentHeaderItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
    private let recentHeaderItem2 = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let interSectionDivider = NSMenuItem.separator()
    private var recentItems: [NSMenuItem] = []
    private var recentItems2: [NSMenuItem] = []
    private var lastAccounts: [AccountDisplayState] = []

    private let pauseNotificationsItem = NSMenuItem(title: "Pause Notifications (1h)", action: nil, keyEquivalent: "")

    private let onCheckNow: () -> Void
    private let onOpenGmail: () -> Void
    private let onOpenMessageInGmail: (MailHeader) -> Void
    private let onOpenMessageInMailApp: (MailHeader) -> Void
    private let onTestNotification: () -> Void
    private let onMarkAllAsRead: () -> Void
    private let onTogglePauseNotifications: () -> Void
    private let onFlagMessage: (MailHeader, Bool) -> Void
    private let onMarkReadMessage: (MailHeader, Bool) -> Void
    private let onCopyCode: (MailHeader) -> Void
    private let onCheckLinks: (MailHeader) -> Void
    private let onPreferences: () -> Void
    private let onQuit: () -> Void

    init(onCheckNow: @escaping () -> Void,
         onOpenGmail: @escaping () -> Void,
         onOpenMessageInGmail: @escaping (MailHeader) -> Void,
         onOpenMessageInMailApp: @escaping (MailHeader) -> Void,
         onTestNotification: @escaping () -> Void,
         onMarkAllAsRead: @escaping () -> Void,
         onTogglePauseNotifications: @escaping () -> Void,
         onFlagMessage: @escaping (MailHeader, Bool) -> Void,
         onMarkReadMessage: @escaping (MailHeader, Bool) -> Void,
         onCopyCode: @escaping (MailHeader) -> Void,
         onCheckLinks: @escaping (MailHeader) -> Void,
         onPreferences: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onCheckNow = onCheckNow
        self.onOpenGmail = onOpenGmail
        self.onOpenMessageInGmail = onOpenMessageInGmail
        self.onOpenMessageInMailApp = onOpenMessageInMailApp
        self.onTestNotification = onTestNotification
        self.onMarkAllAsRead = onMarkAllAsRead
        self.onTogglePauseNotifications = onTogglePauseNotifications
        self.onFlagMessage = onFlagMessage
        self.onMarkReadMessage = onMarkReadMessage
        self.onCopyCode = onCopyCode
        self.onCheckLinks = onCheckLinks
        self.onPreferences = onPreferences
        self.onQuit = onQuit

        statusItem.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Mail")
        statusItem.button?.imagePosition = .imageLeft

        statusLabelItem.isEnabled = false
        recentHeaderItem.isEnabled = false
        recentHeaderItem.isHidden = true
        recentHeaderItem2.isEnabled = false
        recentHeaderItem2.isHidden = true
        interSectionDivider.isHidden = true

        menu.addItem(statusLabelItem)
        menu.addItem(.separator())
        menu.addItem(recentHeaderItem)
        // Section-1 recent-message items get inserted here dynamically, right after recentHeaderItem.
        menu.addItem(interSectionDivider)
        menu.addItem(recentHeaderItem2)
        // Section-2 (second account) recent-message items get inserted here, right after recentHeaderItem2.
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Check Now", action: #selector(checkNowTapped)))
        menu.addItem(makeItem(title: "Open Gmail", action: #selector(openGmailTapped)))
        pauseNotificationsItem.target = self
        pauseNotificationsItem.action = #selector(togglePauseNotificationsTapped)
        menu.addItem(pauseNotificationsItem)
        menu.addItem(makeItem(title: "Send Test Notification", action: #selector(testNotificationTapped)))
        menu.addItem(makeItem(title: "Mark All as Read", action: #selector(markAllAsReadTapped)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Preferences…", action: #selector(preferencesTapped), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func checkNowTapped() { onCheckNow() }
    @objc private func openGmailTapped() { onOpenGmail() }
    @objc private func testNotificationTapped() { onTestNotification() }
    @objc private func markAllAsReadTapped() { onMarkAllAsRead() }
    @objc private func togglePauseNotificationsTapped() { onTogglePauseNotifications() }
    @objc private func preferencesTapped() { onPreferences() }
    @objc private func quitTapped() { onQuit() }

    @objc private func openInGmailTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onOpenMessageInGmail(message)
    }

    @objc private func openInMailAppTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onOpenMessageInMailApp(message)
    }

    func updateConnectionStatus(_ status: String) {
        statusItem.button?.toolTip = status
    }

    func updatePauseState(isPaused: Bool) {
        pauseNotificationsItem.title = isPaused ? "Resume Notifications" : "Pause Notifications (1h)"
    }

    /// Pops the menu open as if the status item had been clicked — used by
    /// the global keyboard shortcut. Arrow-key navigation once it's open is
    /// native NSMenu behavior, no extra code needed.
    func showMenu() {
        NSLog("Mercury: global shortcut fired, opening menu")
        statusItem.button?.performClick(nil)
    }

    /// Renders 1 or 2 configured accounts. With 1 account this looks exactly
    /// like before (plain template envelope icon + numeric text, single
    /// "Recent" section). With 2, the icon stays the same genuine template
    /// image, and the count becomes two colored numbers as the button's
    /// title -- e.g. "5 · 2" in blue/orange -- the same proven text-badge
    /// mechanism the 1-account case already uses, rather than hand-drawn
    /// graphical badges that don't have room to look clean at menu-bar
    /// scale. The "Recent" section splits into two, each labeled with that
    /// account's display name (custom, or "Mail 1"/"Mail 2" by default).
    func update(accounts: [AccountDisplayState]) {
        lastAccounts = accounts
        let showRecent = Settings.showRecentMessagesInMenu

        guard !accounts.isEmpty else {
            statusItem.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Mail")
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusLabelItem.title = "Not signed in"
            renderSection(header: recentHeaderItem, items: &recentItems, messages: [], headerTitle: "Recent")
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: [], headerTitle: "")
            interSectionDivider.isHidden = true
            return
        }

        if accounts.count == 1 {
            let account = accounts[0]
            statusItem.button?.image = NSImage(
                systemSymbolName: account.unreadCount > 0 ? "envelope.fill" : "envelope",
                accessibilityDescription: "Mail"
            )
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.title = account.unreadCount > 0 ? " \(account.unreadCount)" : ""
            statusLabelItem.title = account.unreadCount > 0 ? "\(account.unreadCount) unread" : "No unread mail"

            renderSection(header: recentHeaderItem, items: &recentItems, messages: showRecent ? account.recentMessages : [], headerTitle: "Recent")
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: [], headerTitle: "")
            interSectionDivider.isHidden = true
        } else {
            let primary = accounts.first { $0.slot == .primary } ?? accounts[0]
            let secondary = accounts.first { $0.slot == .secondary } ?? accounts[1]
            let hasAnyUnread = primary.unreadCount > 0 || secondary.unreadCount > 0

            statusItem.button?.image = NSImage(
                systemSymbolName: hasAnyUnread ? "envelope.fill" : "envelope",
                accessibilityDescription: "Mail"
            )
            statusItem.button?.title = ""
            statusItem.button?.attributedTitle = dualCountTitle(primary: primary.unreadCount, secondary: secondary.unreadCount)

            let total = primary.unreadCount + secondary.unreadCount
            statusLabelItem.title = total > 0 ? "\(total) unread total" : "No unread mail"

            renderSection(header: recentHeaderItem, items: &recentItems, messages: showRecent ? primary.recentMessages : [], headerTitle: primary.displayName)
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: showRecent ? secondary.recentMessages : [], headerTitle: secondary.displayName)
            interSectionDivider.isHidden = !showRecent
        }
    }

    /// Omits either number entirely when its account has no unread mail,
    /// rather than always showing both (e.g. "0 · 3") -- saves space and
    /// there's no ambiguity about which account a lone number belongs to
    /// since it keeps that account's color (blue for primary, orange for
    /// secondary).
    private func dualCountTitle(primary: Int, secondary: Int) -> NSAttributedString {
        guard primary > 0 || secondary > 0 else { return NSAttributedString(string: "") }

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let result = NSMutableAttributedString(string: " ")
        if primary > 0 {
            result.append(NSAttributedString(
                string: "\(primary)",
                attributes: [.font: font, .foregroundColor: NSColor.systemBlue]
            ))
        }
        if primary > 0 && secondary > 0 {
            result.append(NSAttributedString(
                string: " · ",
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }
        if secondary > 0 {
            result.append(NSAttributedString(
                string: "\(secondary)",
                attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
            ))
        }
        return result
    }

    /// Clears every badge and unread dot immediately, ahead of the IMAP
    /// round-trip confirming it — the STORE command basically never fails,
    /// so waiting on the server before updating the UI just reads as lag.
    /// The next real refresh will reconcile if something did go wrong.
    func markAllAsReadOptimistically() {
        let cleared = lastAccounts.map { account in
            AccountDisplayState(
                slot: account.slot,
                email: account.email,
                displayName: account.displayName,
                unreadCount: 0,
                recentMessages: account.recentMessages.map { message in
                    MailHeader(
                        uid: message.uid,
                        from: message.from,
                        subject: message.subject,
                        messageID: message.messageID,
                        isUnread: false,
                        isFlagged: message.isFlagged,
                        accountEmail: message.accountEmail
                    )
                }
            )
        }
        update(accounts: cleared)
    }

    private func renderSection(
        header: NSMenuItem,
        items: inout [NSMenuItem],
        messages: [MailHeader],
        headerTitle: String
    ) {
        for item in items {
            menu.removeItem(item)
        }
        items.removeAll()

        header.title = headerTitle
        header.isHidden = messages.isEmpty
        guard !messages.isEmpty else { return }

        // Back to one item per message: the submenu lives directly on the
        // row again, so hovering it reveals the actions to the side
        // (native NSMenuItem/submenu behavior). AppKit doesn't let a
        // submenu-bearing item also fire its own click, so opening the
        // message lives inside the submenu itself (as two explicit
        // choices) rather than as a direct click on the row.
        let insertionIndex = menu.index(of: header) + 1
        for (offset, message) in messages.enumerated() {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.attributedTitle = formattedTitle(for: message)
            item.representedObject = message
            item.submenu = quickActionsSubmenu(for: message)
            menu.insertItem(item, at: insertionIndex + offset)
            items.append(item)
        }
    }

    private func quickActionsSubmenu(for message: MailHeader) -> NSMenu {
        let submenu = NSMenu()

        let openMailAppItem = NSMenuItem(title: "Open in Mail.app", action: #selector(openInMailAppTapped(_:)), keyEquivalent: "")
        openMailAppItem.target = self
        openMailAppItem.representedObject = message
        openMailAppItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        submenu.addItem(openMailAppItem)

        let openGmailItem = NSMenuItem(title: "Open in Gmail", action: #selector(openInGmailTapped(_:)), keyEquivalent: "")
        openGmailItem.target = self
        openGmailItem.representedObject = message
        openGmailItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        submenu.addItem(openGmailItem)

        submenu.addItem(.separator())

        let flagItem = NSMenuItem(
            title: message.isFlagged ? "Remove Flag" : "Flag",
            action: #selector(flagTapped(_:)),
            keyEquivalent: ""
        )
        flagItem.target = self
        flagItem.representedObject = message
        flagItem.image = tintedSymbol("flag.fill", color: .systemOrange)
        submenu.addItem(flagItem)

        let readItem = NSMenuItem(
            title: message.isUnread ? "Mark as Read" : "Mark as Unread",
            action: #selector(markReadTapped(_:)),
            keyEquivalent: ""
        )
        readItem.target = self
        readItem.representedObject = message
        readItem.image = tintedSymbol(message.isUnread ? "envelope.open.fill" : "envelope.fill", color: .systemBlue)
        submenu.addItem(readItem)

        submenu.addItem(.separator())

        let copyCodeItem = NSMenuItem(title: "Copy Code", action: #selector(copyCodeTapped(_:)), keyEquivalent: "")
        copyCodeItem.target = self
        copyCodeItem.representedObject = message
        copyCodeItem.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
        submenu.addItem(copyCodeItem)

        let checkLinksItem = NSMenuItem(title: "Check for Links", action: #selector(checkLinksTapped(_:)), keyEquivalent: "")
        checkLinksItem.target = self
        checkLinksItem.representedObject = message
        checkLinksItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        submenu.addItem(checkLinksItem)

        return submenu
    }

    /// A monochrome SF Symbol tinted a specific color, for menu items where
    /// the color itself carries meaning (orange = flag, matching Mail.app's
    /// own flag color; blue = read/unread, matching its unread dot).
    private func tintedSymbol(_ name: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(config)
    }

    @objc private func flagTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onFlagMessage(message, !message.isFlagged)
    }

    @objc private func markReadTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onMarkReadMessage(message, message.isUnread)
    }

    @objc private func copyCodeTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onCopyCode(message)
    }

    @objc private func checkLinksTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onCheckLinks(message)
    }

    /// Pops up a small standalone menu listing links to choose from, once
    /// they've been fetched asynchronously (the main menu has already
    /// closed by then, so this is a fresh menu rather than a live submenu).
    func showLinkPicker(links: [String]) {
        guard !links.isEmpty else { return }
        let picker = NSMenu()
        for link in links {
            let item = NSMenuItem(title: truncate(link, maxLength: 70), action: #selector(linkPickerItemTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link
            picker.addItem(item)
        }
        picker.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func linkPickerItemTapped(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func formattedTitle(for message: MailHeader) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if message.isUnread {
            result.append(NSAttributedString(string: "● ", attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .black),
                .foregroundColor: NSColor.systemBlue,
                .baselineOffset: 1.5
            ]))
        } else {
            result.append(NSAttributedString(string: "   ", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        }
        result.append(NSAttributedString(
            string: (message.from.isEmpty ? "Unknown sender" : message.from) + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        ))
        result.append(NSAttributedString(
            string: "    " + truncate(message.subject.isEmpty ? "(no subject)" : message.subject, maxLength: 60),
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return result
    }

    private func truncate(_ s: String, maxLength: Int) -> String {
        if s.count <= maxLength { return s }
        return String(s.prefix(maxLength)) + "…"
    }
}
