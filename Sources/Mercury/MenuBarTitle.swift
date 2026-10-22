import AppKit

/// The unread numbers shown beside the envelope in the menu bar. Shared by
/// the status item and the live preview in Preferences so the two can't
/// drift apart.
enum MenuBarTitle {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// One account: plain menu-bar text unless the user picked a color.
    static func single(count: Int) -> NSAttributedString {
        guard count > 0 else { return NSAttributedString(string: "") }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color = Settings.singleAccountCountColor {
            attributes[.foregroundColor] = color
        }
        return NSAttributedString(string: " \(count)", attributes: attributes)
    }

    /// Two accounts. Omits either number when its account has nothing
    /// unread, so a lone number keeps that account's color.
    static func dual(primary: Int, secondary: Int) -> NSAttributedString {
        guard primary > 0 || secondary > 0 else { return NSAttributedString(string: "") }

        let result = NSMutableAttributedString(string: " ")
        if primary > 0 {
            result.append(NSAttributedString(
                string: "\(primary)",
                attributes: [.font: font, .foregroundColor: Settings.countColor(for: .primary)]
            ))
        }
        if primary > 0 && secondary > 0 {
            result.append(NSAttributedString(
                string: " · ",
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }
        if secondary > 0 {
            result.append(NSAttributedString(
                string: "\(secondary)",
                attributes: [.font: font, .foregroundColor: Settings.countColor(for: .secondary)]
            ))
        }
        return result
    }
}
