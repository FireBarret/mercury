import AppKit

private enum Layout {
    static let inset: CGFloat = 28
    static let contentWidth: CGFloat = 560
    static let gridWidth: CGFloat = contentWidth - inset * 2
    static let rowSpacing: CGFloat = 16
    static let columnSpacing: CGFloat = 14
    static let blockGap: CGFloat = 12
    static let fieldWidth: CGFloat = 260
    static let popUpWidth: CGFloat = 240
}

/// A two-column form (labels right-aligned, controls left-aligned) built on
/// NSGridView, in the style of Things' preferences: label/control rows on
/// top, a hairline, then a block of checkboxes flush left with small gray
/// explanations underneath.
private final class FormBuilder {
    let grid = NSGridView()

    init() {
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = Layout.rowSpacing
        grid.columnSpacing = Layout.columnSpacing
        grid.addColumn(with: [])
        grid.addColumn(with: [])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .none
    }

    private func addMerged(_ view: NSView, placement: NSGridCell.Placement = .leading) {
        let row = grid.addRow(with: [view, NSGridCell.emptyContentView])
        grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2),
                        verticalRange: NSRange(location: grid.numberOfRows - 1, length: 1))
        row.cell(at: 0).xPlacement = placement
        row.yPlacement = .center
    }

    /// Small bold caption, for pages that hold more than one group (Accounts).
    func section(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        addMerged(label)
    }

    func row(_ label: String, _ control: NSView) {
        let row = grid.addRow(with: [NSTextField(labelWithString: label), control])
        row.yPlacement = .center
    }

    /// A control in the right-hand column with no label.
    func control(_ view: NSView) {
        grid.addRow(with: [NSGridCell.emptyContentView, view]).yPlacement = .center
    }

    func separator() {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Layout.gridWidth).isActive = true
        addMerged(box, placement: .fill)
        let index = grid.numberOfRows - 1
        grid.row(at: index).topPadding = Layout.blockGap
        grid.row(at: index).bottomPadding = Layout.blockGap
    }

    /// A checkbox flush with the left edge of the form, with an optional
    /// small gray explanation beneath it.
    func checkbox(_ button: NSButton, note: String? = nil) {
        guard let note = note else {
            addMerged(button)
            return
        }
        let label = NSTextField(wrappingLabelWithString: note)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor
        label.preferredMaxLayoutWidth = Layout.gridWidth - 22
        label.widthAnchor.constraint(equalToConstant: Layout.gridWidth - 22).isActive = true
        let stack = NSStackView(views: [button, label])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.setCustomSpacing(3, after: button)
        // Indent the note under the checkbox's title.
        label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 22).isActive = true
        addMerged(stack)
    }

    func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor
        label.preferredMaxLayoutWidth = 320
        label.widthAnchor.constraint(equalToConstant: 320).isActive = true
        grid.addRow(with: [NSGridCell.emptyContentView, label])
    }

    func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }
}

/// One tab of the preferences window.
private final class FormPageViewController: NSViewController {
    private let grid: NSGridView

    init(title: String, form: FormBuilder) {
        self.grid = form.grid
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: Layout.inset),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: Layout.inset),
            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Layout.inset)
        ])
        view = root
        preferredContentSize = NSSize(
            width: Layout.contentWidth,
            height: grid.fittingSize.height + Layout.inset * 2
        )
    }
}

/// A fake menu-bar strip showing the envelope + unread numbers exactly as
/// the status item renders them.
private final class MenuBarPreviewView: NSView {
    private let render: () -> NSAttributedString
    private let titleLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()

    init(caption: String, render: @escaping () -> NSAttributedString) {
        self.render = render
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "envelope.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.contentTintColor = NSColor.labelColor
        let row = NSStackView(views: [icon, titleLabel])
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(equalToConstant: 84),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityLabel("Menu bar preview, \(caption)")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        // Strings without an explicit color (default single-account count)
        // get the label color, since there's no status button to supply one.
        let text = NSMutableAttributedString(attributedString: render())
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        titleLabel.attributedStringValue = text
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }
}

