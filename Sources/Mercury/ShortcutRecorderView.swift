import AppKit
import Carbon.HIToolbox

/// A small click-to-record control for a single global keyboard shortcut,
/// following the standard macOS "click, then press keys" convention. Once
/// captured, arrow-key navigation inside the resulting menu is free —
/// NSMenu already supports it natively.
final class ShortcutRecorderView: NSView {
    var onShortcutChanged: ((_ keyCode: UInt32, _ carbonModifiers: UInt32, _ displayString: String) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet { updateAppearance() }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDisplayString(_ s: String) {
        label.stringValue = s.isEmpty ? "Click to record shortcut" : s
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        label.stringValue = "Type shortcut…"
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handle(event: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event: event)
    }

    private func handle(event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }
        isRecording = false
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        let display = Self.displayString(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        label.stringValue = display
        onShortcutChanged?(UInt32(event.keyCode), carbonModifiers, display)
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlColor).cgColor
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func modifierFlags(fromCarbon carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func displayString(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
