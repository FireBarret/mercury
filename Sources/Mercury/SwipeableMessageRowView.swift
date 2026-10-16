import AppKit

/// A single message row with real two-finger trackpad swipe-to-reveal,
/// used only inside the custom panel (Settings.useCustomPanel) -- this is
/// a plain NSView in a real window, not hosted inside an NSMenu, so normal
/// AppKit event handling applies with none of the uncertainty custom
/// NSMenuItem views carry.
///
/// Swiping right reveals actions on the left/leading edge, matching
/// Mail.app's convention of putting Unread there; swiping left reveals the
/// right/trailing edge, matching its Flag placement. Within each side the
/// step 1 action sits adjacent to the message content and step 2 sits
/// outermost, so dragging well past the open position commits the
/// outermost action -- the leftmost/rightmost one.
final class SwipeableMessageRowView: NSView {
    private let message: MailHeader
    private let contentContainer = NSView()
    private let contentLabel = NSTextField(labelWithString: "")
    private let leftActionsContainer = NSView()
    private let rightActionsContainer = NSView()
    private var leftButtons: [SwipeActionButton] = []
    private var rightButtons: [SwipeActionButton] = []

    private var contentOffset: CGFloat = 0
    private var gestureAccumulator: CGFloat = 0
    private var isTrackingGesture = false
    private var pastCommitPoint = false
    private var animationTimer: Timer?
    private var springTarget: CGFloat = 0
    private var springVelocity: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private let leftRevealMask = CALayer()
    private let rightRevealMask = CALayer()
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    /// Width allotted to one action button, including its share of padding.
    private let slotWidth: CGFloat = 76
    /// Extra drag past the fully-open position required to auto-commit the
    /// outermost action, plus how far the row can be dragged at all.
    private let commitOvershoot: CGFloat = 62
    private let dragOvershoot: CGFloat = 95
    private let revealThreshold: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    // Flip this to -1 if real-world testing shows the swipe direction feels
    // backwards -- sign conventions for trackpad scrollingDeltaX can vary
    // and this isn't something testable without a physical trackpad.
    private let directionMultiplier: CGFloat = 1

    /// Fully-open position per direction -- only as wide as the actions
    /// actually configured, so a direction set to None/one action doesn't
    /// leave dead space to drag into.
    private var leftOpenWidth: CGFloat { CGFloat(leftButtons.count) * slotWidth }
    private var rightOpenWidth: CGFloat { CGFloat(rightButtons.count) * slotWidth }

    var onTapOpen: (() -> Void)?
    var onAction: ((SwipeAction) -> Void)?

