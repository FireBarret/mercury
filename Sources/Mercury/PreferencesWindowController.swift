import AppKit

final class PreferencesWindowController: NSWindowController {
    private let name1Field = NSTextField()
    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let name2Field = NSTextField()
    private let email2Field = NSTextField()
    private let password2Field = NSSecureTextField()
    private let removeAccount2Button = NSButton(title: "Remove Account 2", target: nil, action: nil)

    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let previewsCheckbox = NSButton(
        checkboxWithTitle: "Show sender & subject in notifications",
        target: nil,
        action: nil
    )
    private let shortcutRecorder = ShortcutRecorderView()

    private let autoRefreshCheckbox = NSButton(
        checkboxWithTitle: "Automatically refresh Mail.app when new mail arrives",
        target: nil,
        action: nil
    )
    private let openInPopUp = NSPopUpButton()
    private let minCountStepper = NSStepper()
    private let minCountValueLabel = NSTextField(labelWithString: "")
    private let maxCountStepper = NSStepper()
    private let maxCountValueLabel = NSTextField(labelWithString: "")

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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mercury — Setup"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let fieldWidth: CGFloat = 400

        // --- Account 1 ---

        let account1SectionLabel = sectionLabel("Account 1")
        let name1Label = NSTextField(labelWithString: "Display name (optional):")
        let emailLabel = NSTextField(labelWithString: "Gmail address:")
        let passwordLabel = NSTextField(labelWithString: "App password:")
        let helpLabel = NSTextField(wrappingLabelWithString:
            "Requires 2-Step Verification. Generate an app password at:")
        helpLabel.font = NSFont.systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor

        let linkButton = makeLinkButton(
            title: "myaccount.google.com/apppasswords",
            url: "https://myaccount.google.com/apppasswords"
        )

        name1Field.placeholderString = Credentials.defaultDisplayName(for: .primary)
        name1Field.stringValue = Credentials.customDisplayName(for: .primary) ?? ""

        emailField.placeholderString = "you@gmail.com"
        emailField.stringValue = Credentials.email(for: .primary) ?? ""

        let account1Stack = NSStackView(views: [
            account1SectionLabel, name1Label, name1Field,
            emailLabel, emailField, passwordLabel, passwordField, helpLabel, linkButton
        ])
        account1Stack.orientation = .vertical
        account1Stack.alignment = .leading
        account1Stack.spacing = 6
        account1Stack.setCustomSpacing(12, after: account1SectionLabel)
        account1Stack.setCustomSpacing(14, after: name1Field)
        account1Stack.setCustomSpacing(14, after: passwordField)
        account1Stack.setCustomSpacing(2, after: helpLabel)

        // --- Account 2 (optional) ---

        let account2SectionLabel = sectionLabel("Account 2 (optional)")
        let name2Label = NSTextField(labelWithString: "Display name (optional):")
        let email2Label = NSTextField(labelWithString: "Gmail address:")
        let password2Label = NSTextField(labelWithString: "App password:")

        name2Field.placeholderString = Credentials.defaultDisplayName(for: .secondary)
        name2Field.stringValue = Credentials.customDisplayName(for: .secondary) ?? ""

        email2Field.placeholderString = "you@gmail.com"
        email2Field.stringValue = Credentials.email(for: .secondary) ?? ""

        removeAccount2Button.target = self
        removeAccount2Button.action = #selector(removeAccount2Tapped)
        removeAccount2Button.bezelStyle = .rounded
        removeAccount2Button.isHidden = Credentials.email(for: .secondary) == nil

        let account2Stack = NSStackView(views: [
            account2SectionLabel, name2Label, name2Field,
            email2Label, email2Field, password2Label, password2Field, removeAccount2Button
        ])
        account2Stack.orientation = .vertical
        account2Stack.alignment = .leading
        account2Stack.spacing = 6
        account2Stack.setCustomSpacing(12, after: account2SectionLabel)
        account2Stack.setCustomSpacing(10, after: password2Field)

        let accountStack = NSStackView(views: [account1Stack, account2Stack])
        accountStack.orientation = .vertical
        accountStack.alignment = .leading
        accountStack.spacing = 18

        // --- Options ---

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

        previewsCheckbox.target = self
        previewsCheckbox.action = #selector(previewsToggled)
        previewsCheckbox.state = Settings.showPreviews ? .on : .off

