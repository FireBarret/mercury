import AppKit

/// Draws a menu bar icon with two small numeric badges -- one in the
/// upper-right corner (primary account's unread count) and one in the
/// lower-right corner (secondary account's) -- used when two accounts are
/// configured, since a single combined count wouldn't say which inbox
/// actually has mail waiting.
enum MenuBarIconRenderer {
    static func dualAccountIcon(primaryUnread: Int, secondaryUnread: Int) -> NSImage {
        let size = NSSize(width: 30, height: 18)
        let hasAnyUnread = primaryUnread > 0 || secondaryUnread > 0
        let envelopeSymbolName = hasAnyUnread ? "envelope.fill" : "envelope"

        let image = NSImage(size: size, flipped: false) { rect in
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let envelope = NSImage(systemSymbolName: envelopeSymbolName, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                    if let configured = envelope.withSymbolConfiguration(config) {
                        let envelopeSize = configured.size
                        let envelopeRect = NSRect(
                            x: 0,
                            y: (rect.height - envelopeSize.height) / 2,
                            width: envelopeSize.width,
                            height: envelopeSize.height
                        )
                        configured.draw(in: envelopeRect)
                        // The symbol draws as an opaque black silhouette by default;
                        // recolor it to the current appearance's label color by
                        // filling the same rect with sourceAtop, which only affects
                        // pixels where the glyph already has alpha.
                        NSColor.labelColor.setFill()
                        envelopeRect.fill(using: .sourceAtop)
                    }
                }

                if primaryUnread > 0 {
                    drawBadge(
                        count: primaryUnread,
                        center: NSPoint(x: rect.width - 5.5, y: rect.height - 5.5),
                        color: .systemBlue
                    )
                }
                if secondaryUnread > 0 {
                    drawBadge(
                        count: secondaryUnread,
                        center: NSPoint(x: rect.width - 5.5, y: 5.5),
                        color: .systemOrange
                    )
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawBadge(count: Int, center: NSPoint, color: NSColor) {
        let diameter: CGFloat = 11
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)

        color.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let text = count > 99 ? "99+" : "\(count)"
        let font = NSFont.systemFont(ofSize: text.count > 2 ? 6 : 7, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        text.draw(at: textOrigin, withAttributes: attrs)
    }
}
