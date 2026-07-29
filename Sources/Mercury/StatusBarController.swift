import AppKit

struct AccountDisplayState {
    let slot: AccountSlot
    let email: String
    let unreadCount: Int
    let recentMessages: [MailHeader]
}

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLabelItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let recentHeaderItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
    private let recentHeaderItem2 = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var recentItems: [NSMenuItem] = []
    private var recentItems2: [NSMenuItem] = []
    private var lastAccounts: [AccountDisplayState] = []

    private let onCheckNow: () -> Void
    private let onOpenGmail: () -> Void
    private let onOpenMessage: (MailHeader) -> Void
    private let onTestNotification: () -> Void
    private let onMarkAllAsRead: () -> Void
    private let onPreferences: () -> Void
    private let onQuit: () -> Void

    init(onCheckNow: @escaping () -> Void,
         onOpenGmail: @escaping () -> Void,
         onOpenMessage: @escaping (MailHeader) -> Void,
         onTestNotification: @escaping () -> Void,
         onMarkAllAsRead: @escaping () -> Void,
         onPreferences: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onCheckNow = onCheckNow
        self.onOpenGmail = onOpenGmail
        self.onOpenMessage = onOpenMessage
        self.onTestNotification = onTestNotification
        self.onMarkAllAsRead = onMarkAllAsRead
        self.onPreferences = onPreferences
        self.onQuit = onQuit

        statusItem.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Mail")
        statusItem.button?.imagePosition = .imageLeft

        statusLabelItem.isEnabled = false
        recentHeaderItem.isEnabled = false
        recentHeaderItem.isHidden = true
        recentHeaderItem2.isEnabled = false
        recentHeaderItem2.isHidden = true

        menu.addItem(statusLabelItem)
        menu.addItem(.separator())
        menu.addItem(recentHeaderItem)
        // Section-1 recent-message items get inserted here dynamically, right after recentHeaderItem.
        menu.addItem(recentHeaderItem2)
        // Section-2 (second account) recent-message items get inserted here, right after recentHeaderItem2.
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Check Now", action: #selector(checkNowTapped)))
        menu.addItem(makeItem(title: "Open Gmail", action: #selector(openGmailTapped)))
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
    @objc private func preferencesTapped() { onPreferences() }
    @objc private func quitTapped() { onQuit() }

    @objc private func recentItemTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onOpenMessage(message)
    }

    func updateConnectionStatus(_ status: String) {
        statusItem.button?.toolTip = status
    }

    /// Pops the menu open as if the status item had been clicked — used by
    /// the global keyboard shortcut. Arrow-key navigation once it's open is
    /// native NSMenu behavior, no extra code needed.
    func showMenu() {
        NSLog("Mercury: global shortcut fired, opening menu")
        statusItem.button?.performClick(nil)
    }

    /// Renders 1 or 2 configured accounts. With 1 account this looks exactly
    /// like before (plain envelope icon + numeric badge, single "Recent"
    /// section). With 2, it switches to the dual-badge icon and labels each
    /// "Recent" section with its account's address so it's clear which
    /// inbox each message belongs to.
    func update(accounts: [AccountDisplayState]) {
        lastAccounts = accounts

        guard !accounts.isEmpty else {
            statusItem.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Mail")
            statusItem.button?.title = ""
            statusLabelItem.title = "Not signed in"
            renderSection(header: recentHeaderItem, items: &recentItems, messages: [], headerTitle: "Recent")
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: [], headerTitle: "")
            return
        }

        if accounts.count == 1 {
            let account = accounts[0]
            statusItem.button?.image = NSImage(
                systemSymbolName: account.unreadCount > 0 ? "envelope.fill" : "envelope",
                accessibilityDescription: "Mail"
            )
            statusItem.button?.title = account.unreadCount > 0 ? " \(account.unreadCount)" : ""
            statusLabelItem.title = account.unreadCount > 0 ? "\(account.unreadCount) unread" : "No unread mail"

            renderSection(header: recentHeaderItem, items: &recentItems, messages: account.recentMessages, headerTitle: "Recent")
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: [], headerTitle: "")
        } else {
            let primary = accounts.first { $0.slot == .primary } ?? accounts[0]
            let secondary = accounts.first { $0.slot == .secondary } ?? accounts[1]

            statusItem.button?.image = MenuBarIconRenderer.dualAccountIcon(
                primaryUnread: primary.unreadCount,
                secondaryUnread: secondary.unreadCount
            )
            statusItem.button?.title = ""
            let total = primary.unreadCount + secondary.unreadCount
            statusLabelItem.title = total > 0 ? "\(total) unread total" : "No unread mail"

            renderSection(header: recentHeaderItem, items: &recentItems, messages: primary.recentMessages, headerTitle: primary.email)
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: secondary.recentMessages, headerTitle: secondary.email)
        }
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
                unreadCount: 0,
                recentMessages: account.recentMessages.map { message in
                    MailHeader(
                        from: message.from,
                        subject: message.subject,
                        messageID: message.messageID,
                        isUnread: false,
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

        let insertionIndex = menu.index(of: header) + 1
        for (offset, message) in messages.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(recentItemTapped(_:)), keyEquivalent: "")
            item.target = self
            item.attributedTitle = formattedTitle(for: message)
            item.representedObject = message
            menu.insertItem(item, at: insertionIndex + offset)
            items.append(item)
        }
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
