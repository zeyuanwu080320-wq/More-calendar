import AppKit
import Foundation

/// Google OAuth 2.0 授权码流程（PKCE + loopback）的编排者。
///
/// 它同时是 `GoogleTokenProvider`：`GoogleAPIClient` 只问它要令牌，401 时叫它强刷。
/// `refresh_token` 只存在于 Keychain（account = `google-refresh-token`），
/// `access_token` 只在内存里缓存到过期前 60 秒。
public actor GoogleOAuthManager: GoogleTokenProvider {
    private let client: GoogleOAuthClient
    private let tokenStore: any SecretStore
    private let transport: any GoogleHTTPTransport
    private let openURL: @Sendable (URL) -> Void
    private let makeServer: @Sendable () -> GoogleOAuthLoopbackServer

    private var cachedAccessToken: String?
    private var cachedExpiry: Date?

    /// 默认用系统默认浏览器打开授权页。不用 `ASWebAuthenticationSession`：
    /// 它只能拦截自定义 scheme（或 https universal link），拦不到 `http://localhost`，
    /// 而 Google 桌面端只支持 loopback。
    public static let openInSystemBrowser: @Sendable (URL) -> Void = { url in
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
    }

    public init(
        client: GoogleOAuthClient,
        tokenStore: any SecretStore = GoogleSecretAccount.makeRefreshTokenStore(),
        transport: any GoogleHTTPTransport = URLSessionTransport(),
        openURL: @escaping @Sendable (URL) -> Void = GoogleOAuthManager.openInSystemBrowser,
        makeServer: @escaping @Sendable () -> GoogleOAuthLoopbackServer = { GoogleOAuthLoopbackServer() }
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.transport = transport
        self.openURL = openURL
        self.makeServer = makeServer
    }

    /// 用凭据文件的默认位置构造。
    public init(
        transport: any GoogleHTTPTransport = URLSessionTransport(),
        openURL: @escaping @Sendable (URL) -> Void = GoogleOAuthManager.openInSystemBrowser
    ) throws {
        let client: GoogleOAuthClient
        do {
            client = try GoogleOAuthClientLoader.load()
        } catch let error as GoogleOAuthClientError {
            throw GoogleOAuthError.credentialsUnavailable(error.localizedDescription)
        }
        self.init(client: client, transport: transport, openURL: openURL)
    }

    // MARK: - 状态

    /// 是否已经存有 refresh_token（不等于当前可用，可能已被用户撤销）。
    public func hasStoredRefreshToken() -> Bool {
        guard let stored = try? tokenStore.readSecret(), !stored.isEmpty else { return false }
        return true
    }

    /// 丢掉内存缓存与 Keychain 里的 refresh_token。
    public func signOut() {
        cachedAccessToken = nil
        cachedExpiry = nil
        try? tokenStore.deleteSecret()
    }

    // MARK: - GoogleTokenProvider

    public func validAccessToken() async throws -> String {
        if let token = cachedAccessToken,
           let expiry = cachedExpiry,
           expiry > Date() {
            return token
        }
        return try await refreshAccessToken()
    }

    public func forceRefreshAccessToken() async throws -> String {
        cachedAccessToken = nil
        cachedExpiry = nil
        return try await refreshAccessToken()
    }

    // MARK: - 授权

    /// 走完整个授权流程并返回 access_token。
    ///
    /// 调用方的线程会被挂起直到浏览器回调、超时或失败。
    @discardableResult
    public func authorize(timeout: TimeInterval = 180) async throws -> String {
        let server = makeServer()
        let port = try await server.start()
        let redirectURI = URL(string: "http://localhost:\(port)/callback")!
        defer { Task { await server.stop() } }

        let request = try GoogleAuthorizationRequest(client: client, redirectURI: redirectURI)
        openURL(request.url)

        let callback = try await server.waitForCallback(timeout: timeout)

        if let error = callback.error {
            throw GoogleOAuthError.authorizationDenied(callback.errorDescription ?? error)
        }
        guard callback.state == request.state else {
            throw GoogleOAuthError.stateMismatch
        }
        guard let code = callback.code, !code.isEmpty else {
            throw GoogleOAuthError.missingAuthorizationCode
        }

        let token = try await exchangeAuthorizationCode(
            code,
            verifier: request.codeVerifier,
            redirectURI: redirectURI
        )
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw GoogleOAuthError.missingRefreshToken
        }
        do {
            try tokenStore.saveSecret(refreshToken)
        } catch {
            throw GoogleOAuthError.tokenExchangeFailed("无法把 refresh_token 写入 Keychain")
        }
        cache(token)
        return token.accessToken
    }

    // MARK: - 令牌交换

    private func exchangeAuthorizationCode(
        _ code: String,
        verifier: String,
        redirectURI: URL
    ) async throws -> GoogleTokenResponse {
        let fields = [
            "code": code,
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        do {
            return try await postForm(fields)
        } catch let error as GoogleOAuthError {
            throw error
        } catch {
            throw GoogleOAuthError.tokenExchangeFailed(error.localizedDescription)
        }
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = try? tokenStore.readSecret(), !refreshToken.isEmpty else {
            throw GoogleOAuthError.notAuthorized
        }
        let fields = [
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let token: GoogleTokenResponse
        do {
            token = try await postForm(fields)
        } catch let error as GoogleOAuthError {
            throw GoogleOAuthError.refreshFailed(error.localizedDescription)
        } catch {
            throw GoogleOAuthError.refreshFailed(error.localizedDescription)
        }
        // refresh 响应通常不再带 refresh_token，保留原来那条即可。
        cache(token)
        return token.accessToken
    }

    private func postForm(_ fields: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: GoogleOAuthEndpoint.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(fields).utf8)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let message = Self.errorDescription(from: data) ?? "HTTP \(response.statusCode)"
            throw GoogleOAuthError.tokenExchangeFailed(message)
        }
        do {
            return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            throw GoogleOAuthError.tokenExchangeFailed("无法解析 Google 的令牌响应")
        }
    }

    private func cache(_ token: GoogleTokenResponse) {
        cachedAccessToken = token.accessToken
        // 提前 60 秒视为过期，避免"刚好在请求途中过期"。
        cachedExpiry = Date().addingTimeInterval(TimeInterval(max(token.expiresIn - 60, 30)))
    }

    // MARK: - 编码

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    static func errorDescription(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String
        else { return nil }
        if let description = object["error_description"] as? String {
            return "\(error)：\(description)"
        }
        return error
    }
}
