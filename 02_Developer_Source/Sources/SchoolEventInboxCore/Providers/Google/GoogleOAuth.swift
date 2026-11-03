import CryptoKit
import Foundation

/// Google Calendar 所需的最小 scope 集合。
///
/// 刻意**不申请** `https://www.googleapis.com/auth/calendar`（全量）：
/// 那会允许建/删日历，而本项目采用"写入用户选定的单一日历 + 事件 colorId 分色"
/// 的模型，不需要这个权限。少一个权限，公开分发时的说服成本也低一分。
public enum GoogleOAuthScope {
    /// 查看并编辑事件。
    public static let calendarEvents = "https://www.googleapis.com/auth/calendar.events"
    /// 读取日历列表、读取事件（用于冲突检测与管理面板）。
    public static let calendarReadOnly = "https://www.googleapis.com/auth/calendar.readonly"

    public static let defaultScopes = [calendarEvents, calendarReadOnly]
}

public enum GoogleOAuthEndpoint {
    public static let authorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let token = URL(string: "https://oauth2.googleapis.com/token")!
}

/// PKCE（RFC 7636）的 S256 实现。
///
/// 纯函数，可完全单测：verifier 必须是 43–128 个 unreserved 字符，
/// challenge 是 `base64url(SHA256(ASCII(verifier)))` 且无 padding。
public enum GooglePKCE {
    public struct Pair: Equatable, Sendable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String, challenge: String) {
            self.verifier = verifier
            self.challenge = challenge
        }
    }

    /// 32 字节随机数 → base64url，得到 43 个字符的合法 verifier。
    public static func make() -> Pair {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let verifier = base64URL(Data(bytes))
        return Pair(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// state 用于防 CSRF：回调必须带回同一个值。
    public static func makeState() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return base64URL(Data(bytes))
    }
}

/// 授权码流程的授权页 URL。
public struct GoogleAuthorizationRequest: Sendable {
    public let url: URL
    public let state: String
    public let codeVerifier: String

    public init(
        client: GoogleOAuthClient,
        redirectURI: URL,
        scopes: [String] = GoogleOAuthScope.defaultScopes,
        state: String = GooglePKCE.makeState(),
        pkce: GooglePKCE.Pair = GooglePKCE.make()
    ) throws {
        guard var components = URLComponents(url: GoogleOAuthEndpoint.authorization, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.invalidAuthorizationURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // offline + consent：Google 只在**首次**同意或带 consent 时返回 refresh_token。
            // 少了这两个参数，第二次授权拿不到 refresh_token，自动刷新就无从谈起。
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]
        guard let url = components.url else {
            throw GoogleOAuthError.invalidAuthorizationURL
        }
        self.url = url
        self.state = state
        self.codeVerifier = pkce.verifier
    }
}

/// token 端点的响应。
public struct GoogleTokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let scope: String?
    public let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }

    public init(accessToken: String, refreshToken: String?, expiresIn: Int, scope: String?, tokenType: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.tokenType = tokenType
    }
}

public enum GoogleOAuthError: LocalizedError, Equatable, Sendable {
    case credentialsUnavailable(String)
    case invalidAuthorizationURL
    case listenerFailed(String)
    case callbackTimeout
    case stateMismatch
    case authorizationDenied(String)
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case missingRefreshToken
    case refreshFailed(String)
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .credentialsUnavailable(let reason):
            return "无法读取 Google 凭据：\(reason)"
        case .invalidAuthorizationURL:
            return "无法构造 Google 授权链接"
        case .listenerFailed(let reason):
            return "本地回调监听启动失败：\(reason)"
        case .callbackTimeout:
            return "等待 Google 授权回调超时，请重试"
        case .stateMismatch:
            return "Google 授权回调校验失败（state 不匹配），已拒绝"
        case .authorizationDenied(let reason):
            return "Google 授权被拒绝：\(reason)"
        case .missingAuthorizationCode:
            return "Google 授权回调里没有 code"
        case .tokenExchangeFailed(let reason):
            return "用授权码换取令牌失败：\(reason)"
        case .missingRefreshToken:
            return "Google 未返回 refresh_token，无法离线访问。请重新授权"
        case .refreshFailed(let reason):
            return "刷新 Google 访问令牌失败：\(reason)"
        case .notAuthorized:
            return "尚未连接 Google 账户"
        }
    }
}
