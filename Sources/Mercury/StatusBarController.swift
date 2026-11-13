import AppKit

struct AccountDisplayState {
    let slot: AccountSlot
    let email: String
    let displayName: String
    let unreadCount: Int
    let recentMessages: [MailHeader]
}

/// Tracks whether the classic dropdown is open. While it is, the global
/// shortcut's Carbon event is held back by menu tracking until the menu
/// closes -- so pressing the shortcut again would otherwise just queue a
/// reopen. A local key monitor catches the press during tracking and closes
/// the menu, and presses delivered right after a close are dropped.
private final class MenuOpenTracker: NSObject, NSMenuDelegate {
    private(set) var isOpen = false
    private(set) var lastCloseDate = Date.distantPast
    private var monitor: Any?
    var onOpenChanged: ((Bool) -> Void)?
    var onWillOpen: (() -> Void)?
    var onDidClose: (() -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        onWillOpen?()
        isOpen = true
        onOpenChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak menu] event in
            guard let self = self, let menu = menu, self.matchesShortcut(event) else { return event }
            NSLog("Mercury: shortcut pressed while menu open, closing it")
            menu.cancelTracking()
            return nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        lastCloseDate = Date()
        onOpenChanged?(false)
        onDidClose?()
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func downArrowEvent() -> NSEvent? {
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                                characters: down, charactersIgnoringModifiers: down, isARepeat: false, keyCode: 125)
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        guard let keyCode = Settings.shortcutKeyCode, let modifiers = Settings.shortcutModifiers else { return false }
        let wanted = ShortcutRecorderView.modifierFlags(fromCarbon: modifiers)
        let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return UInt32(event.keyCode) == keyCode && pressed == wanted
    }
}

/// A menu row that runs its action without dismissing the menu. NSMenu
/// closes on any normal item click, but a custom-view item receives the
/// mouse itself, so the menu stays open. Highlighting follows the menu's own
/// state (`enclosingMenuItem.isHighlighted`) so it never gets stuck.
private final class StayOpenMenuRow: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var baseTitle: String
    private let followUp: String?
    private var followUpTimer: Timer?
    private var feedbackShown = false
    private let hintLabel = NSTextField(labelWithString: "")
    private let feedback: (StayOpenMenuRow) -> String
    private let action: (StayOpenMenuRow) -> Void
    /// The message a per-message row acts on.
    var message: MailHeader?

    init(title: String, icon: NSImage? = nil, followUp: String? = nil,
         feedback: @escaping (StayOpenMenuRow) -> String, action: @escaping (StayOpenMenuRow) -> Void) {
        self.baseTitle = title
        self.followUp = followUp
        self.feedback = feedback
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        autoresizingMask = [.width]
        label.stringValue = title
        label.font = NSFont.menuFont(ofSize: 0)
        label.autoresizingMask = [.width]
        iconView.frame = NSRect(x: 12, y: 3, width: 16, height: 16)
        addSubview(iconView)
        addSubview(label)
        hintLabel.font = NSFont.menuFont(ofSize: 0)
        hintLabel.alignment = .right
        hintLabel.autoresizingMask = [.minXMargin]
        hintLabel.frame = NSRect(x: 150, y: 2, width: 36, height: 18)
        addSubview(hintLabel)
        update(title: title, icon: icon)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, icon: NSImage?) {
        baseTitle = title
        iconView.image = icon
        iconView.isHidden = icon == nil
        label.frame = NSRect(x: icon == nil ? 14 : 34, y: 2, width: 160, height: 18)
        if !feedbackShown { label.stringValue = title }
    }

    // The menu doesn't redraw custom views on highlight changes, and mouse
    // enter/exit events get lost while submenus open. So hover is derived
    // from the live pointer position and polled while the row is on screen.
    /// The key shown greyed on the right ("" hides it).
    func setHint(_ key: String) {
        hintLabel.stringValue = key.uppercased()
    }

    override func layout() {
        super.layout()
        hintLabel.frame = NSRect(x: bounds.width - 14 - 36, y: 2, width: 36, height: 18)
        label.frame.size.width = max(60, bounds.width - label.frame.minX - 50)
    }

    private var isHighlighted = false
    private var hoverTimer: Timer?

    private func pointerIsInside() -> Bool {
        guard let window = window else { return false }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return bounds.contains(local)
    }

    private func refreshHover() {
        let inside = pointerIsInside() || (enclosingMenuItem?.isHighlighted ?? false)
        if inside != isHighlighted {
            isHighlighted = inside
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverTimer?.invalidate()
        hoverTimer = nil
        isHighlighted = false
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.refreshHover() }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        refreshHover()
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isHighlighted
        label.textColor = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        hintLabel.textColor = highlighted ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.8) : NSColor.tertiaryLabelColor
        guard highlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }

    /// Runs the action and shows its feedback (click or quick key).
    func activate() {
        action(self)
        showFeedback()
    }

    /// Swaps the label for a confirmation that stays until `reset()` (the
    /// next time the menu opens). A common-modes Timer is needed for the
    /// follow-up because GCD timers don't fire while a menu is tracked.
    private func showFeedback() {
        feedbackShown = true
        label.stringValue = feedback(self)
        followUpTimer?.invalidate()
        guard let followUp = followUp else { return }
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.label.stringValue = followUp
        }
        RunLoop.main.add(timer, forMode: .common)
        followUpTimer = timer
    }

    func reset() {
        followUpTimer?.invalidate()
        feedbackShown = false
        label.stringValue = baseTitle
    }
}

