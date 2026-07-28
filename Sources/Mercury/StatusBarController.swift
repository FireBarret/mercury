import AppKit

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLabelItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let recentHeaderItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
    private var recentItems: [NSMenuItem] = []

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

        menu.addItem(statusLabelItem)
        menu.addItem(.separator())
        menu.addItem(recentHeaderItem)
        // Recent-message items get inserted here dynamically, right after recentHeaderItem.
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

    func updateUnreadCount(_ count: Int) {
        statusItem.button?.image = NSImage(
            systemSymbolName: count > 0 ? "envelope.fill" : "envelope",
            accessibilityDescription: "Mail"
        )
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusLabelItem.title = count > 0 ? "\(count) unread" : "No unread mail"
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

    func updateRecentMessages(_ messages: [MailHeader]) {
        for item in recentItems {
            menu.removeItem(item)
        }
        recentItems.removeAll()

        recentHeaderItem.isHidden = messages.isEmpty
        guard !messages.isEmpty else { return }

        let insertionIndex = menu.index(of: recentHeaderItem) + 1
        for (offset, message) in messages.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(recentItemTapped(_:)), keyEquivalent: "")
            item.target = self
            item.attributedTitle = formattedTitle(for: message)
            item.representedObject = message
            menu.insertItem(item, at: insertionIndex + offset)
            recentItems.append(item)
        }
    }

    private func formattedTitle(for message: MailHeader) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: message.isUnread ? "🔵 " : "    "
        )
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
