import Foundation

/// 通用密钥存储。
///
/// `KeychainService` 原本只为 DeepSeek API Key 设计（方法名叫 `readAPIKey`），
/// 但实现本身是参数化的。这里补一个语义中立的协议，Google 的 refresh_token
/// 复用同一套 Keychain 实现，只是换一个 `account`，**绝不与 API Key 混用**。
public protocol SecretStore {
    func readSecret() throws -> String?
    func saveSecret(_ secret: String) throws
    func deleteSecret() throws
}

extension KeychainService: SecretStore {
    public func readSecret() throws -> String? { try readAPIKey() }
    public func saveSecret(_ secret: String) throws { try saveAPIKey(secret) }
    public func deleteSecret() throws { try deleteAPIKey() }
}

public enum GoogleSecretAccount {
    /// Keychain 里 Google 刷新令牌的 account 名。
    public static let refreshToken = "google-refresh-token"

    /// 与 DeepSeek API Key 共用 `service`，但 account 不同，因此是彼此独立的条目。
    public static func makeRefreshTokenStore() -> any SecretStore {
        KeychainService(accountName: refreshToken)
    }
}
