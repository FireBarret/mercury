import AppKit

/// First-run walkthrough, shown at launch when no Gmail account is
/// configured: turn on 2-Step Verification, create an app password, then
/// enter the address and password. The credentials are only saved once a
/// real login to Gmail succeeds.
final class OnboardingWindowController: NSWindowController {
    private struct Page {
        let title: String
        let body: String
        let linkTitle: String?
        let linkURL: String?
    }

    private let pages: [Page] = [
        Page(
            title: "Welcome to Mercury",
            body: "Mercury lives in your menu bar and shows your unread Gmail. It signs in with a Google app password, so nothing goes through anyone else's server.\n\nFirst, make sure 2-Step Verification is turned on for your Google account -- Google only offers app passwords once it is.",
            linkTitle: "myaccount.google.com/signinoptions/twosv",
            linkURL: "https://myaccount.google.com/signinoptions/twosv"
        ),
        Page(
            title: "Create an app password",
            body: "Open the page below, name the password \"Mercury\", and click Create. Google shows a 16-character password once -- copy it, then continue.",
            linkTitle: "myaccount.google.com/apppasswords",
            linkURL: "https://myaccount.google.com/apppasswords"
        )
    ]

    private let iconView = NSImageView()
    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let linkButton = NSButton()
    private let formStack = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let dotsStack = NSStackView()
    private let contentStack = NSStackView()

    private var pageIndex = 0
    private var isConnecting = false
    private var pageCount: Int { pages.count + 1 }

    /// Verifies the login and, on success, saves it. Calls back on the main
    /// thread with nil for success or a message to show.
    private let onConnect: (String, String, @escaping (String?) -> Void) -> Void

    init(onConnect: @escaping (String, String, @escaping (String?) -> Void) -> Void) {
        self.onConnect = onConnect
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Mercury"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityLabel("Mercury")
        iconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.preferredMaxLayoutWidth = 400

        linkButton.isBordered = false
        linkButton.bezelStyle = .inline
        linkButton.target = self
        linkButton.action = #selector(linkTapped)
        linkButton.refusesFirstResponder = true
        linkButton.focusRingType = .none

        emailField.placeholderString = "you@gmail.com"
        passwordField.placeholderString = "16-character app password"
        let emailLabel = NSTextField(labelWithString: "Gmail address:")
        let passwordLabel = NSTextField(labelWithString: "App password:")
        formStack.setViews([emailLabel, emailField, passwordLabel, passwordField], in: .leading)
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 6
        formStack.setCustomSpacing(14, after: emailField)

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.preferredMaxLayoutWidth = 400
        statusLabel.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isIndeterminate = true

        dotsStack.orientation = .horizontal
        dotsStack.spacing = 6
        for index in 0..<pageCount {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dot.setAccessibilityLabel("Step \(index + 1) of \(pageCount)")
            dotsStack.addArrangedSubview(dot)
        }

        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [dotsStack, NSView(), spinner, backButton, nextButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let headerRow = NSStackView(views: [iconView, titleLabel])
        headerRow.orientation = .horizontal
        headerRow.spacing = 14
        headerRow.alignment = .centerY

        let stack = contentStack
        stack.setViews([headerRow, bodyLabel, linkButton, formStack, statusLabel, buttonRow], in: .leading)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(22, after: formStack)
        stack.setCustomSpacing(22, after: linkButton)
        stack.setCustomSpacing(22, after: statusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            bodyLabel.widthAnchor.constraint(equalToConstant: 400),
            statusLabel.widthAnchor.constraint(equalToConstant: 400),
            emailField.widthAnchor.constraint(equalToConstant: 400),
            passwordField.widthAnchor.constraint(equalToConstant: 400),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func render() {
        let onForm = pageIndex == pages.count
        backButton.isHidden = pageIndex == 0
        formStack.isHidden = !onForm
        iconView.isHidden = pageIndex != 0
        updateDots()

        if onForm {
            titleLabel.stringValue = "Connect your account"
            bodyLabel.stringValue = "Enter your Gmail address and the app password you just created. They're kept in your Mac's Keychain."
            linkButton.isHidden = true
            nextButton.title = "Connect"
            window?.makeFirstResponder(emailField)
        } else {
            statusLabel.isHidden = true
            let page = pages[pageIndex]
            titleLabel.stringValue = page.title
            bodyLabel.stringValue = page.body
            linkButton.isHidden = page.linkTitle == nil
            if let linkTitle = page.linkTitle {
                linkButton.attributedTitle = NSAttributedString(string: linkTitle, attributes: [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: NSFont.systemFont(ofSize: 13)
                ])
            }
            nextButton.title = "Next"
        }
        fitWindowToContent()
    }

    private func updateDots() {
        for (index, dot) in dotsStack.arrangedSubviews.enumerated() {
            dot.effectiveAppearance.performAsCurrentDrawingAppearance {
                dot.layer?.backgroundColor = (index == pageIndex
                    ? NSColor.controlAccentColor
                    : NSColor.tertiaryLabelColor).cgColor
            }
        }
    }

    /// Shrinks or grows the window to hug the current page, keeping its top
    /// edge fixed.
    private func fitWindowToContent() {
        guard let window = window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let height = contentStack.fittingSize.height + 24 + 22
        var frame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 460, height: height))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        window.setFrame(frame, display: true)
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? NSColor.systemRed : NSColor.secondaryLabelColor
        statusLabel.isHidden = false
        fitWindowToContent()
    }

    private func setConnecting(_ connecting: Bool) {
        isConnecting = connecting
        nextButton.isEnabled = !connecting
        backButton.isEnabled = !connecting
        emailField.isEnabled = !connecting
        passwordField.isEnabled = !connecting
        if connecting { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func linkTapped() {
        guard pageIndex < pages.count,
              let urlString = pages[pageIndex].linkURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func backTapped() {
        pageIndex = max(0, pageIndex - 1)
        render()
    }

    @objc private func nextTapped() {
        if pageIndex < pages.count {
            pageIndex += 1
            render()
            return
        }
        guard !isConnecting else { return }
        let email = emailField.stringValue.trimmingCharacters(in: .whitespaces)
        // Google displays app passwords in 4 groups separated by spaces.
        let password = passwordField.stringValue.filter { !$0.isWhitespace }
        guard !email.isEmpty, !password.isEmpty else {
            NSSound.beep()
            showStatus("Enter both your Gmail address and the app password.", isError: true)
            return
        }
        setConnecting(true)
        showStatus("Connecting to Gmail…", isError: false)
        onConnect(email, password) { [weak self] error in
            guard let self = self else { return }
            self.setConnecting(false)
            if let error = error {
                self.showStatus(error, isError: true)
            } else {
                self.showStatus("Connected as \(email) ✓", isError: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.window?.close() }
            }
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// For the snapshot tool: jump straight to a page.
    func showPage(_ index: Int) {
        pageIndex = min(max(0, index), pageCount - 1)
        render()
    }
}
