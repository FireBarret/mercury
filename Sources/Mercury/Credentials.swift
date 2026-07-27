import Foundation
import Security

/// Stores the Gmail address in UserDefaults and the app password in the
/// macOS Keychain (never written to disk in plain text).
enum Credentials {
    private static let service = "com.mercuryapp.Mercury"
    private static let emailDefaultsKey = "Mercury.email"

    static var email: String? {
        UserDefaults.standard.string(forKey: emailDefaultsKey)
    }

    static func save(email: String, appPassword: String) {
        UserDefaults.standard.set(email, forKey: emailDefaultsKey)
        setAppPassword(appPassword, for: email)
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
}
