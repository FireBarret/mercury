import AppKit

/// One of the 4 quick actions, usable as a swipe-reveal action in the
/// custom panel (in addition to the submenu in the classic menu). "None"
/// leaves that swipe slot inactive.
/// Copy Code and Check for Links are switched off for now. Flip this to
/// bring back their menu items, swipe actions and keys.
let quickExtractionEnabled = false

enum SwipeAction: String, CaseIterable {
    case none
    case flag
    case markRead
    case copyCode
    case checkLinks
    case reply
    case open

    /// Actions offered in Preferences.
    static var available: [SwipeAction] {
        allCases.filter { quickExtractionEnabled || ($0 != .copyCode && $0 != .checkLinks) }
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .flag: return "Flag"
        case .markRead: return "Mark as Read/Unread"
        case .copyCode: return "Copy Code"
        case .checkLinks: return "Check for Links"
        case .reply: return "Reply in Gmail"
        case .open: return "Open Message"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return ""
        case .flag: return "flag.fill"
        case .markRead: return "envelope.open.fill"
        case .copyCode: return "key.fill"
        case .checkLinks: return "link"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .open: return "arrow.up.right.square.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .flag: return .systemOrange
        case .markRead: return .systemBlue
        case .copyCode: return .systemPurple
        case .checkLinks: return .systemTeal
        case .reply: return .systemGreen
        case .open: return .systemIndigo
        case .none: return .clear
        }
    }
}

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

enum RecentListOrder: String, CaseIterable {
    /// Unread mail first (including old unread mail), then newest read.
    case unreadFirst
    /// Strictly the newest messages, regardless of read state.
    case chronological

    var displayName: String {
        switch self {
        case .unreadFirst: return "Unread first"
        case .chronological: return "Newest first (chronological)"
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

/// Keys that act on the highlighted message (or the menu) while the classic
/// dropdown is open. Each can be remapped in Preferences → Keyboard.
enum QuickKey: String, CaseIterable {
    case markRead, reply, flag, copyCode, checkLinks, openMailApp, openGmail, markAllRead, checkNow, openInbox

    var displayName: String {
        switch self {
        case .markRead: return "Mark as read, go down:"
        case .reply: return "Reply in Gmail:"
        case .flag: return "Flag / unflag:"
        case .copyCode: return "Copy code:"
        case .checkLinks: return "Check for links:"
        case .openMailApp: return "Open in Mail.app:"
        case .openGmail: return "Open in Gmail:"
        case .markAllRead: return "Mark all as read:"
        case .checkNow: return "Check now:"
        case .openInbox: return "Open Gmail inbox:"
        }
    }

    static var available: [QuickKey] {
        allCases.filter { quickExtractionEnabled || ($0 != .copyCode && $0 != .checkLinks) }
    }

    var defaultKey: String {
        switch self {
        case .markRead: return "e"
        case .reply: return "r"
        case .flag: return "f"
        case .copyCode: return "c"
        case .checkLinks: return "l"
        case .openMailApp: return "m"
        case .openGmail: return "g"
        case .markAllRead: return "a"
        case .checkNow: return "n"
        case .openInbox: return "i"
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
    private static let useCustomPanelKey = "Mercury.useCustomPanel"
    private static let leftSwipeStep1Key = "Mercury.leftSwipeStep1"
    private static let leftSwipeStep2Key = "Mercury.leftSwipeStep2"
    private static let rightSwipeStep1Key = "Mercury.rightSwipeStep1"
    private static let rightSwipeStep2Key = "Mercury.rightSwipeStep2"

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

    static var recentListOrder: RecentListOrder {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "Mercury.recentListOrder") else { return .unreadFirst }
            return RecentListOrder(rawValue: raw) ?? .unreadFirst
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "Mercury.recentListOrder") }
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

    /// The deferred "option 1" from the swipe-animation discussion: a
    /// custom floating panel with real trackpad swipe gestures, instead of
    /// the classic NSMenu dropdown. Off by default -- this is genuinely
    /// less battle-tested than the rest of the app.
    static var useCustomPanel: Bool {
        get { UserDefaults.standard.bool(forKey: useCustomPanelKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCustomPanelKey) }
    }

    /// Swiping a row rightward (content moves right, revealing on the left/
    /// leading edge) -- matches Mail.app's own convention of putting
    /// Unread there. Step 1 is revealed by a modest swipe; Step 2 needs a
    /// further swipe and auto-commits if released past that point.
    /// Saved or default Copy Code / Check for Links become "None" while those are off.
    private static func sanitized(_ action: SwipeAction) -> SwipeAction {
        SwipeAction.available.contains(action) ? action : .none
    }

    /// What a plain click on a message does in the swipeable panel.
    static var clickAction: SwipeAction {
        get { sanitized(SwipeAction(rawValue: UserDefaults.standard.string(forKey: "Mercury.clickAction") ?? "") ?? .open) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "Mercury.clickAction") }
    }

    static var rightSwipeStep1: SwipeAction {
        get { sanitized(SwipeAction(rawValue: UserDefaults.standard.string(forKey: rightSwipeStep1Key) ?? "") ?? .markRead) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: rightSwipeStep1Key) }
    }

    static var rightSwipeStep2: SwipeAction {
        get { sanitized(SwipeAction(rawValue: UserDefaults.standard.string(forKey: rightSwipeStep2Key) ?? "") ?? .reply) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: rightSwipeStep2Key) }
    }