    init(message: MailHeader, attributedText: NSAttributedString) {
        self.message = message
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        wantsLayer = true
        buildUI(attributedText: attributedText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { animationTimer?.invalidate() }

    private func buildUI(attributedText: NSAttributedString) {
        addSubview(leftActionsContainer)
        addSubview(rightActionsContainer)
        addSubview(contentContainer)

        leftActionsContainer.wantsLayer = true
        rightActionsContainer.wantsLayer = true
        // Each layer rounds and clips itself. Also masking on the parent
        // row stacked two anti-aliased edges on top of each other, leaving
        // a light fringe in the corners.
        for container in [leftActionsContainer, rightActionsContainer] {
            container.layer?.cornerRadius = cornerRadius
            container.layer?.masksToBounds = true
        }
        rightActionsContainer.isHidden = true
        leftActionsContainer.isHidden = true
        leftRevealMask.backgroundColor = NSColor.black.cgColor
        rightRevealMask.backgroundColor = NSColor.black.cgColor
        leftActionsContainer.layer?.mask = leftRevealMask
        rightActionsContainer.layer?.mask = rightRevealMask
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = restingBackgroundColor.cgColor
        // The content block keeps its own rounded corners so it still reads
        // as a rounded row once it slides away from the row's own bounds --
        // relying on the parent's mask alone left a hard square edge
        // exposed mid-swipe.
        contentContainer.layer?.cornerRadius = cornerRadius
        contentContainer.layer?.masksToBounds = true

        // .none slots are dropped rather than laid out as invisible gaps, so
        // the reveal width always matches what's actually actionable.
        leftButtons = [Settings.rightSwipeStep1, Settings.rightSwipeStep2]
            .filter { $0 != .none }
            .map { action in
                SwipeActionButton(action: action, symbolName: symbolName(for: action)) { [weak self] in
                    self?.commit(action)
                }
            }
        rightButtons = [Settings.leftSwipeStep1, Settings.leftSwipeStep2]
            .filter { $0 != .none }
            .map { action in
                SwipeActionButton(action: action, symbolName: symbolName(for: action)) { [weak self] in
                    self?.commit(action)
                }
            }
        leftButtons.forEach { leftActionsContainer.addSubview($0) }
        rightButtons.forEach { rightActionsContainer.addSubview($0) }

        contentLabel.attributedStringValue = attributedText
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.maximumNumberOfLines = 2
        // Multi-line NSTextField needs its wrap width known *before* Auto
        // Layout can compute a correct intrinsic height -- without this, a
        // label whose exact width is only found out after layout resolves
        // sizes itself as if unconstrained and overflows the row.
        contentLabel.preferredMaxLayoutWidth = 316
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentLabel)
        NSLayoutConstraint.activate([
            contentLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -12),
            contentLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        contentContainer.addGestureRecognizer(clickGesture)
    }

    /// Mark-as-read and mark-as-unread are the same configurable slot but
    /// need to read as different actions, so the glyph follows the
    /// message's current state -- open envelope to mark read, sealed
    /// envelope to mark unread (same pairing the classic menu uses).
    private func symbolName(for action: SwipeAction) -> String {
        guard action == .markRead else { return action.symbolName }
        return message.isUnread ? "envelope.open.fill" : "envelope.fill"
    }

    // Over Liquid Glass the rows must stay translucent so the glass shows
    // through; an opaque fill would just paint a flat tile over it.
    private let usesGlass = Settings.useGlassEffect
    private var restingBackgroundColor: NSColor {
        usesGlass ? NSColor.labelColor.withAlphaComponent(0.07) : .windowBackgroundColor
    }
    private var hoveredBackgroundColor: NSColor {
        usesGlass ? NSColor.labelColor.withAlphaComponent(0.14) : .unemphasizedSelectedContentBackgroundColor
    }

    // MARK: - Hover

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

    private func applyHoverAppearance() {
        let color = isHovered ? hoveredBackgroundColor : restingBackgroundColor
        contentContainer.layer?.backgroundColor = color.cgColor
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Layer-backed colors are resolved CGColors, so they don't follow a
    /// light/dark appearance switch on their own the way NSColor-drawn
    /// content does.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyHoverAppearance()
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        leftActionsContainer.frame = NSRect(x: 0, y: 0, width: leftOpenWidth, height: bounds.height)
        rightActionsContainer.frame = NSRect(
            x: bounds.width - rightOpenWidth,
            y: 0,
            width: rightOpenWidth,
            height: bounds.height
        )
        // Step 1 sits adjacent to the message content, step 2 outermost --
        // hence the left side lays out from its right edge inward.
        layoutActionButtons(in: leftActionsContainer, buttons: leftButtons, fromInnerEdge: .right)
        layoutActionButtons(in: rightActionsContainer, buttons: rightButtons, fromInnerEdge: .left)
        contentContainer.frame = NSRect(x: contentOffset, y: 0, width: bounds.width, height: bounds.height)
        updateRevealMasks()
    }

    private enum InnerEdge { case left, right }

    private func layoutActionButtons(in container: NSView, buttons: [SwipeActionButton], fromInnerEdge edge: InnerEdge) {
        guard !buttons.isEmpty else { return }
        let verticalInset: CGFloat = 3
        let horizontalInset: CGFloat = 5
        let height = max(container.bounds.height - verticalInset * 2, 20)
        let width = slotWidth - horizontalInset * 2
        let y = verticalInset

        for (index, button) in buttons.enumerated() {
            let slotX: CGFloat
            switch edge {
            case .right:
                slotX = container.bounds.width - CGFloat(index + 1) * slotWidth
            case .left:
                slotX = CGFloat(index) * slotWidth
            }
            button.frame = NSRect(x: slotX + horizontalInset, y: y, width: width, height: height)
        }
    }

    /// Moves the content to `value`. Animated moves run a small critically
    /// damped spring driven by a timer: the content frame, the side
    /// visibility and the reveal masks all update together every tick,
    /// so nothing depends on Core Animation picking up a layer change.
    private func setOffset(_ value: CGFloat, animated: Bool) {
        animationTimer?.invalidate()
        animationTimer = nil
        guard animated, abs(value - contentOffset) > 0.5 else {
            applyOffset(value)
            return
        }
        springTarget = value
        springVelocity = 0
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 1.0 / 30.0))
        lastTick = now
        // Critically damped: no bounce, settles in roughly 0.6s.
        let stiffness: CGFloat = 110
        let damping: CGFloat = 21
        let acceleration = -stiffness * (contentOffset - springTarget) - damping * springVelocity
        springVelocity += acceleration * dt
        let next = contentOffset + springVelocity * dt
        if abs(next - springTarget) < 0.4, abs(springVelocity) < 4 {
            animationTimer?.invalidate()
            animationTimer = nil
            applyOffset(springTarget)
        } else {
            applyOffset(next)
        }
    }

