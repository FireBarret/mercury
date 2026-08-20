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

enum MailAppRefreshMode: String, CaseIterable {
    /// Launch it if needed, tell it to check for new mail, then quit it
    /// again -- but only if it wasn't already running.
    case quitAfterRefresh
    /// Launch it if needed, tell it to check for new mail, then hide it
    /// (like Cmd+H) instead of quitting -- only the first time; after that
    /// it just stays running hidden, so later refreshes skip the relaunch.
    case hideAfterRefresh
    /// Never launches Mail.app. If it's already open (however the user
    /// left it), just tells it to check for new mail.
    case refreshIfAlreadyOpen
    /// Don't touch Mail.app at all.
    case disabled

    var displayName: String {
        switch self {
        case .quitAfterRefresh: return "Open, refresh, then close"
        case .hideAfterRefresh: return "Open, refresh, then hide"
        case .refreshIfAlreadyOpen: return "Refresh only if already open"
        case .disabled: return "Do nothing"
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
    private static let mailAppRefreshModeKey = "Mercury.mailAppRefreshMode"
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

    /// Replaces the old on/off `autoRefreshMailApp` toggle with 4 modes.
    /// Migrates a previously-set boolean once: on -> .hideAfterRefresh (the
    /// new nicer default, not the old quit behavior), off -> .disabled.
    static var mailAppRefreshMode: MailAppRefreshMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: mailAppRefreshModeKey),
               let mode = MailAppRefreshMode(rawValue: raw) {
                return mode
            }
            if UserDefaults.standard.object(forKey: autoRefreshMailAppKey) != nil {
                let wasEnabled = UserDefaults.standard.bool(forKey: autoRefreshMailAppKey)
                let migrated: MailAppRefreshMode = wasEnabled ? .hideAfterRefresh : .disabled
                UserDefaults.standard.set(migrated.rawValue, forKey: mailAppRefreshModeKey)
                UserDefaults.standard.removeObject(forKey: autoRefreshMailAppKey)
                return migrated
            }
            return .hideAfterRefresh
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: mailAppRefreshModeKey) }
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
