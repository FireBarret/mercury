import Foundation

/// Small persisted preferences, independent of the account credentials.
enum Settings {
    private static let showPreviewsKey = "Mercury.showPreviews"
    private static let shortcutKeyCodeKey = "Mercury.shortcutKeyCode"
    private static let shortcutModifiersKey = "Mercury.shortcutModifiers"

    static var showPreviews: Bool {
        get {
            if UserDefaults.standard.object(forKey: showPreviewsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showPreviewsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showPreviewsKey) }
    }

    static var shortcutKeyCode: UInt32? {
        get { (UserDefaults.standard.object(forKey: shortcutKeyCodeKey) as? Int).map { UInt32($0) } }
        set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: shortcutKeyCodeKey) }
    }

    static var shortcutModifiers: UInt32? {
        get { (UserDefaults.standard.object(forKey: shortcutModifiersKey) as? Int).map { UInt32($0) } }
        set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: shortcutModifiersKey) }
    }
}
