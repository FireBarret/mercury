import Foundation

enum MailOpenAction: String, CaseIterable {
    case mailApp
    case gmailBrowser

    var displayName: String {
        switch self {
        case .mailApp: return "Mail.app"
        case .gmailBrowser: return "Gmail (Browser)"
        }
    }
}

/// Small persisted preferences, independent of the account credentials.
enum Settings {
    private static let showPreviewsKey = "Mercury.showPreviews"
    private static let shortcutKeyCodeKey = "Mercury.shortcutKeyCode"
    private static let shortcutModifiersKey = "Mercury.shortcutModifiers"
    private static let recentListMinCountKey = "Mercury.recentListMinCount"
    private static let recentListMaxCountKey = "Mercury.recentListMaxCount"
    private static let autoRefreshMailAppKey = "Mercury.autoRefreshMailApp"
    private static let openMailActionKey = "Mercury.openMailAction"
    private static let playNotificationSoundKey = "Mercury.playNotificationSound"
    private static let showRecentMessagesInMenuKey = "Mercury.showRecentMessagesInMenu"

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

    /// Always shown, regardless of unread count.
    static var recentListMinCount: Int {
        get {
            let value = UserDefaults.standard.object(forKey: recentListMinCountKey) as? Int
            return value ?? 3
        }
        set { UserDefaults.standard.set(newValue, forKey: recentListMinCountKey) }
    }

    /// Ceiling the recent list grows to when there's more unread mail than
    /// the minimum.
    static var recentListMaxCount: Int {
        get {
            let value = UserDefaults.standard.object(forKey: recentListMaxCountKey) as? Int
            return value ?? 10
        }
        set { UserDefaults.standard.set(newValue, forKey: recentListMaxCountKey) }
    }

    static var autoRefreshMailApp: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoRefreshMailAppKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoRefreshMailAppKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoRefreshMailAppKey) }
    }

    static var openMailAction: MailOpenAction {
        get {
            guard let raw = UserDefaults.standard.string(forKey: openMailActionKey) else { return .mailApp }
            return MailOpenAction(rawValue: raw) ?? .mailApp
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: openMailActionKey) }
    }

    static var playNotificationSound: Bool {
        get {
            if UserDefaults.standard.object(forKey: playNotificationSoundKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: playNotificationSoundKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: playNotificationSoundKey) }
    }

    static var showRecentMessagesInMenu: Bool {
        get {
            if UserDefaults.standard.object(forKey: showRecentMessagesInMenuKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showRecentMessagesInMenuKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showRecentMessagesInMenuKey) }
    }
}