    /// Only the side being revealed is shown, and masked to exactly the
    /// uncovered strip -- over Liquid Glass the row is translucent, so
    /// anything underneath it would otherwise show through.
    private func applyOffset(_ value: CGFloat) {
        contentOffset = value
        contentContainer.setFrameOrigin(NSPoint(x: value, y: 0))
        leftActionsContainer.isHidden = value <= 0
        rightActionsContainer.isHidden = value >= 0
        updateRevealMasks()
    }

    private func updateRevealMasks() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftRevealMask.frame = CGRect(
            x: 0, y: 0,
            width: max(0, contentOffset), height: leftActionsContainer.bounds.height
        )
        let revealed = max(0, -contentOffset)
        rightRevealMask.frame = CGRect(
            x: rightActionsContainer.bounds.width - revealed, y: 0,
            width: revealed, height: rightActionsContainer.bounds.height
        )
        CATransaction.commit()
    }

    /// Follows the finger 1:1 up to the fully-open position, then applies
    /// diminishing returns so pulling further feels like stretching rather
    /// than sliding the row off-screen.
    private func rubberBanded(_ raw: CGFloat) -> CGFloat {
        let open = raw >= 0 ? leftOpenWidth : rightOpenWidth
        let hasButtons = raw >= 0 ? !leftButtons.isEmpty : !rightButtons.isEmpty
        guard hasButtons else { return 0 }
        let magnitude = abs(raw)
        guard magnitude > open else { return raw }
        let excess = magnitude - open
        let stretched = open + dragOvershoot * (1 - exp(-excess / dragOvershoot))
        return raw >= 0 ? stretched : -stretched
    }

    @objc private func tapped() {
        guard contentOffset == 0 else {
            // Tapping the content while a side is revealed just closes it,
            // same as Mail.app -- doesn't also open the message.
            setOffset(0, animated: true)
            return
        }
        onTapOpen?()
    }

    // MARK: - Swipe

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
            animationTimer?.invalidate()
            animationTimer = nil
            gestureAccumulator = contentOffset
            pastCommitPoint = false
        case .changed:
            guard isTrackingGesture else { break }
            gestureAccumulator += event.scrollingDeltaX * directionMultiplier
            setOffset(rubberBanded(gestureAccumulator), animated: false)
            let beyond = gestureAccumulator > leftOpenWidth + commitOvershoot && !leftButtons.isEmpty
                || gestureAccumulator < -(rightOpenWidth + commitOvershoot) && !rightButtons.isEmpty
            if beyond != pastCommitPoint {
                pastCommitPoint = beyond
                // A light tick when the far-swipe action becomes armed
                // (and again when it disarms), like iOS's swipe actions.
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        case .ended, .cancelled:
            guard isTrackingGesture else { break }
            isTrackingGesture = false
            finishGesture()
        default:
            break
        }
    }

    private func finishGesture() {
        let raw = gestureAccumulator
        let outermostLeft = leftButtons.last?.action
        let outermostRight = rightButtons.last?.action

        if !leftButtons.isEmpty, raw > leftOpenWidth + commitOvershoot {
            setOffset(0, animated: true)
            if let action = outermostLeft { onAction?(action) }
        } else if !leftButtons.isEmpty, raw > revealThreshold {
            setOffset(leftOpenWidth, animated: true)
        } else if !rightButtons.isEmpty, raw < -(rightOpenWidth + commitOvershoot) {
            setOffset(0, animated: true)
            if let action = outermostRight { onAction?(action) }
        } else if !rightButtons.isEmpty, raw < -revealThreshold {
            setOffset(-rightOpenWidth, animated: true)
        } else {
            setOffset(0, animated: true)
        }
    }

    private func commit(_ action: SwipeAction) {
        guard action != .none else { return }
        setOffset(0, animated: true)
        onAction?(action)
    }
}

/// A colored action button revealed by swiping, sized to nearly fill the
/// row's height and highlighting as the cursor passes over it.
private final class SwipeActionButton: NSView {
    let action: SwipeAction
    private let onTap: () -> Void
    private let baseColor: NSColor
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(action: SwipeAction, symbolName: String, onTap: @escaping () -> Void) {
        self.action = action
        self.onTap = onTap
        self.baseColor = action.color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        applyHoverAppearance()

        let imageView = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: action.displayName) ?? NSImage())
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 19),
            imageView.heightAnchor.constraint(equalToConstant: 19)
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let color = isHovered ? (baseColor.highlight(withLevel: 0.25) ?? baseColor) : baseColor
        layer?.backgroundColor = color.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyHoverAppearance()
        }
    }

    @objc private func tapped() { onTap() }
}