        let shortcutLabel = NSTextField(labelWithString: "Open menu shortcut:")
        if let keyCode = Settings.shortcutKeyCode, let modifiers = Settings.shortcutModifiers {
            let flags = ShortcutRecorderView.modifierFlags(fromCarbon: modifiers)
            shortcutRecorder.setDisplayString(ShortcutRecorderView.displayString(keyCode: UInt16(keyCode), modifierFlags: flags))
        }
        shortcutRecorder.onShortcutChanged = { [weak self] keyCode, modifiers, _ in
            self?.onShortcutChanged(keyCode, modifiers)
        }
        let clearShortcutButton = NSButton(title: "Clear", target: self, action: #selector(clearShortcutTapped))
        clearShortcutButton.bezelStyle = .rounded
        let shortcutRow = NSStackView(views: [shortcutRecorder, clearShortcutButton])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8

        let optionsStack = NSStackView(views: [launchAtLoginCheckbox, previewsCheckbox, shortcutLabel, shortcutRow])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 10
        optionsStack.setCustomSpacing(4, after: previewsCheckbox)

        // --- Mail behavior ---

        autoRefreshCheckbox.target = self
        autoRefreshCheckbox.action = #selector(autoRefreshToggled)
        autoRefreshCheckbox.state = Settings.autoRefreshMailApp ? .on : .off

        let openInLabel = NSTextField(labelWithString: "Open messages in:")
        openInPopUp.removeAllItems()
        openInPopUp.addItems(withTitles: MailOpenAction.allCases.map { $0.displayName })
        if let index = MailOpenAction.allCases.firstIndex(of: Settings.openMailAction) {
            openInPopUp.selectItem(at: index)
        }
        openInPopUp.target = self
        openInPopUp.action = #selector(openInChanged)
        let openInRow = NSStackView(views: [openInLabel, openInPopUp])
        openInRow.orientation = .horizontal
        openInRow.spacing = 8

        minCountStepper.minValue = 1
        minCountStepper.maxValue = 20
        minCountStepper.increment = 1
        minCountStepper.integerValue = Settings.recentListMinCount
        minCountValueLabel.stringValue = "\(Settings.recentListMinCount)"
        minCountStepper.target = self
        minCountStepper.action = #selector(minCountChanged)
        let minCountLabel = NSTextField(labelWithString: "Recent messages shown (minimum):")
        let minCountRow = NSStackView(views: [minCountLabel, minCountStepper, minCountValueLabel])
        minCountRow.orientation = .horizontal
        minCountRow.spacing = 6

        maxCountStepper.minValue = 1
        maxCountStepper.maxValue = 50
        maxCountStepper.increment = 1
        maxCountStepper.integerValue = Settings.recentListMaxCount
        maxCountValueLabel.stringValue = "\(Settings.recentListMaxCount)"
        maxCountStepper.target = self
        maxCountStepper.action = #selector(maxCountChanged)
        let maxCountLabel = NSTextField(labelWithString: "...up to this many if there's unread mail:")
        let maxCountRow = NSStackView(views: [maxCountLabel, maxCountStepper, maxCountValueLabel])
        maxCountRow.orientation = .horizontal
        maxCountRow.spacing = 6

        let mailBehaviorStack = NSStackView(views: [autoRefreshCheckbox, openInRow, minCountRow, maxCountRow])
        mailBehaviorStack.orientation = .vertical
        mailBehaviorStack.alignment = .leading
        mailBehaviorStack.spacing = 10

        // --- Save ---

        let saveButton = NSButton(title: "Save & Connect", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        let buttonRow = NSStackView(views: [saveButton])
        buttonRow.orientation = .horizontal

        let mainStack = NSStackView(views: [
            accountStack, divider(width: fieldWidth), optionsStack, divider(width: fieldWidth),
            mailBehaviorStack, divider(width: fieldWidth), buttonRow
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 18
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),

            name1Field.widthAnchor.constraint(equalToConstant: fieldWidth),
            emailField.widthAnchor.constraint(equalToConstant: fieldWidth),
            passwordField.widthAnchor.constraint(equalToConstant: fieldWidth),
            name2Field.widthAnchor.constraint(equalToConstant: fieldWidth),
            email2Field.widthAnchor.constraint(equalToConstant: fieldWidth),
            password2Field.widthAnchor.constraint(equalToConstant: fieldWidth),
            helpLabel.widthAnchor.constraint(equalToConstant: fieldWidth)
        ])
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        return label
    }

    private func divider(width: CGFloat) -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
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

    @objc private func clearShortcutTapped() {
        shortcutRecorder.setDisplayString("")
        onShortcutChanged(nil, nil)
    }

    @objc private func autoRefreshToggled() {
        Settings.autoRefreshMailApp = (autoRefreshCheckbox.state == .on)
    }

    @objc private func openInChanged() {
        let index = openInPopUp.indexOfSelectedItem
        let actions = MailOpenAction.allCases
        guard index >= 0, index < actions.count else { return }
        Settings.openMailAction = actions[index]
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
