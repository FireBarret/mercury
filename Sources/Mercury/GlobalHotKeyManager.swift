import Carbon.HIToolbox
import AppKit

/// Registers a single system-wide keyboard shortcut using the classic
/// Carbon Hot Key API — still the standard permission-free way to do this
/// on macOS (unlike global NSEvent monitors, which require Input Monitoring
/// access to be granted in System Settings).
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D4E4231), id: 1)

    var onHotKeyPressed: (() -> Void)?

    func register(keyCode: UInt32, carbonModifiers: UInt32) {
        unregister()
        installHandlerIfNeeded()
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData = userData, let eventRef = eventRef else { return noErr }
            var pressedID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if pressedID.id == manager.hotKeyID.id {
                manager.onHotKeyPressed?()
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }
}