final class PreferencesWindowController: NSWindowController {
    private let name1Field = NSTextField()
    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let name2Field = NSTextField()
    private let email2Field = NSTextField()
    private let password2Field = NSSecureTextField()
    private let removeAccount2Button = NSButton(title: "Remove Account 2", target: nil, action: nil)
    private let notify1Checkbox = NSButton(checkboxWithTitle: "Notify for new mail", target: nil, action: nil)
    private let notify2Checkbox = NSButton(checkboxWithTitle: "Notify for new mail", target: nil, action: nil)
    private let hide1Checkbox = NSButton(checkboxWithTitle: "Hide when no unread mail", target: nil, action: nil)
    private let hide2Checkbox = NSButton(checkboxWithTitle: "Hide when no unread mail", target: nil, action: nil)

    private let color1Well = ColorCircleView(accessibilityName: "Primary account number color")
    private let color2Well = ColorCircleView(accessibilityName: "Secondary account number color")
    private let singleColorWell = ColorCircleView(accessibilityName: "Single account number color")
    private var previews: [MenuBarPreviewView] = []

    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let previewsCheckbox = NSButton(
        checkboxWithTitle: "Show sender & subject in notifications",
        target: nil,
        action: nil
    )
    private let playSoundCheckbox = NSButton(
        checkboxWithTitle: "Play sound for notifications",
        target: nil,
        action: nil
    )
    private let showRecentCheckbox = NSButton(
        checkboxWithTitle: "Show recent messages in menu",
        target: nil,
        action: nil
    )
    private let glassCheckbox = NSButton(
        checkboxWithTitle: "Liquid Glass look (macOS 26+)",
        target: nil,
        action: nil
    )
    private let shortcutRecorder = ShortcutRecorderView()

    private let mailAppRefreshPopUp = NSPopUpButton()
    private let openInPopUp = NSPopUpButton()
    private let orderPopUp = NSPopUpButton()
    private let minCountStepper = NSStepper()
    private let minCountValueLabel = NSTextField(labelWithString: "")
    private let maxCountStepper = NSStepper()
    private let maxCountValueLabel = NSTextField(labelWithString: "")

    private let useCustomPanelCheckbox = NSButton(
        checkboxWithTitle: "Use custom swipeable panel (Beta)",
        target: nil,
        action: nil
    )
    private let rightStep1PopUp = NSPopUpButton()
    private let rightStep2PopUp = NSPopUpButton()
    private let leftStep1PopUp = NSPopUpButton()
    private let leftStep2PopUp = NSPopUpButton()

    private let tabController = NSTabViewController()

    private let onSaveAccount: (String, String, AccountSlot) -> Void
    private let onRemoveAccount: (AccountSlot) -> Void
    private let onShortcutChanged: (UInt32?, UInt32?) -> Void
    private let onDisplaySettingsChanged: () -> Void

