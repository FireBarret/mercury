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
    /// Pre-multi-account key; migrated into account1EmailKey on first read.
    private static let legacyEmailKey = "Mercury.email"

    private static func emailKey(for slot: AccountSlot) -> String {
        slot == .primary ? account1EmailKey : account2EmailKey
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