final class StatusBarController {
    private let menuTracker = MenuOpenTracker()
    private var stayOpenRows: [StayOpenMenuRow] = []
    private var needsRerender = false
    /// Number of Down-arrow presses to send right after the menu opens, to
    /// land the highlight on a message (1 = the newest).
    private var downPressesOnOpen = 0
    private var checkNowItem: NSMenuItem?
    private var markAllItem: NSMenuItem?
    private var checkNowRow: StayOpenMenuRow?
    private var markAllRow: StayOpenMenuRow?
    private let openInboxItem = NSMenuItem()

    /// Called with true when the dropdown opens and false when it closes.
    /// The owner unregisters the global hotkey while it's open: Carbon holds
    /// hotkey presses until menu tracking ends, whereas unregistered, the
    /// press arrives as an ordinary key event that closes the menu.
    var onMenuOpenChanged: ((Bool) -> Void)? {
        get { menuTracker.onOpenChanged }
        set { menuTracker.onOpenChanged = newValue }
    }
    // .variableLength lets the button's width track its actual content
    // (image + title) automatically -- important now that the dual-account
    // count is real title text of varying width, not a fixed-size bitmap.
    private let statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Stable identity: without a name the system assigns "Item-N" by
        // creation order, which menu-bar managers (Ice, Thaw, Bartender)
        // and macOS itself can't reliably track across launches, so the
        // item's position/hidden state gets lost or duplicated.
        item.autosaveName = "MercuryStatusItem"
        return item
    }()
    private let menu = NSMenu()
    private let statusLabelItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let recentHeaderItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
    private let recentHeaderItem2 = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let interSectionDivider = NSMenuItem.separator()
    private var recentItems: [NSMenuItem] = []
    private var recentItems2: [NSMenuItem] = []
    private var lastAccounts: [AccountDisplayState] = []

    private let pauseNotificationsItem = NSMenuItem(title: "Pause Notifications (1h)", action: nil, keyEquivalent: "")
    private var customPanelController: CustomPanelController?

    private let onCheckNow: () -> Void
    private let onOpenGmail: () -> Void
    private let onOpenMessageInGmail: (MailHeader) -> Void
    private let onOpenMessageInMailApp: (MailHeader) -> Void
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

        menu.delegate = menuTracker
        menuTracker.onWillOpen = { [weak self] in self?.menuWillOpen() }
        menuTracker.onDidClose = { [weak self] in
            guard let self = self, self.needsRerender else { return }
            self.needsRerender = false
            self.update(accounts: self.lastAccounts)
        }
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
        let checkNowItem = makeStayOpenItem(title: "Check Now", feedback: "Checking…", followUp: "Check completed ✓") { [weak self] in self?.onCheckNow() }
        checkNowRow = checkNowItem.view as? StayOpenMenuRow
        // An action makes the row reachable with the arrow keys (Return or
        // its key then runs it; a mouse click is handled by the row itself).
        checkNowItem.target = self
        checkNowItem.action = #selector(checkNowItemFired)
        self.checkNowItem = checkNowItem
        menu.addItem(checkNowItem)
        openInboxItem.title = "Open Gmail"
        openInboxItem.target = self
        openInboxItem.action = #selector(openGmailTapped)
        menu.addItem(openInboxItem)
        pauseNotificationsItem.target = self
        pauseNotificationsItem.action = #selector(togglePauseNotificationsTapped)
        menu.addItem(pauseNotificationsItem)
        let markAllItem = makeStayOpenItem(title: "Mark All as Read", feedback: "Marked all as read ✓") { [weak self] in self?.onMarkAllAsRead() }
        markAllRow = markAllItem.view as? StayOpenMenuRow
        markAllItem.target = self
        markAllItem.action = #selector(markAllItemFired)
        self.markAllItem = markAllItem
        menu.addItem(markAllItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Preferences…", action: #selector(preferencesTapped), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q"))

        customPanelController = CustomPanelController(
            onCheckNow: onCheckNow,
            onOpenGmail: onOpenGmail,
            onMarkAllAsRead: onMarkAllAsRead,
            onTogglePauseNotifications: onTogglePauseNotifications,
            onFlagMessage: onFlagMessage,
            onMarkReadMessage: onMarkReadMessage,
            onCopyCode: onCopyCode,
            onCheckLinks: onCheckLinks,
            onPreferences: onPreferences,
            onQuit: onQuit
        )

        applyInterfaceMode()
    }

    /// Switches the status item between the classic NSMenu dropdown and the
    /// custom swipeable panel, based on Settings.useCustomPanel. Safe to
    /// call again any time the setting changes at runtime (Preferences
    /// already re-invokes this via onDisplaySettingsChanged), since AppKit
    /// doesn't allow both a menu and a custom click action on one status
    /// item at once.
    func applyInterfaceMode() {
        customPanelController?.refreshBackground()
        if Settings.useCustomPanel {
            statusItem.menu = nil
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusItemClicked)
        } else {
            customPanelController?.hide()
            statusItem.button?.target = nil
            statusItem.button?.action = nil
            statusItem.menu = menu
        }
    }

    @objc private func statusItemClicked() {
        customPanelController?.toggle(anchorFrame: visibleButtonFrame())
    }

    /// The status button's screen frame, or nil when it isn't actually
    /// visible -- menu-bar managers hide items by pushing them off-screen
    /// (or into a collapsed section), where anchoring to the frame would
    /// put the panel/menu somewhere unreachable.
    private func visibleButtonFrame() -> NSRect? {
        guard let window = statusItem.button?.window else { return nil }
        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(center) }
        let visible = window.occlusionState.contains(.visible)
        guard onScreen, visible else {
            NSLog("Mercury: status item not visible (frame=%@, onScreen=%d, visible=%d); using fallback anchor",
                  NSStringFromRect(frame), onScreen ? 1 : 0, visible ? 1 : 0)
            return nil
        }
        return frame
    }

    /// Resets every "Marked…/Checking…" row, including the per-message ones
    /// inside submenus, when the menu opens again.
    @objc private func checkNowItemFired() { checkNowRow?.activate() }
    @objc private func markAllItemFired() { markAllRow?.activate() }

    /// Toggles read/unread (click or the E key).
    @objc private func markReadTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        onMarkReadMessage(message, message.isUnread)
    }

    private func menuWillOpen() {
        resetFeedbackRows()
        applyKeyHints()
        let presses = downPressesOnOpen
        downPressesOnOpen = 0
        guard presses > 0 else { return }
        // Highlight the wanted message by pressing Down that many times.
        // Common-modes Timers so they fire during menu tracking.
        for i in 0..<presses {
            let timer = Timer(timeInterval: 0.06 + 0.04 * Double(i), repeats: false) { _ in
                if let event = MenuOpenTracker.downArrowEvent() { NSApp.postEvent(event, atStart: false) }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Greyed key hints on the right of each row.
    private func applyKeyHints() {
        checkNowRow?.setHint(Settings.key(for: .checkNow))
        markAllRow?.setHint(Settings.key(for: .markAllRead))
        if let item = checkNowItem { setKeyHint(item, Settings.key(for: .checkNow)) }
        if let item = markAllItem { setKeyHint(item, Settings.key(for: .markAllRead)) }
        setKeyHint(openInboxItem, Settings.key(for: .openInbox))
        for item in recentItems + recentItems2 { applySubmenuHints(item.submenu) }
    }

    private func setKeyHint(_ item: NSMenuItem, _ key: String) {
        item.keyEquivalentModifierMask = []
        item.keyEquivalent = key
    }

    private func applySubmenuHints(_ submenu: NSMenu?) {
        for sub in submenu?.items ?? [] {
            let action: QuickKey?
            switch sub.action {
            case #selector(openInMailAppTapped(_:)): action = .openMailApp
            case #selector(openInGmailTapped(_:)): action = .openGmail
            case #selector(replyTapped(_:)): action = .reply
            case #selector(markReadTapped(_:)): action = .markRead
            case #selector(flagTapped(_:)): action = .flag
            case #selector(copyCodeTapped(_:)): action = .copyCode
            case #selector(checkLinksTapped(_:)): action = .checkLinks
            default: action = nil
            }
            if let action = action { setKeyHint(sub, Settings.key(for: action)) }
        }
    }

    private func resetFeedbackRows() {
        stayOpenRows.forEach { $0.reset() }
        for item in recentItems + recentItems2 {
            for sub in item.submenu?.items ?? [] { (sub.view as? StayOpenMenuRow)?.reset() }
        }
    }

    private func makeStayOpenItem(title: String, feedback: String, followUp: String? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        let row = StayOpenMenuRow(title: title, followUp: followUp, feedback: { _ in feedback }, action: { _ in action() })
        stayOpenRows.append(row)
        item.view = row
        return item
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func openGmailTapped() { onOpenGmail() }
    @objc private func togglePauseNotificationsTapped() { onTogglePauseNotifications() }
    @objc private func preferencesTapped() { onPreferences() }
    @objc private func quitTapped() { onQuit() }

    @objc private func replyTapped(_ sender: NSMenuItem) {
        guard let message = sender.representedObject as? MailHeader else { return }
        MessageOpener.replyInGmail(to: message)
    }

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
        customPanelController?.updateConnectionStatus(status)
    }

    func updatePauseState(isPaused: Bool) {
        pauseNotificationsItem.title = isPaused ? "Resume Notifications" : "Pause Notifications (1h)"
        customPanelController?.updatePauseState(isPaused: isPaused)
    }

    /// Pops the menu open as if the status item had been clicked — used by
    /// the global keyboard shortcut. Arrow-key navigation once it's open is
    /// native NSMenu behavior, no extra code needed.
    func showMenu() {
        if !Settings.useCustomPanel {
            if menuTracker.isOpen {
                menu.cancelTracking()
                return
            }
            // Presses made while the menu was open arrive right after it
            // closes; swallow them rather than reopening.
            if Date().timeIntervalSince(menuTracker.lastCloseDate) < 0.3 {
                NSLog("Mercury: ignoring queued shortcut press after menu close")
                return
            }
        }
        NSLog("Mercury: global shortcut fired, opening menu")
        if !Settings.useCustomPanel { downPressesOnOpen = 1 }
        let anchor = visibleButtonFrame()
        if Settings.useCustomPanel {
            customPanelController?.toggle(anchorFrame: anchor, selectNewest: true)
        } else if anchor != nil {
            statusItem.button?.performClick(nil)
        } else {
            // Item is hidden by a menu-bar manager: performClick would
            // open the menu off-screen, so pop it at the screen's top-right.
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let area = screen?.visibleFrame ?? .zero
            menu.popUp(positioning: nil, at: NSPoint(x: area.maxX - menu.size.width - 8, y: area.maxY), in: nil)
        }
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
    func update(accounts rawAccounts: [AccountDisplayState]) {
        lastAccounts = rawAccounts
        // Accounts set to "hide when no unread" lose their recent list while
        // they have nothing unread (empty sections hide themselves below).
        let accounts = rawAccounts.map { account in
            guard account.unreadCount == 0, Credentials.hideWhenNoUnread(for: account.slot) else { return account }
            return AccountDisplayState(slot: account.slot, email: account.email, displayName: account.displayName,
                                       unreadCount: 0, recentMessages: [])
        }
        customPanelController?.update(accounts: accounts)
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
            statusItem.button?.title = ""
            statusItem.button?.attributedTitle = MenuBarTitle.single(count: account.unreadCount)
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
            statusItem.button?.attributedTitle = MenuBarTitle.dual(primary: primary.unreadCount, secondary: secondary.unreadCount)

            let total = primary.unreadCount + secondary.unreadCount
            statusLabelItem.title = total > 0 ? "\(total) unread total" : "No unread mail"

            renderSection(header: recentHeaderItem, items: &recentItems, messages: showRecent ? primary.recentMessages : [], headerTitle: primary.displayName)
            renderSection(header: recentHeaderItem2, items: &recentItems2, messages: showRecent ? secondary.recentMessages : [], headerTitle: secondary.displayName)
            interSectionDivider.isHidden = !showRecent
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
        // Removing a row whose submenu is open orphans that submenu and
        // leaves the menu stuck, so while the menu is open only refresh rows
        // in place; a changed list waits until the menu closes.
        if menuTracker.isOpen {
            func key(_ m: MailHeader) -> String { "\(m.accountEmail)|\(m.uid ?? -1)|\(m.messageID ?? "")" }
            let existing = items.compactMap { ($0.representedObject as? MailHeader).map(key) }
            let incoming = messages.map(key)
            if existing.count == items.count, items.count == messages.count, Set(existing) == Set(incoming) {
                header.title = headerTitle
                let byKey = Dictionary(messages.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
                for item in items {
                    if let old = item.representedObject as? MailHeader, let message = byKey[key(old)] {
                        refreshInPlace(item, with: message)
                    }
                }
                if existing != incoming { needsRerender = true }   // reorder once the menu closes
            } else {
                needsRerender = true
            }
            return
        }
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

    private func refreshInPlace(_ item: NSMenuItem, with message: MailHeader) {
        item.attributedTitle = formattedTitle(for: message)
        item.representedObject = message
        for sub in item.submenu?.items ?? [] {
            if sub.action == #selector(markReadTapped(_:)) {
                sub.representedObject = message
                sub.title = message.isUnread ? "Mark as Read" : "Mark as Unread"
                sub.image = tintedSymbol(message.isUnread ? "envelope.open.fill" : "envelope.fill", color: .systemBlue)
            } else if sub.representedObject != nil {
                sub.representedObject = message
                if sub.action == #selector(flagTapped(_:)) { sub.title = message.isFlagged ? "Remove Flag" : "Flag" }
            }
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

        let replyItem = NSMenuItem(title: "Reply in Gmail", action: #selector(replyTapped(_:)), keyEquivalent: "")
        replyItem.target = self
        replyItem.representedObject = message
        replyItem.image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: nil)
        submenu.addItem(replyItem)

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

        if quickExtractionEnabled {
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

        }

        applySubmenuHints(submenu)
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
        NSApp.activate(ignoringOtherApps: true)
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
