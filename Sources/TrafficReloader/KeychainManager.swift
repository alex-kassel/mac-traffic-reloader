import Foundation
import Security
import LocalAuthentication

final class KeychainManager {
    static let shared = KeychainManager()

    private let defaultService = "com.fcc.TrafficReloader"

    private init() {}

    // MARK: - Biometrics / Touch ID Authentication

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithTouchID(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Logger.log("[KeychainManager] Biometric/Passcode policy unavailable: %@", error?.localizedDescription ?? "N/A")
            return false
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success
        } catch {
            Logger.log("[KeychainManager] Touch ID authentication failed or cancelled: %@", error.localizedDescription)
            return false
        }
    }

    // MARK: - Keychain CRUD

    @discardableResult
    func savePassword(service: String, account: String, password: String) -> Bool {
        guard let data = password.data(using: .utf8), !account.isEmpty else { return false }

        // Remove old item if exists
        deletePassword(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.isEmpty ? defaultService : service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            Logger.log("[KeychainManager] Successfully saved password in Keychain for: %@", account)
            return true
        } else {
            Logger.log("[KeychainManager] Failed to save password in Keychain (status: %d)", status)
            return false
        }
    }

    func getPassword(service: String, account: String) -> String? {
        guard !account.isEmpty else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.isEmpty ? defaultService : service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deletePassword(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.isEmpty ? defaultService : service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func findStoredAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.isEmpty ? defaultService : service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let items = item as? [[String: Any]] else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
