import AppKit

final class PreferencesWindowController: NSWindowController {
    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let previewsCheckbox = NSButton(
        checkboxWithTitle: "Show sender & subject in notifications",
        target: nil,
        action: nil
    )
    private let shortcutRecorder = ShortcutRecorderView()
    private let onSave: (String, String) -> Void
    private let onShortcutChanged: (UInt32?, UInt32?) -> Void

    init(onSave: @escaping (String, String) -> Void, onShortcutChanged: @escaping (UInt32?, UInt32?) -> Void) {
        self.onSave = onSave
        self.onShortcutChanged = onShortcutChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mail Notification Buddy — Setup"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let fieldWidth: CGFloat = 400

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

        emailField.placeholderString = "you@gmail.com"
        emailField.stringValue = Credentials.email ?? ""

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

        let saveButton = NSButton(title: "Save & Connect", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let accountStack = NSStackView(views: [emailLabel, emailField, passwordLabel, passwordField, helpLabel, linkButton])
        accountStack.orientation = .vertical
        accountStack.alignment = .leading
        accountStack.spacing = 6
        accountStack.setCustomSpacing(14, after: passwordField)
        accountStack.setCustomSpacing(2, after: helpLabel)

        let optionsStack = NSStackView(views: [launchAtLoginCheckbox, previewsCheckbox, shortcutLabel, shortcutRow])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 10
        optionsStack.setCustomSpacing(4, after: previewsCheckbox)

        let buttonRow = NSStackView(views: [saveButton])
        buttonRow.orientation = .horizontal

        let mainStack = NSStackView(views: [
            accountStack, divider(width: fieldWidth), optionsStack, divider(width: fieldWidth), buttonRow
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

            emailField.widthAnchor.constraint(equalToConstant: fieldWidth),
            passwordField.widthAnchor.constraint(equalToConstant: fieldWidth),
            helpLabel.widthAnchor.constraint(equalToConstant: fieldWidth)
        ])
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

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func saveTapped() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { return }
        onSave(email, password)
        window?.close()
    }
}
