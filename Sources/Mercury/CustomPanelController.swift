import AppKit

/// A borderless NSPanel that can become key -- needed so it receives real
/// scrollWheel/click events like an ordinary window, and so losing key
/// status (a click outside it) can auto-dismiss it, the same way an NSMenu
/// closes when you click away.
private final class FloatingPanel: NSPanel {
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

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

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
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
/// Top-left-origin container so the message list pins to the top of its scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var onHover: (() -> Void)?
    var onHoverEnd: (() -> Void)?
    /// Shared hover/keyboard selection, driven by the panel.
    var isKeySelected = false { didSet { applyHoverAppearance() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onHoverEnd?() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyHoverAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = isKeySelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyHoverAppearance()
        }
    }
}

/// The swipeable panel: a floating window used instead of the classic NSMenu
/// dropdown when Settings.useCustomPanel is on. Real trackpad swipes on
/// message rows, full keyboard navigation, standard blur background.
final class CustomPanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let contentHolder = PanelContentView()
    private var backgroundView: NSView?
    private let outerStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Checking…")
    private let messagesStack = NSStackView()
    private let messagesScroll = NSScrollView()
    private var messagesHeight: NSLayoutConstraint?
    private let maxMessagesHeight: CGFloat = 440
    private let pauseButton: NSButton
    private var checkNowButton: NSButton?
    private var feedbackGeneration = 0
    private var markAllButton: NSButton?
    private var messageRows: [(row: SwipeableMessageRowView, message: MailHeader)] = []
    /// Unified keyboard selection: message rows first, then the footer buttons.
    private var selectedIndex: Int?
    private var footerButtons: [HoverButton] = []
    private var selectionFromMouse = false
    private var lastMousePoint = NSPoint.zero
    private var keyHints: [(label: NSTextField, key: QuickKey)] = []

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
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }

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
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(messagesStack)
        NSLayoutConstraint.activate([
            messagesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            messagesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            messagesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            messagesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            messagesStack.widthAnchor.constraint(equalToConstant: panelWidth)
        ])
        messagesScroll.drawsBackground = false
        messagesScroll.hasVerticalScroller = false
        messagesScroll.hasHorizontalScroller = false
        messagesScroll.autohidesScrollers = true
        messagesScroll.scrollerStyle = .overlay
        messagesScroll.documentView = documentView
        messagesScroll.translatesAutoresizingMaskIntoConstraints = false
        messagesScroll.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true
        messagesHeight = messagesScroll.heightAnchor.constraint(equalToConstant: 0)
        messagesHeight?.isActive = true
        outerStack.addArrangedSubview(messagesScroll)

        outerStack.addArrangedSubview(divider())

        let checkNow = actionRow(title: "Check Now", symbol: "arrow.clockwise", action: #selector(checkNowTapped))
        checkNowButton = checkNow
        addKeyHint(to: checkNow, key: .checkNow)
        outerStack.addArrangedSubview(padded(checkNow))
        let openGmailButton = actionRow(title: "Open Gmail", symbol: "globe", action: #selector(openGmailTapped))
        addKeyHint(to: openGmailButton, key: .openInbox)
        outerStack.addArrangedSubview(padded(openGmailButton))
        pauseButton.removeFromSuperview()
        configureActionButton(pauseButton, title: "Pause Notifications (1h)", symbol: "moon.zzz", action: #selector(pauseTapped))
        outerStack.addArrangedSubview(padded(pauseButton))
        let markAll = actionRow(title: "Mark All as Read", symbol: "envelope.open", action: #selector(markAllTapped))
        markAllButton = markAll
        addKeyHint(to: markAll, key: .markAllRead)
        outerStack.addArrangedSubview(padded(markAll))

        outerStack.addArrangedSubview(divider())

        let preferencesButton = actionRow(title: "Preferences…", symbol: "gearshape", action: #selector(preferencesTapped))
        let quitButton = actionRow(title: "Quit Mercury", symbol: "power", action: #selector(quitTapped))
        outerStack.addArrangedSubview(padded(preferencesButton))
        outerStack.addArrangedSubview(padded(quitButton))
        footerButtons = [checkNow, openGmailButton, pauseButton, markAll, preferencesButton, quitButton].compactMap { $0 as? HoverButton }
        for button in footerButtons {
            button.onHover = { [weak self, weak button] in
                guard let self = self, let button = button, let i = self.footerButtons.firstIndex(where: { $0 === button }) else { return }
                self.mouseSelect(self.messageRows.count + i)
            }
            button.onHoverEnd = { [weak self, weak button] in
                guard let self = self, let button = button, let i = self.footerButtons.firstIndex(where: { $0 === button }) else { return }
                self.mouseDeselect(self.messageRows.count + i)
            }
        }
    }

    /// NSStackView's .width alignment turned out not to reliably force
    /// arranged subviews to fill a nested stack's width in practice (this
    /// was the root cause of the first real-world test showing half-width,
    /// right-hugged rows) -- every section pins its own width explicitly to
    /// panelWidth instead of trusting alignment alone.
    /// (Re)builds the panel background: a blurred, rounded popover surface.
    func refreshBackground() {
        contentHolder.removeFromSuperview()
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        // A mask image (not a layer corner radius) so the window shadow
        // follows the rounded shape instead of being cut at the corners.
        let radius: CGFloat = 18
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        blur.maskImage = mask
        blur.addSubview(contentHolder)
        NSLayoutConstraint.activate([
            contentHolder.topAnchor.constraint(equalTo: blur.topAnchor),
            contentHolder.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            contentHolder.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            contentHolder.trailingAnchor.constraint(equalTo: blur.trailingAnchor)
        ])
        blur.toolTip = backgroundView?.toolTip
        backgroundView = blur
        panel.contentView = blur
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
        button.focusRingType = .none
        button.refusesFirstResponder = true
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

    /// Swaps a button's title and icon for a confirmation that stays until
    /// the panel is next shown.
    private func flash(_ button: NSButton?, title: String, symbol: String) {
        guard let button = button else { return }
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func resetFeedback() {
        feedbackGeneration += 1
        checkNowButton?.title = "Check Now"
        checkNowButton?.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        markAllButton?.title = "Mark All as Read"
        markAllButton?.image = NSImage(systemSymbolName: "envelope.open", accessibilityDescription: nil)
    }

    @objc private func checkNowTapped() {
        onCheckNow()
        flash(checkNowButton, title: "Checking…", symbol: "arrow.triangle.2.circlepath")
        feedbackGeneration += 1
        let generation = feedbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.feedbackGeneration == generation else { return }
            self.flash(self.checkNowButton, title: "Check completed", symbol: "checkmark.circle.fill")
        }
    }
    @objc private func openGmailTapped() { onOpenGmail() }
    @objc private func markAllTapped() {
        onMarkAllAsRead()
        flash(markAllButton, title: "Marked all as read", symbol: "checkmark.circle.fill")
    }
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
        let oldCount = messageRows.count
        let previousSelection = selectedIndex.flatMap { $0 < oldCount ? messageRows[$0].message : nil }
        let previousFooter = selectedIndex.flatMap { $0 >= oldCount ? $0 - oldCount : nil }
        messageRows = []
        defer {
            if messageRows.isEmpty, !accounts.isEmpty, Settings.showRecentMessagesInMenu {
                let empty = NSTextField(labelWithString: "No recent messages")
                empty.font = .systemFont(ofSize: 12)
                empty.textColor = .tertiaryLabelColor
                messagesStack.addArrangedSubview(padded(empty))
            }
            messagesStack.layoutSubtreeIfNeeded()
            messagesHeight?.constant = min(messagesStack.fittingSize.height, maxMessagesHeight)
            if panel.isVisible { resizeToFit() }
            // Keep the same row selected across refreshes.
            if let previous = previousSelection {
                let match = messageRows.firstIndex { $0.message.uid == previous.uid && $0.message.accountEmail == previous.accountEmail }
                selectIndex(match ?? min(selectedIndex ?? 0, max(0, messageRows.count - 1)))
            } else if let footer = previousFooter {
                selectIndex(messageRows.count + footer)
            } else {
                selectIndex(nil)
            }
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
                row.onTapOpen = { [weak self] in self?.perform(Settings.clickAction, on: message) }
                row.onAction = { [weak self] action in self?.perform(action, on: message) }
                row.onHover = { [weak self, weak row] in
                    guard let self = self, let row = row, let i = self.messageRows.firstIndex(where: { $0.row === row }) else { return }
                    self.mouseSelect(i)
                }
                row.onHoverEnd = { [weak self, weak row] in
                    guard let self = self, let row = row, let i = self.messageRows.firstIndex(where: { $0.row === row }) else { return }
                    self.mouseDeselect(i)
                }
                messagesStack.addArrangedSubview(row)
                messageRows.append((row, message))
            }
        }
    }

    // MARK: - Keyboard

    private var selectableCount: Int { messageRows.count + footerButtons.count }

    private func selectIndex(_ index: Int?) {
        let valid = index.flatMap { (0..<selectableCount).contains($0) ? $0 : nil }
        selectedIndex = valid
        for (i, entry) in messageRows.enumerated() { entry.row.isSelected = (i == valid) }
        if let valid = valid, valid < messageRows.count {
            let row = messageRows[valid].row
            row.scrollToVisible(row.bounds)
        }
        for (i, button) in footerButtons.enumerated() { button.isKeySelected = (messageRows.count + i == valid) }
    }

    /// The pointer moved onto a row/button: it takes over the highlight. Only
    /// real movement counts, so a stationary pointer never overrides the keys.
    private func mouseSelect(_ index: Int) {
        let point = NSEvent.mouseLocation
        guard point != lastMousePoint else { return }
        lastMousePoint = point
        selectionFromMouse = true
        if selectedIndex != index { selectIndex(index) }
    }

    private func mouseDeselect(_ index: Int) {
        guard selectionFromMouse, selectedIndex == index else { return }
        selectIndex(nil)
    }

    private func moveSelection(by delta: Int) {
        selectionFromMouse = false
        guard selectableCount > 0 else { return }
        let current = selectedIndex ?? (delta > 0 ? -1 : selectableCount)
        selectIndex(max(0, min(selectableCount - 1, current + delta)))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 125: moveSelection(by: 1); return true
        case 126: moveSelection(by: -1); return true
        case 36, 76:
            guard let i = selectedIndex else { return true }
            if i < messageRows.count {
                MessageOpener.open(messageID: messageRows[i].message.messageID)
                hide()
            } else {
                footerButtons[i - messageRows.count].performClick(nil)
            }
            return true
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1,
              let key = Settings.quickKey(matching: chars) else { return false }
        switch key {
        case .markAllRead: markAllTapped(); return true
        case .checkNow: checkNowTapped(); return true
        case .openInbox: onOpenGmail(); hide(); return true
        default: break
        }
        guard let index = selectedIndex, messageRows.indices.contains(index) else {
            NSSound.beep()
            return true
        }
        let message = messageRows[index].message
        switch key {
        case .markRead:
            // Toggle read/unread, then jump to the next unread message below
            // (stay put if there is none).
            let next = messageRows.indices.dropFirst(index + 1).first { messageRows[$0].message.isUnread } ?? index
            onMarkReadMessage(message, message.isUnread)
            selectionFromMouse = false
            selectIndex(next)
        case .flag: onFlagMessage(message, !message.isFlagged)
        case .reply: MessageOpener.replyInGmail(to: message); hide()
        case .openMailApp: MessageOpener.openInMailApp(messageID: message.messageID); hide()
        case .openGmail: MessageOpener.openInGmailBrowser(messageID: message.messageID); hide()
        default: break
        }
        return true
    }

    /// A small greyed key hint at the right edge of an action button.
    private func addKeyHint(to button: NSButton, key: QuickKey) {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        keyHints.append((label, key))
    }

    private func refreshKeyHints() {
        for hint in keyHints { hint.label.stringValue = Settings.key(for: hint.key).uppercased() }
    }

    private func perform(_ action: SwipeAction, on message: MailHeader) {
        switch action {
        case .none: break
        case .flag: onFlagMessage(message, !message.isFlagged)
        case .markRead: onMarkReadMessage(message, message.isUnread)
        case .copyCode: onCopyCode(message)
        case .checkLinks: onCheckLinks(message)
        case .reply: MessageOpener.replyInGmail(to: message)
        case .open:
            MessageOpener.open(messageID: message.messageID)
            hide()
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
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: message.isUnread ? .semibold : .regular),
                .foregroundColor: message.isUnread ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        ))
        let subject = message.subject.isEmpty ? "(no subject)" : message.subject
        result.append(NSAttributedString(
            string: "    " + subject,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        // Each paragraph (sender, subject) stays on one line and truncates
        // with "…" instead of wrapping out of the row (wide Japanese text).
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Toggles the panel open/closed under the status item. `anchorFrame`
    /// is the status button's screen frame, or nil when the item isn't
    /// visibly on screen (hidden by a menu-bar manager, behind the notch),
    /// in which case the panel anchors to the top-right of the screen the
    /// mouse is on instead.
    func toggle(anchorFrame: NSRect?, selectNewest: Bool = false) {
        if panel.isVisible {
            hide()
        } else {
            show(anchorFrame: anchorFrame, selectNewest: selectNewest)
        }
    }

    private func show(anchorFrame: NSRect?, selectNewest: Bool) {
        resetFeedback()
        refreshKeyHints()
        selectionFromMouse = false
        lastMousePoint = NSEvent.mouseLocation
        selectIndex(selectNewest && !messageRows.isEmpty ? 0 : nil)
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
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        installClickAwayMonitor()
        // The shadow is computed from the window's shape; refresh it once the
        // content is laid out.
        panel.invalidateShadow()
        DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
    }

    /// Re-fits the open panel to its content, keeping the top edge in place.
    private func resizeToFit() {
        outerStack.layoutSubtreeIfNeeded()
        let screen = panel.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 900) - 16
        let height = min(outerStack.fittingSize.height + 24, maxHeight)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
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
