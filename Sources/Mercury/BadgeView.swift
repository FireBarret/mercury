import AppKit

/// A small fixed-color rounded numeric badge, meant to be layered as a
/// subview on top of a status item's button (in a corner) rather than
/// baked into the icon's own bitmap -- keeping the icon itself a genuine
/// template image so AppKit handles light/dark menu bar tinting natively,
/// instead of us trying to (unreliably) replicate that ourselves.
final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 5.5

        label.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCount(_ count: Int) {
        label.stringValue = count > 99 ? "99+" : "\(count)"
    }
}
