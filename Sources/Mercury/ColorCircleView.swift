import AppKit

/// A round color swatch. Clicking it opens the shared system color panel and
/// reports changes through its target/action, like NSColorWell -- but filled
/// edge to edge as a circle, which NSColorWell's minimal style can't do.
final class ColorCircleView: NSControl {
    var color: NSColor = .black {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    init(accessibilityName: String) {
        super.init(frame: .zero)
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel(accessibilityName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func drawFocusRingMask() {
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func keyDown(with event: NSEvent) {
        if event.characters == " " || event.characters == "\r" {
            openPanel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        openPanel()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        color.setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        openPanel()
    }

    private func openPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(panelColorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func panelColorChanged(_ sender: NSColorPanel) {
        color = sender.color
        sendAction(action, to: target)
    }
}
