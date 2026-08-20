import AppKit

/// A borderless NSPanel that can become key -- needed so it receives real
/// scrollWheel/click events like an ordinary window, and so losing key
/// status (a click outside it) can auto-dismiss it, the same way an NSMenu
/// closes when you click away.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The "option 1" swipeable panel: a fully custom floating window used
/// instead of the classic NSMenu dropdown when Settings.useCustomPanel is
/// on. Styled as a best-effort approximation of Apple's translucent
/// "Liquid Glass" look using stable, documented APIs (NSVisualEffectView +
/// rounded corners) -- true Liquid Glass materials from macOS 26 aren't
/// something reproduced here with confidence.
final class CustomPanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let visualEffectView = NSVisualEffectView()
    private let outerStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Checking…")
    private let messagesStack = NSStackView()
    private let pauseButton: NSButton

    private let panelWidth: CGFloat = 340

    private let onCheckNow: () -> Void
    private let onOpenGmail: () -> Void
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
        self.onMarkAllAsRead = onMarkAllAsRead
        self.onTogglePauseNotifications = onTogglePauseNotifications
        self.onFlagMessage = onFlagMessage
        self.onMarkReadMessage = onMarkReadMessage
        self.onCopyCode = onCopyCode
        self.onCheckLinks = onCheckLinks
        self.onPreferences = onPreferences
        self.onQuit = onQuit
        self.pauseButton = NSButton(title: "Pause Notifications (1h)", target: nil, action: nil)

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        buildUI()
    }

    private func buildUI() {
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        panel.contentView = visualEffectView

        outerStack.orientation = .vertical
        outerStack.alignment = .width
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 12),
            outerStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -12),
            outerStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            visualEffectView.widthAnchor.constraint(equalToConstant: panelWidth)
        ])

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        outerStack.addArrangedSubview(padded(statusLabel))

        outerStack.addArrangedSubview(divider())

        messagesStack.orientation = .vertical
        messagesStack.alignment = .width
        messagesStack.spacing = 4
        outerStack.addArrangedSubview(messagesStack)
        messagesStack.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true

        outerStack.addArrangedSubview(divider())

        outerStack.addArrangedSubview(padded(actionRow(title: "Check Now", symbol: "arrow.clockwise", action: #selector(checkNowTapped))))
        outerStack.addArrangedSubview(padded(actionRow(title: "Open Gmail", symbol: "globe", action: #selector(openGmailTapped))))
        pauseButton.removeFromSuperview()
        configureActionButton(pauseButton, title: "Pause Notifications (1h)", symbol: "moon.zzz", action: #selector(pauseTapped))
        outerStack.addArrangedSubview(padded(pauseButton))
        outerStack.addArrangedSubview(padded(actionRow(title: "Mark All as Read", symbol: "envelope.open", action: #selector(markAllTapped))))

        outerStack.addArrangedSubview(divider())

        outerStack.addArrangedSubview(padded(actionRow(title: "Preferences…", symbol: "gearshape", action: #selector(preferencesTapped))))
        outerStack.addArrangedSubview(padded(actionRow(title: "Quit Mercury", symbol: "power", action: #selector(quitTapped))))
    }

    /// NSStackView's .width alignment turned out not to reliably force
    /// arranged subviews to fill a nested stack's width in practice (this
    /// was the root cause of the first real-world test showing half-width,
    /// right-hugged rows) -- every section pins its own width explicitly to
    /// panelWidth instead of trusting alignment alone.
    private func padded(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: panelWidth)
        ])
        return container
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true
        return line
    }

    private func actionRow(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        configureActionButton(button, title: title, symbol: symbol, action: action)
        return button
    }

    private func configureActionButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.font = .systemFont(ofSize: 13)
        button.contentTintColor = .labelColor
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        if let cell = button.cell as? NSButtonCell {
            cell.imageScaling = .scaleProportionallyDown
        }
    }

    @objc private func checkNowTapped() { onCheckNow() }
    @objc private func openGmailTapped() { onOpenGmail() }
    @objc private func markAllTapped() { onMarkAllAsRead() }
    @objc private func preferencesTapped() { onPreferences(); hide() }
    @objc private func quitTapped() { onQuit() }
    @objc private func pauseTapped() { onTogglePauseNotifications() }

    func updatePauseState(isPaused: Bool) {
        pauseButton.title = isPaused ? "Resume Notifications" : "Pause Notifications (1h)"
    }

    func updateConnectionStatus(_ status: String) {
        panel.contentView?.toolTip = status
    }

    /// Rebuilds the message list -- 1 or 2 account sections, each a small
    /// header followed by its swipeable rows, same data StatusBarController
    /// already receives.
    func update(accounts: [AccountDisplayState]) {
        messagesStack.arrangedSubviews.forEach {
            messagesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard !accounts.isEmpty else {
            statusLabel.stringValue = "Not signed in"
            return
        }

        let showRecent = Settings.showRecentMessagesInMenu
        let total = accounts.reduce(0) { $0 + $1.unreadCount }
        statusLabel.stringValue = total > 0 ? "\(total) unread" : "No unread mail"

        guard showRecent else { return }

        for account in accounts where !account.recentMessages.isEmpty {
            if accounts.count > 1 {
                let header = NSTextField(labelWithString: account.displayName)
                header.font = .systemFont(ofSize: 11, weight: .semibold)
                header.textColor = .tertiaryLabelColor
                let paddedHeader = padded(header)
                if let previous = messagesStack.arrangedSubviews.last {
                    messagesStack.setCustomSpacing(12, after: previous)
                }
                messagesStack.addArrangedSubview(paddedHeader)
                // padded() already pins the container to panelWidth, so the
                // header needs no further width constraint of its own.
                messagesStack.setCustomSpacing(4, after: paddedHeader)
            }
            for message in account.recentMessages {
                let row = SwipeableMessageRowView(message: message, attributedText: formattedTitle(for: message))
                row.translatesAutoresizingMaskIntoConstraints = false
                row.heightAnchor.constraint(equalToConstant: 50).isActive = true
                // A plain width constant rather than pinning to
                // messagesStack's anchors: cross-view constraints require a
                // common ancestor, and the row isn't added to the stack
                // until a few lines below -- activating them here threw and
                // aborted the app the moment IMAP delivered its first batch
                // of messages. A constant can't have that failure mode.
                row.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true
                row.onTapOpen = { MessageOpener.open(messageID: message.messageID) }
                row.onAction = { [weak self] action in self?.perform(action, on: message) }
                messagesStack.addArrangedSubview(row)
            }
        }
    }

    private func perform(_ action: SwipeAction, on message: MailHeader) {
        switch action {
        case .none: break
        case .flag: onFlagMessage(message, !message.isFlagged)
        case .markRead: onMarkReadMessage(message, message.isUnread)
        case .copyCode: onCopyCode(message)
        case .checkLinks: onCheckLinks(message)
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
        let subject = message.subject.isEmpty ? "(no subject)" : message.subject
        result.append(NSAttributedString(
            string: "    " + (subject.count > 60 ? String(subject.prefix(60)) + "…" : subject),
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return result
    }

    /// Toggles the panel open/closed, positioned just under the given
    /// status-bar button -- mirrors how NSMenu anchors itself to the status
    /// item automatically, which a plain NSPanel doesn't do for free.
    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    private func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        outerStack.layoutSubtreeIfNeeded()
        let height = outerStack.fittingSize.height + 24
        let buttonFrame = buttonWindow.frame
        let origin = NSPoint(x: buttonFrame.minX - (panelWidth - buttonFrame.width) / 2, y: buttonFrame.minY - height - 4)
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: panelWidth, height: height), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
