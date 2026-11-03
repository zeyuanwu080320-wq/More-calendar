import Foundation
import Security

public enum APIKeyPresence: Equatable, Sendable {
    case missing
    case present
    case inaccessible
}

public protocol APIKeyStore {
    func apiKeyPresence() -> APIKeyPresence
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

public enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if status == 100001 {
                return "Keychain 访问被系统拒绝；如屏幕已锁定，请解锁后重试"
            }
            return "Keychain 操作失败（\(status)）"
        case .invalidData:
            return "Keychain 数据无法读取"
        }
    }
}

public final class KeychainService: APIKeyStore {
    public static let service = "local.duishangque.SchoolEventInbox"
    public static let account = "deepseek-api-key"

    private let serviceName: String
    private let accountName: String

    public init(serviceName: String = KeychainService.service, accountName: String = KeychainService.account) {
        self.serviceName = serviceName
        self.accountName = accountName
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
    }

    public func apiKeyPresence() -> APIKeyPresence {
        // Explicit metadata query. This can still trigger a macOS Keychain
        // unlock/ACL dialog, so never call it automatically at launch.
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, OSStatus(100001):
            return .inaccessible
        default:
            return .inaccessible
        }
    }

    public func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainError.invalidData
        }
        return key
    }

    public func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // Delete then add so a rebuilt local app resets the item ACL for its
        // current code signature. Updating data alone would keep the old ACL.
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(deleteStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
