import AppKit

/// A single message row with real two-finger trackpad swipe-to-reveal,
/// used only inside the custom panel (Settings.useCustomPanel) -- this is
/// a plain NSView in a real window, not hosted inside an NSMenu, so normal
/// AppKit event handling applies with none of the uncertainty custom
/// NSMenuItem views carry.
///
/// Swiping right (content moves right) reveals leading-edge actions on the
/// left, matching Mail.app's own convention of putting Unread there.
/// Swiping left reveals trailing-edge actions on the right, matching
/// Mail.app's Flag placement. A modest swipe reveals the Step 1 button (and
/// Step 2's, once revealed enough); releasing past the Step 2 threshold
/// auto-commits Step 2 immediately, matching Mail.app's "far swipe"
/// convention for its default action.
final class SwipeableMessageRowView: NSView {
    private let message: MailHeader
    private let contentContainer = NSView()
    private let contentLabel = NSTextField(labelWithString: "")
    private let leftActionsContainer = NSView()
    private let rightActionsContainer = NSView()
    private var leftButtons: [SwipeActionButton] = []
    private var rightButtons: [SwipeActionButton] = []

    private var contentOffset: CGFloat = 0 {
        didSet { layoutContent() }
    }
    private var gestureAccumulator: CGFloat = 0
    private var isTrackingGesture = false

    private let step1Threshold: CGFloat = 60
    private let step2Threshold: CGFloat = 130
    private let maxReveal: CGFloat = 150
    // Flip this to -1 if real-world testing shows the swipe direction feels
    // backwards -- sign conventions for trackpad scrollingDeltaX can vary
    // and this isn't something testable without a physical trackpad.
    private let directionMultiplier: CGFloat = 1

    var onTapOpen: (() -> Void)?
    var onAction: ((SwipeAction) -> Void)?

    init(message: MailHeader, attributedText: NSAttributedString) {
        self.message = message
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 46))
        wantsLayer = true
        buildUI(attributedText: attributedText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(attributedText: NSAttributedString) {
        addSubview(leftActionsContainer)
        addSubview(rightActionsContainer)
        addSubview(contentContainer)

        leftActionsContainer.wantsLayer = true
        rightActionsContainer.wantsLayer = true
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        leftButtons = [
            SwipeActionButton(action: Settings.rightSwipeStep1) { [weak self] in self?.commit(Settings.rightSwipeStep1) },
            SwipeActionButton(action: Settings.rightSwipeStep2) { [weak self] in self?.commit(Settings.rightSwipeStep2) }
        ]
        rightButtons = [
            SwipeActionButton(action: Settings.leftSwipeStep1) { [weak self] in self?.commit(Settings.leftSwipeStep1) },
            SwipeActionButton(action: Settings.leftSwipeStep2) { [weak self] in self?.commit(Settings.leftSwipeStep2) }
        ]
        leftButtons.forEach { leftActionsContainer.addSubview($0) }
        rightButtons.forEach { rightActionsContainer.addSubview($0) }

        contentLabel.attributedStringValue = attributedText
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.maximumNumberOfLines = 2
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentLabel)
        NSLayoutConstraint.activate([
            contentLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -12),
            contentLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        contentContainer.addGestureRecognizer(clickGesture)
    }

    override func layout() {
        super.layout()
        leftActionsContainer.frame = NSRect(x: 0, y: 0, width: maxReveal, height: bounds.height)
        rightActionsContainer.frame = NSRect(x: bounds.width - maxReveal, y: 0, width: maxReveal, height: bounds.height)
        layoutActionButtons(in: leftActionsContainer, buttons: leftButtons, rightAligned: true)
        layoutActionButtons(in: rightActionsContainer, buttons: rightButtons, rightAligned: false)
        layoutContent()
    }

    private func layoutActionButtons(in container: NSView, buttons: [SwipeActionButton], rightAligned: Bool) {
        let size: CGFloat = 34
        let spacing: CGFloat = 10
        let y = (container.bounds.height - size) / 2
        if rightAligned {
            var x = container.bounds.width - size - spacing
            for button in buttons {
                button.frame = NSRect(x: x, y: y, width: size, height: size)
                x -= size + spacing
            }
        } else {
            var x: CGFloat = spacing
            for button in buttons {
                button.frame = NSRect(x: x, y: y, width: size, height: size)
                x += size + spacing
            }
        }
    }

    private func layoutContent() {
        contentContainer.frame = NSRect(x: contentOffset, y: 0, width: bounds.width, height: bounds.height)
        // Second button in each direction only becomes visible once swiped
        // past the step 1 threshold, so a light swipe shows just one choice.
        leftButtons.last?.alphaValue = contentOffset > step1Threshold ? 1 : 0
        rightButtons.last?.alphaValue = contentOffset < -step1Threshold ? 1 : 0
    }

    @objc private func tapped() {
        guard contentOffset == 0 else {
            // Tapping the content while a side is revealed just closes it,
            // same as Mail.app -- doesn't also open the message.
            animateOffset(to: 0)
            return
        }
        onTapOpen?()
    }

    override func scrollWheel(with event: NSEvent) {
        // Only real trackpad gestures carry a phase; a plain mouse wheel
        // doesn't do horizontal swipe-to-reveal.
        guard event.phase != [] || event.momentumPhase != [] else {
            super.scrollWheel(with: event)
            return
        }
        // Primarily-vertical gestures aren't ours to handle -- let them
        // pass through untouched.
        if !isTrackingGesture, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            isTrackingGesture = true
            gestureAccumulator = contentOffset
        case .changed:
            guard isTrackingGesture else { break }
            gestureAccumulator += event.scrollingDeltaX * directionMultiplier
            contentOffset = max(-maxReveal, min(maxReveal, gestureAccumulator))
        case .ended, .cancelled:
            guard isTrackingGesture else { break }
            isTrackingGesture = false
            finishGesture()
        default:
            break
        }
    }

    private func finishGesture() {
        if contentOffset > step2Threshold {
            animateOffset(to: 0)
            commit(Settings.rightSwipeStep2)
        } else if contentOffset > step1Threshold {
            animateOffset(to: step2Threshold)
        } else if contentOffset < -step2Threshold {
            animateOffset(to: 0)
            commit(Settings.leftSwipeStep2)
        } else if contentOffset < -step1Threshold {
            animateOffset(to: -step2Threshold)
        } else {
            animateOffset(to: 0)
        }
    }

    private func animateOffset(to target: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            contentContainer.animator().setFrameOrigin(NSPoint(x: target, y: 0))
        }
        contentOffset = target
    }

    private func commit(_ action: SwipeAction) {
        guard action != .none else { return }
        animateOffset(to: 0)
        onAction?(action)
    }
}

/// A small colored square button used for one revealed swipe action.
private final class SwipeActionButton: NSView {
    private let onTap: () -> Void

    init(action: SwipeAction, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        guard action != .none else { return }
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = action.color.cgColor

        let imageView = NSImageView(image: NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil) ?? NSImage())
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap() }
}
