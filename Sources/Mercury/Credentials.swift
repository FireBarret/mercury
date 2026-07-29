import Foundation
import Security

enum AccountSlot: CaseIterable, Hashable {
    case primary
    case secondary
}

/// Stores Gmail addresses (up to 2, one per AccountSlot) in UserDefaults and
/// their app passwords in the macOS Keychain (never written to disk in
/// plain text).
enum Credentials {
    private static let service = "com.mercuryapp.Mercury"
    private static let account1EmailKey = "Mercury.account1Email"
    private static let account2EmailKey = "Mercury.account2Email"
    private static let account1NameKey = "Mercury.account1Name"
    private static let account2NameKey = "Mercury.account2Name"
    private static let account1NotifyKey = "Mercury.account1NotificationsEnabled"
    private static let account2NotifyKey = "Mercury.account2NotificationsEnabled"
    /// Pre-multi-account key; migrated into account1EmailKey on first read.
    private static let legacyEmailKey = "Mercury.email"

    private static func emailKey(for slot: AccountSlot) -> String {
        slot == .primary ? account1EmailKey : account2EmailKey
    }

    private static func nameKey(for slot: AccountSlot) -> String {
        slot == .primary ? account1NameKey : account2NameKey
    }

    private static func notifyKey(for slot: AccountSlot) -> String {
        slot == .primary ? account1NotifyKey : account2NotifyKey
    }

    /// Whether new mail for this account should trigger a banner
    /// notification. Independent of the account's unread badge/recent-list
    /// visibility, which are unaffected by this -- it only silences the
    /// popup.
    static func notificationsEnabled(for slot: AccountSlot) -> Bool {
        if UserDefaults.standard.object(forKey: notifyKey(for: slot)) == nil { return true }
        return UserDefaults.standard.bool(forKey: notifyKey(for: slot))
    }

    static func setNotificationsEnabled(_ enabled: Bool, for slot: AccountSlot) {
        UserDefaults.standard.set(enabled, forKey: notifyKey(for: slot))
    }

    static func defaultDisplayName(for slot: AccountSlot) -> String {
        slot == .primary ? "Mail 1" : "Mail 2"
    }

    /// The user-chosen name for this slot, or nil if it hasn't been set
    /// (i.e. it's still using the "Mail 1"/"Mail 2" default). Used to
    /// pre-fill the Preferences field without showing the default as if
    /// it were something the user actually typed.
    static func customDisplayName(for slot: AccountSlot) -> String? {
        UserDefaults.standard.string(forKey: nameKey(for: slot))
    }

    /// The name to actually show in the UI -- the custom one if set,
    /// otherwise "Mail 1"/"Mail 2".
    static func displayName(for slot: AccountSlot) -> String {
        customDisplayName(for: slot) ?? defaultDisplayName(for: slot)
    }

    static func setDisplayName(_ name: String?, for slot: AccountSlot) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        if let trimmed = trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: nameKey(for: slot))
        } else {
            UserDefaults.standard.removeObject(forKey: nameKey(for: slot))
        }
    }

    static func email(for slot: AccountSlot) -> String? {
        if let value = UserDefaults.standard.string(forKey: emailKey(for: slot)) {
            return value
        }
        if slot == .primary, let legacy = UserDefaults.standard.string(forKey: legacyEmailKey) {
            UserDefaults.standard.set(legacy, forKey: account1EmailKey)
            UserDefaults.standard.removeObject(forKey: legacyEmailKey)
            return legacy
        }
        return nil
    }

    static func save(email: String, appPassword: String, slot: AccountSlot) {
        UserDefaults.standard.set(email, forKey: emailKey(for: slot))
        setAppPassword(appPassword, for: email)
    }

    /// Removes the account in this slot entirely (UserDefaults entry and
    /// its Keychain password).
    static func clear(slot: AccountSlot) {
        if let existingEmail = email(for: slot) {
            deleteAppPassword(for: existingEmail)
        }
        UserDefaults.standard.removeObject(forKey: emailKey(for: slot))
        UserDefaults.standard.removeObject(forKey: nameKey(for: slot))
        UserDefaults.standard.removeObject(forKey: notifyKey(for: slot))
    }

    static func appPassword(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func setAppPassword(_ password: String, for email: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var newItem = baseQuery
        newItem[kSecValueData as String] = Data(password.utf8)
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newItem as CFDictionary, nil)
    }

    private static func deleteAppPassword(for email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        SecItemDelete(query as CFDictionary)
    }
}
