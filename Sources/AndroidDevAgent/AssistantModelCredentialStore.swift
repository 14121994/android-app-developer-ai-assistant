import Foundation
import Security

enum AssistantModelCredentialStore {
    private static let service = "AndroidDevAgent.AssistantModels"
    private static let openAIAccount = "OpenAIAPIKey"

    static func openAIAPIKey() -> String? {
        var query = baseQuery(account: openAIAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func saveOpenAIAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearOpenAIAPIKey()
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(account: openAIAccount)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.keychainStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.keychainStatus(addStatus)
        }
    }

    static func clearOpenAIAPIKey() {
        SecItemDelete(baseQuery(account: openAIAccount) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum CredentialError: LocalizedError {
        case keychainStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .keychainStatus(status):
                return "Keychain operation failed with status \(status)."
            }
        }
    }
}
