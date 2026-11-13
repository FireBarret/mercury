import AppKit

/// Click-to-record control for a single unmodified key (used for the
/// in-menu keys). Escape cancels, Delete clears the assignment.
final class KeyRecorderView: NSView {
    var onKeyChanged: ((String) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var key = ""
    private var isRecording = false { didSet { updateAppearance() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        widthAnchor.constraint(equalToConstant: 110).isActive = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setKey(_ newKey: String) {
        key = newKey
        isRecording = false
        showKey()
    }

    private func showKey() {
        label.stringValue = key.isEmpty ? "None" : key.uppercased()
        label.textColor = key.isEmpty ? .secondaryLabelColor : .labelColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false; showKey() }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        label.stringValue = "Press a key…"
        label.textColor = .controlAccentColor
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { isRecording = false; showKey(); return }          // Escape
        if event.keyCode == 51 || event.keyCode == 117 {                            // Delete
            key = ""; isRecording = false; showKey(); onKeyChanged?(""); return
        }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1,
              let scalar = chars.unicodeScalars.first, scalar.value >= 0x21, scalar.value < 0xF700 else {
            NSSound.beep()
            return
        }
        key = chars
        isRecording = false
        showKey()
        onKeyChanged?(chars)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }
}
