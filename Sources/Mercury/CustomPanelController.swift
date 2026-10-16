import AppKit

/// A borderless NSPanel that can become key -- needed so it receives real
/// scrollWheel/click events like an ordinary window, and so losing key
/// status (a click outside it) can auto-dismiss it, the same way an NSMenu
/// closes when you click away.
private final class FloatingPanel: NSPanel {
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Mercury has no main menu, so Cmd+, / Cmd+Q never reach a menu item
    /// here -- handle them directly while the panel is key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case ",": onPreferences?(); return true
            case "q": onQuit?(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Holds the panel's content. Accepts the first click so the click that
/// activates the panel isn't swallowed.
private final class PanelContentView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless NSButton that highlights as the cursor passes over it.
/// Plain borderless buttons give no hover feedback at all, which made the
/// panel's footer feel inert compared with a real NSMenu.
private final class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyHoverAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyHoverAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = isHovered
            ? NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyHoverAppearance()
        }
    }
}

/// The "option 1" swipeable panel: a fully custom floating window used
/// instead of the classic NSMenu dropdown when Settings.useCustomPanel is
/// on. Styled as a best-effort approximation of Apple's translucent
/// "Liquid Glass" look using stable, documented APIs (NSVisualEffectView +
/// rounded corners) -- true Liquid Glass materials from macOS 26 aren't
/// something reproduced here with confidence.
final class CustomPanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let contentHolder = PanelContentView()
    private var backgroundView: NSView?
    private let outerStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Checking…")
    private let messagesStack = NSStackView()
    private let pauseButton: NSButton

    private let panelWidth: CGFloat = 340
    private var clickAwayMonitor: Any?

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
        self.pauseButton = HoverButton(title: "Pause Notifications (1h)", target: nil, action: nil)

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
        panel.onPreferences = { [weak self] in self?.onPreferences(); self?.hide() }
        panel.onQuit = { [weak self] in self?.onQuit() }
        panel.onCancel = { [weak self] in self?.hide() }

        buildUI()
    }

    private func buildUI() {
        contentHolder.translatesAutoresizingMaskIntoConstraints = false
        outerStack.orientation = .vertical
        outerStack.alignment = .width
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        contentHolder.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: contentHolder.topAnchor, constant: 12),
            outerStack.bottomAnchor.constraint(equalTo: contentHolder.bottomAnchor, constant: -12),
            outerStack.leadingAnchor.constraint(equalTo: contentHolder.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentHolder.trailingAnchor),
            contentHolder.widthAnchor.constraint(equalToConstant: panelWidth)
        ])
        refreshBackground()

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
    /// (Re)builds the panel background: Liquid Glass when enabled and
    /// available (content goes inside its contentView, the only part Apple
    /// guarantees sits within the glass), otherwise the standard blur.
    func refreshBackground() {
        contentHolder.removeFromSuperview()
        let background: NSView
        if let glass = makeGlassBackground() {
            background = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 18
            blur.layer?.masksToBounds = true
            blur.layer?.borderWidth = 0.5
            blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
            blur.addSubview(contentHolder)
            NSLayoutConstraint.activate([
                contentHolder.topAnchor.constraint(equalTo: blur.topAnchor),
                contentHolder.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                contentHolder.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                contentHolder.trailingAnchor.constraint(equalTo: blur.trailingAnchor)
            ])
            background = blur
        }
        background.toolTip = backgroundView?.toolTip
        backgroundView = background
        panel.contentView = background
    }

    /// NSGlassEffectView only exists in the macOS 26 SDK; the compile-time
    /// guard keeps the project building on older toolchains (e.g. CI).
    private func makeGlassBackground() -> NSView? {
        #if compiler(>=6.2)
        if Settings.useGlassEffect, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 22
            glass.contentView = contentHolder
            return glass
        }
        #endif
        return nil
    }

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
        let button = HoverButton(title: title, target: self, action: action)
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
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
        backgroundView?.toolTip = status
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

    /// Toggles the panel open/closed under the status item. `anchorFrame`
    /// is the status button's screen frame, or nil when the item isn't
    /// visibly on screen (hidden by a menu-bar manager, behind the notch),
    /// in which case the panel anchors to the top-right of the screen the
    /// mouse is on instead.
    func toggle(anchorFrame: NSRect?) {
        if panel.isVisible {
            hide()
        } else {
            show(anchorFrame: anchorFrame)
        }
    }

    private func show(anchorFrame: NSRect?) {
        outerStack.layoutSubtreeIfNeeded()
        let screen = anchorFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
        } ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let height = min(outerStack.fittingSize.height + 24, area.height - 16)
        let desiredX = anchorFrame.map { $0.midX - panelWidth / 2 } ?? (area.maxX - panelWidth - 8)
        let topY = anchorFrame.map { $0.minY - 4 } ?? area.maxY - 4
        let x = max(area.minX + 8, min(desiredX, area.maxX - panelWidth - 8))
        let y = max(area.minY + 8, topY - height)
        NSLog("Mercury: showing panel at (%.0f, %.0f) anchor=%@", x, y, anchorFrame.map { NSStringFromRect($0) } ?? "fallback")

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        installClickAwayMonitor()
    }

    func hide() {
        removeClickAwayMonitor()
        panel.orderOut(nil)
    }

    /// Dismissal can't rely on resigning key alone: with cooperative
    /// activation (macOS 14+) the panel isn't guaranteed to ever become
    /// key, so clicks elsewhere would leave it stuck open.
    private func installClickAwayMonitor() {
        removeClickAwayMonitor()
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeClickAwayMonitor() {
        if let monitor = clickAwayMonitor {
            NSEvent.removeMonitor(monitor)
            clickAwayMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