    init(
        onSaveAccount: @escaping (String, String, AccountSlot) -> Void,
        onRemoveAccount: @escaping (AccountSlot) -> Void,
        onShortcutChanged: @escaping (UInt32?, UInt32?) -> Void,
        onDisplaySettingsChanged: @escaping () -> Void
    ) {
        self.onSaveAccount = onSaveAccount
        self.onRemoveAccount = onRemoveAccount
        self.onShortcutChanged = onShortcutChanged
        self.onDisplaySettingsChanged = onDisplaySettingsChanged

        tabController.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        addTab(title: "General", symbol: "gearshape", form: buildGeneralForm())
        addTab(title: "Menu Bar", symbol: "menubar.rectangle", form: buildMenuBarForm())
        addTab(title: "Accounts", symbol: "person.crop.circle", form: buildAccountsForm())
        addTab(title: "Swipe Panel", symbol: "hand.draw", form: buildSwipeForm())
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addTab(title: String, symbol: String, form: FormBuilder) {
        let page = FormPageViewController(title: title, form: form)
        let item = NSTabViewItem(viewController: page)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabController.addTabViewItem(item)
    }

    var tabCount: Int { tabController.tabViewItems.count }

    func selectTab(_ index: Int) {
        tabController.selectedTabViewItemIndex = index
        if let size = tabController.tabViewItems[index].viewController?.preferredContentSize {
            window?.setContentSize(size)
        }
    }

    // MARK: - General

    private func buildGeneralForm() -> FormBuilder {
        let form = FormBuilder()

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

        previewsCheckbox.target = self
        previewsCheckbox.action = #selector(previewsToggled)
        previewsCheckbox.state = Settings.showPreviews ? .on : .off

        playSoundCheckbox.target = self
        playSoundCheckbox.action = #selector(playSoundToggled)
        playSoundCheckbox.state = Settings.playNotificationSound ? .on : .off

        if let keyCode = Settings.shortcutKeyCode, let modifiers = Settings.shortcutModifiers {
            let flags = ShortcutRecorderView.modifierFlags(fromCarbon: modifiers)
            shortcutRecorder.setDisplayString(ShortcutRecorderView.displayString(keyCode: UInt16(keyCode), modifierFlags: flags))
        } else {
            shortcutRecorder.setDisplayString("")
        }
        shortcutRecorder.onShortcutChanged = { [weak self] keyCode, modifiers, _ in
            self?.onShortcutChanged(keyCode, modifiers)
        }
        let clearShortcutButton = NSButton(title: "Clear", target: self, action: #selector(clearShortcutTapped))
        clearShortcutButton.bezelStyle = .rounded

        configurePopUp(mailAppRefreshPopUp, titles: MailAppRefreshMode.allCases.map { $0.displayName },
                       selected: MailAppRefreshMode.allCases.firstIndex(of: Settings.mailAppRefreshMode),
                       action: #selector(mailAppRefreshModeChanged))
        configurePopUp(openInPopUp, titles: MailOpenAction.allCases.map { $0.displayName },
                       selected: MailOpenAction.allCases.firstIndex(of: Settings.openMailAction),
                       action: #selector(openInChanged))

        form.row("When new mail arrives:", mailAppRefreshPopUp)
        form.row("Open messages in:", openInPopUp)
        form.row("Open menu shortcut:", form.horizontal([shortcutRecorder, clearShortcutButton]))

        form.separator()

        form.checkbox(launchAtLoginCheckbox)
        form.checkbox(previewsCheckbox)
        form.checkbox(playSoundCheckbox)
        return form
    }

    // MARK: - Menu Bar

    private func buildMenuBarForm() -> FormBuilder {
        let form = FormBuilder()

        let onePreview = MenuBarPreviewView(caption: "one account") { MenuBarTitle.single(count: 3) }
        let twoPreview = MenuBarPreviewView(caption: "two accounts") { MenuBarTitle.dual(primary: 3, secondary: 2) }
        previews = [onePreview, twoPreview]

        let wells: [(ColorCircleView, NSColor, Selector)] = [
            (color1Well, Settings.countColor(for: .primary), #selector(color1Changed)),
            (color2Well, Settings.countColor(for: .secondary), #selector(color2Changed)),
            (singleColorWell, Settings.singleAccountCountColor ?? NSColor.labelColor, #selector(singleColorChanged))
        ]
        for (well, color, changed) in wells {
            well.color = color
            well.target = self
            well.action = changed
            well.widthAnchor.constraint(equalToConstant: 24).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let resetColorsButton = NSButton(title: "Restore Default Colors", target: self, action: #selector(resetAllColors))
        resetColorsButton.bezelStyle = .rounded

        showRecentCheckbox.target = self
        showRecentCheckbox.action = #selector(showRecentToggled)
        showRecentCheckbox.state = Settings.showRecentMessagesInMenu ? .on : .off

        configurePopUp(orderPopUp, titles: RecentListOrder.allCases.map { $0.displayName },
                       selected: RecentListOrder.allCases.firstIndex(of: Settings.recentListOrder),
                       action: #selector(orderChanged))

        minCountStepper.minValue = 1
        minCountStepper.maxValue = 20
        minCountStepper.increment = 1
        minCountStepper.integerValue = Settings.recentListMinCount
        minCountValueLabel.stringValue = "\(Settings.recentListMinCount)"
        minCountStepper.target = self
        minCountStepper.action = #selector(minCountChanged)

        maxCountStepper.minValue = 1
        maxCountStepper.maxValue = 50
        maxCountStepper.increment = 1
        maxCountStepper.integerValue = Settings.recentListMaxCount
        maxCountValueLabel.stringValue = "\(Settings.recentListMaxCount)"
        maxCountStepper.target = self
        maxCountStepper.action = #selector(maxCountChanged)

        form.row("Preview:", form.horizontal([onePreview, twoPreview], spacing: 12))
        form.row("Primary account number:", color1Well)
        form.row("Secondary account number:", color2Well)
        form.row("Single account number:", singleColorWell)
        form.control(resetColorsButton)

        form.separator()

        form.row("Recent list order:", orderPopUp)
        form.row("Messages shown (minimum):", form.horizontal([minCountStepper, minCountValueLabel], spacing: 6))
        form.row("Up to, if there's unread mail:", form.horizontal([maxCountStepper, maxCountValueLabel], spacing: 6))

        form.separator()

        form.checkbox(showRecentCheckbox, note: "Lists your latest messages under the menu bar icon.")
        return form
    }

    // MARK: - Accounts

    private func buildAccountsForm() -> FormBuilder {
        let form = FormBuilder()

        name1Field.placeholderString = Credentials.defaultDisplayName(for: .primary)
        name1Field.stringValue = Credentials.customDisplayName(for: .primary) ?? ""
        emailField.placeholderString = "you@gmail.com"
        emailField.stringValue = Credentials.email(for: .primary) ?? ""

        name2Field.placeholderString = Credentials.defaultDisplayName(for: .secondary)
        name2Field.stringValue = Credentials.customDisplayName(for: .secondary) ?? ""
        email2Field.placeholderString = "you@gmail.com"
        email2Field.stringValue = Credentials.email(for: .secondary) ?? ""

        for field in [name1Field, emailField, passwordField, name2Field, email2Field, password2Field] {
            field.widthAnchor.constraint(equalToConstant: Layout.fieldWidth).isActive = true
        }

        notify1Checkbox.target = self
        notify1Checkbox.action = #selector(notify1Toggled)
        notify1Checkbox.state = Credentials.notificationsEnabled(for: .primary) ? .on : .off
        hide1Checkbox.target = self
        hide1Checkbox.action = #selector(hide1Toggled)
        hide1Checkbox.state = Credentials.hideWhenNoUnread(for: .primary) ? .on : .off

        notify2Checkbox.target = self
        notify2Checkbox.action = #selector(notify2Toggled)
        notify2Checkbox.state = Credentials.notificationsEnabled(for: .secondary) ? .on : .off
        hide2Checkbox.target = self
        hide2Checkbox.action = #selector(hide2Toggled)
        hide2Checkbox.state = Credentials.hideWhenNoUnread(for: .secondary) ? .on : .off

        removeAccount2Button.target = self
        removeAccount2Button.action = #selector(removeAccount2Tapped)
        removeAccount2Button.bezelStyle = .rounded
        removeAccount2Button.isHidden = Credentials.email(for: .secondary) == nil

        let saveButton = NSButton(title: "Save & Connect", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let linkButton = makeLinkButton(
            title: "myaccount.google.com/apppasswords",
            url: "https://myaccount.google.com/apppasswords"
        )

        form.section("Account 1")
        form.row("Display name:", name1Field)
        form.row("Gmail address:", emailField)
        form.row("App password:", passwordField)
        form.control(notify1Checkbox)
        form.control(hide1Checkbox)
        form.note("Requires 2-Step Verification. Create an app password at:")
        form.control(linkButton)

        form.separator()

        form.section("Account 2 (optional)")
        form.row("Display name:", name2Field)
        form.row("Gmail address:", email2Field)
        form.row("App password:", password2Field)
        form.control(notify2Checkbox)
        form.control(hide2Checkbox)
        form.control(removeAccount2Button)

        form.separator()

        form.control(saveButton)
        return form
    }

    // MARK: - Swipe Panel

    private func buildSwipeForm() -> FormBuilder {
        let form = FormBuilder()

        useCustomPanelCheckbox.target = self
        useCustomPanelCheckbox.action = #selector(useCustomPanelToggled)
        useCustomPanelCheckbox.state = Settings.useCustomPanel ? .on : .off

        glassCheckbox.target = self
        glassCheckbox.action = #selector(glassToggled)
        glassCheckbox.state = Settings.useGlassEffect ? .on : .off

        configureSwipePopUp(rightStep1PopUp, current: Settings.rightSwipeStep1, action: #selector(rightStep1Changed))
        configureSwipePopUp(rightStep2PopUp, current: Settings.rightSwipeStep2, action: #selector(rightStep2Changed))
        configureSwipePopUp(leftStep1PopUp, current: Settings.leftSwipeStep1, action: #selector(leftStep1Changed))
        configureSwipePopUp(leftStep2PopUp, current: Settings.leftSwipeStep2, action: #selector(leftStep2Changed))

        form.row("Swipe right:", rightStep1PopUp)
        form.row("Swipe right, far:", rightStep2PopUp)
        form.row("Swipe left:", leftStep1PopUp)
        form.row("Swipe left, far:", leftStep2PopUp)

        form.separator()

        form.checkbox(useCustomPanelCheckbox,
                      note: "Replaces the dropdown with a floating panel where you can swipe messages with two fingers, like Mail.app. Each direction reveals up to two actions -- swipe further to trigger the second one immediately.")
        form.checkbox(glassCheckbox)

        updateSwipeControlsEnabled()
        return form
    }

    private func updateSwipeControlsEnabled() {
        let enabled = Settings.useCustomPanel
        let controls: [NSControl] = [glassCheckbox, rightStep1PopUp, rightStep2PopUp, leftStep1PopUp, leftStep2PopUp]
        for control in controls {
            control.isEnabled = enabled
        }
    }

    // MARK: - Helpers

    private func configurePopUp(_ popUp: NSPopUpButton, titles: [String], selected: Int?, action: Selector) {
        popUp.removeAllItems()
        popUp.addItems(withTitles: titles)
        if let selected = selected { popUp.selectItem(at: selected) }
        popUp.target = self
        popUp.action = action
        popUp.widthAnchor.constraint(equalToConstant: Layout.popUpWidth).isActive = true
    }

    private func configureSwipePopUp(_ popUp: NSPopUpButton, current: SwipeAction, action: Selector) {
        configurePopUp(popUp, titles: SwipeAction.allCases.map { $0.displayName },
                       selected: SwipeAction.allCases.firstIndex(of: current), action: action)
    }

    private func makeLinkButton(title: String, url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(linkTapped(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 11)
        ])
        button.identifier = NSUserInterfaceItemIdentifier(url)
        return button
    }

    private func refreshPreviews() {
        previews.forEach { $0.refresh() }
    }

    // MARK: - Actions

    @objc private func linkTapped(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func launchAtLoginToggled() {
        LaunchAtLogin.setEnabled(launchAtLoginCheckbox.state == .on)
    }

    @objc private func previewsToggled() {
        Settings.showPreviews = (previewsCheckbox.state == .on)
    }

    @objc private func playSoundToggled() {
        Settings.playNotificationSound = (playSoundCheckbox.state == .on)
    }

    @objc private func showRecentToggled() {
        Settings.showRecentMessagesInMenu = (showRecentCheckbox.state == .on)
        onDisplaySettingsChanged()
    }

    @objc private func notify1Toggled() {
        Credentials.setNotificationsEnabled(notify1Checkbox.state == .on, for: .primary)
    }

    @objc private func notify2Toggled() {
        Credentials.setNotificationsEnabled(notify2Checkbox.state == .on, for: .secondary)
    }

    @objc private func hide1Toggled() {
        Credentials.setHideWhenNoUnread(hide1Checkbox.state == .on, for: .primary)
        onDisplaySettingsChanged()
    }

    @objc private func hide2Toggled() {
        Credentials.setHideWhenNoUnread(hide2Checkbox.state == .on, for: .secondary)
        onDisplaySettingsChanged()
    }

    @objc private func color1Changed() {
        Settings.setCountColor(color1Well.color, for: .primary)
        refreshPreviews()
        onDisplaySettingsChanged()
    }

    @objc private func color2Changed() {
        Settings.setCountColor(color2Well.color, for: .secondary)
        refreshPreviews()
        onDisplaySettingsChanged()
    }

    @objc private func singleColorChanged() {
        Settings.singleAccountCountColor = singleColorWell.color
        refreshPreviews()
        onDisplaySettingsChanged()
    }

    @objc private func resetAllColors() {
        Settings.setCountColor(nil, for: .primary)
        Settings.setCountColor(nil, for: .secondary)
        Settings.singleAccountCountColor = nil
        color1Well.color = Settings.countColor(for: .primary)
        color2Well.color = Settings.countColor(for: .secondary)
        singleColorWell.color = NSColor.labelColor
        refreshPreviews()
        onDisplaySettingsChanged()
    }

    @objc private func clearShortcutTapped() {
        shortcutRecorder.setDisplayString("")
        onShortcutChanged(nil, nil)
    }

    @objc private func mailAppRefreshModeChanged() {
        let index = mailAppRefreshPopUp.indexOfSelectedItem
        let modes = MailAppRefreshMode.allCases
        guard index >= 0, index < modes.count else { return }
        Settings.mailAppRefreshMode = modes[index]
    }

    @objc private func openInChanged() {
        let index = openInPopUp.indexOfSelectedItem
        let actions = MailOpenAction.allCases
        guard index >= 0, index < actions.count else { return }
        Settings.openMailAction = actions[index]
    }

    @objc private func glassToggled() {
        Settings.useGlassEffect = (glassCheckbox.state == .on)
        onDisplaySettingsChanged()
    }

    @objc private func orderChanged() {
        let index = orderPopUp.indexOfSelectedItem
        let orders = RecentListOrder.allCases
        guard index >= 0, index < orders.count else { return }
        Settings.recentListOrder = orders[index]
        onDisplaySettingsChanged()
    }

    @objc private func minCountChanged() {
        let value = minCountStepper.integerValue
        if value > maxCountStepper.integerValue {
            maxCountStepper.integerValue = value
            maxCountValueLabel.stringValue = "\(value)"
            Settings.recentListMaxCount = value
        }
        minCountValueLabel.stringValue = "\(value)"
        Settings.recentListMinCount = value
        onDisplaySettingsChanged()
    }

    @objc private func maxCountChanged() {
        let value = maxCountStepper.integerValue
        if value < minCountStepper.integerValue {
            minCountStepper.integerValue = value
            minCountValueLabel.stringValue = "\(value)"
            Settings.recentListMinCount = value
        }
        maxCountValueLabel.stringValue = "\(value)"
        Settings.recentListMaxCount = value
        onDisplaySettingsChanged()
    }

    @objc private func useCustomPanelToggled() {
        Settings.useCustomPanel = (useCustomPanelCheckbox.state == .on)
        updateSwipeControlsEnabled()
        onDisplaySettingsChanged()
    }

    @objc private func rightStep1Changed() { swipeChanged(rightStep1PopUp) { Settings.rightSwipeStep1 = $0 } }
    @objc private func rightStep2Changed() { swipeChanged(rightStep2PopUp) { Settings.rightSwipeStep2 = $0 } }
    @objc private func leftStep1Changed() { swipeChanged(leftStep1PopUp) { Settings.leftSwipeStep1 = $0 } }
    @objc private func leftStep2Changed() { swipeChanged(leftStep2PopUp) { Settings.leftSwipeStep2 = $0 } }

    private func swipeChanged(_ popUp: NSPopUpButton, store: (SwipeAction) -> Void) {
        let index = popUp.indexOfSelectedItem
        let actions = SwipeAction.allCases
        guard index >= 0, index < actions.count else { return }
        store(actions[index])
        onDisplaySettingsChanged()
    }

    @objc private func removeAccount2Tapped() {
        onRemoveAccount(.secondary)
        name2Field.stringValue = ""
        email2Field.stringValue = ""
        password2Field.stringValue = ""
        removeAccount2Button.isHidden = true
        onDisplaySettingsChanged()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }

    @objc private func saveTapped() {
        let name1 = name1Field.stringValue.trimmingCharacters(in: .whitespaces)
        Credentials.setDisplayName(name1.isEmpty ? nil : name1, for: .primary)

        let email1 = emailField.stringValue.trimmingCharacters(in: .whitespaces)
        let password1 = passwordField.stringValue.trimmingCharacters(in: .whitespaces)
        if !email1.isEmpty && !password1.isEmpty {
            onSaveAccount(email1, password1, .primary)
        }

        let name2 = name2Field.stringValue.trimmingCharacters(in: .whitespaces)
        Credentials.setDisplayName(name2.isEmpty ? nil : name2, for: .secondary)

        let email2 = email2Field.stringValue.trimmingCharacters(in: .whitespaces)
        let password2 = password2Field.stringValue.trimmingCharacters(in: .whitespaces)
        if !email2.isEmpty && !password2.isEmpty {
            onSaveAccount(email2, password2, .secondary)
            removeAccount2Button.isHidden = false
        }

        onDisplaySettingsChanged()
        window?.close()
    }
}