    /// Swiping a row leftward (content moves left, revealing on the right/
    /// trailing edge) -- matches Mail.app's own convention of putting Flag
    /// there.
    static var leftSwipeStep1: SwipeAction {
        get { sanitized(SwipeAction(rawValue: UserDefaults.standard.string(forKey: leftSwipeStep1Key) ?? "") ?? .flag) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: leftSwipeStep1Key) }
    }

    static var leftSwipeStep2: SwipeAction {
        get { sanitized(SwipeAction(rawValue: UserDefaults.standard.string(forKey: leftSwipeStep2Key) ?? "") ?? .none) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: leftSwipeStep2Key) }
    }

    // MARK: - In-menu keys

    /// "" means unassigned.
    static func key(for action: QuickKey) -> String {
        UserDefaults.standard.string(forKey: "Mercury.key.\(action.rawValue)") ?? action.defaultKey
    }

    static func setKey(_ key: String, for action: QuickKey) {
        UserDefaults.standard.set(key, forKey: "Mercury.key.\(action.rawValue)")
    }

    static func resetKeys() {
        QuickKey.allCases.forEach { UserDefaults.standard.removeObject(forKey: "Mercury.key.\($0.rawValue)") }
    }

    static func quickKey(matching key: String) -> QuickKey? {
        QuickKey.available.first { Settings.key(for: $0) == key && !key.isEmpty }
    }

    // MARK: - Menu-bar count colors

    /// Colors of the unread numbers in the menu bar. Stored as "#RRGGBB".
    /// Defaults match the original look: blue for the primary account,
    /// orange for the secondary.
    static func countColor(for slot: AccountSlot) -> NSColor {
        color(forKey: countColorKey(for: slot)) ?? (slot == .primary ? .systemBlue : .systemOrange)
    }

    static func setCountColor(_ color: NSColor?, for slot: AccountSlot) {
        setColor(color, forKey: countColorKey(for: slot))
    }

    /// Color of the number when only one account is configured. nil keeps
    /// the plain menu-bar text color.
    static var singleAccountCountColor: NSColor? {
        get { color(forKey: "Mercury.singleCountColor") }
        set { setColor(newValue, forKey: "Mercury.singleCountColor") }
    }

    private static func countColorKey(for slot: AccountSlot) -> String {
        slot == .primary ? "Mercury.account1CountColor" : "Mercury.account2CountColor"
    }

    private static func color(forKey key: String) -> NSColor? {
        guard let hex = UserDefaults.standard.string(forKey: key), hex.hasPrefix("#"), hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func setColor(_ color: NSColor?, forKey key: String) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let hex = String(format: "#%02X%02X%02X",
                         Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()),
                         Int((rgb.blueComponent * 255).rounded()))
        UserDefaults.standard.set(hex, forKey: key)
    }
}
