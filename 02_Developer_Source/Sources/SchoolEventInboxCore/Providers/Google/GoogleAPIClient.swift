import Foundation

/// 访问令牌提供者。`GoogleAPIClient` 只依赖这个协议，不关心 OAuth 细节。
public protocol GoogleTokenProvider: Sendable {
    /// 返回可直接用于 `Authorization: Bearer` 的令牌；必要时内部刷新。
    func validAccessToken() async throws -> String
    /// 强制刷新（401 之后调用）。
    func forceRefreshAccessToken() async throws -> String
}

/// 传输层抽象：唯一职责是把 `URLRequest` 发出去。
///
/// 之所以只留一个方法，是为了让自测沿用现有的 `MockURLProtocol` 注入 `URLSession`，
/// 不必为 Google 再造一套桩。
public protocol GoogleHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: GoogleHTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? URLSessionTransport.makeSession()
    }

    /// 临时会话：不落 cookie、不落缓存，避免授权态残留到磁盘。
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GoogleAPIError.network("响应不是 HTTP 响应")
            }
            return (data, http)
        } catch let error as GoogleAPIError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw GoogleAPIError.cancelled }
            throw GoogleAPIError.network(error.localizedDescription)
        } catch {
            throw GoogleAPIError.network(error.localizedDescription)
        }
    }
}

public enum GoogleAPIError: LocalizedError, Equatable, Sendable {
    case unauthorized
    case forbidden(String)
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case http(status: Int, message: String)
    case decoding(String)
    case network(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Google 授权已失效，请重新连接账户"
        case .forbidden(let message):
            return "Google 拒绝了该操作：\(message)"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Google 接口限流，请约 \(Int(retryAfter)) 秒后重试"
            }
            return "Google 接口限流，请稍后重试"
        case .notFound:
            return "目标日历或事件不存在（可能已被删除）"
        case .http(let status, let message):
            return "Google 接口返回 \(status)：\(message)"
        case .decoding(let message):
            return "无法解析 Google 返回的数据：\(message)"
        case .network(let message):
            return "网络请求失败：\(message)"
        case .cancelled:
            return "请求已取消"
        }
    }
}

public struct GoogleAPIRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var contentType: String?

    public init(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.contentType = contentType
    }

    public static func json<T: Encodable>(_ method: String, path: String, query: [URLQueryItem] = [], body: T) throws -> GoogleAPIRequest {
        let encoder = JSONEncoder()
        return GoogleAPIRequest(
            method: method,
            path: path,
            query: query,
            body: try encoder.encode(body),
            contentType: "application/json; charset=utf-8"
        )
    }
}

/// Google Calendar REST 客户端。
///
/// 设计要点：
/// - **401 只自动刷新一次**，刷新后仍 401 就失败，避免死循环。
/// - 限流（403 `rateLimitExceeded` / 429）**不自动重试**：静默重试会让"写入 3 条却卡 20 秒"
///   变得无法解释，直接把重试决策交给上层。
/// - 错误统一为 `GoogleAPIError`，由 `GoogleCalendarProvider` 再翻译成 `TargetProviderError`。
public actor GoogleAPIClient {
    private let transport: any GoogleHTTPTransport
    private let tokenProvider: any GoogleTokenProvider
    private let baseURL: URL

    public init(
        transport: any GoogleHTTPTransport = URLSessionTransport(),
        tokenProvider: any GoogleTokenProvider,
        baseURL: URL = URL(string: "https://www.googleapis.com/calendar/v3")!
    ) {
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
    }

    @discardableResult
    public func send<T: Decodable>(_ request: GoogleAPIRequest, as type: T.Type = T.self) async throws -> T {
        let data = try await perform(request)
        guard !data.isEmpty else {
            throw GoogleAPIError.decoding("预期有响应体但收到空内容")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GoogleAPIError.decoding(String(describing: error))
        }
    }

    public func send(_ request: GoogleAPIRequest) async throws {
        _ = try await perform(request)
    }

    /// 供分页使用：把一次响应里的 `nextPageToken` 拼进下一次请求。
    public func sendAllPages<T: Decodable, Item>(
        _ request: GoogleAPIRequest,
        as type: T.Type,
        items: (T) -> [Item],
        nextToken: (T) -> String?
    ) async throws -> [Item] {
        var collected: [Item] = []
        var pageToken: String?
        repeat {
            var pageRequest = request
            if let pageToken {
                pageRequest.query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let page = try await send(pageRequest, as: type)
            collected.append(contentsOf: items(page))
            pageToken = nextToken(page)
        } while pageToken != nil
        return collected
    }

    // MARK: - 内部

    private func perform(_ request: GoogleAPIRequest) async throws -> Data {
        var token = try await tokenProvider.validAccessToken()
        var urlRequest = try makeURLRequest(request, token: token)
        // 记录**实际**发出的 URL：排查 404 时这是唯一可靠的事实来源。
        GoogleDiagnostics.log("HTTP → \(request.method) \(urlRequest.url?.absoluteString ?? "?")")
        var (data, response) = try await transport.send(urlRequest)
        GoogleDiagnostics.log("HTTP ← \(response.statusCode) \(request.path)")

        if response.statusCode == 401 {
            // 令牌可能过期（或被用户撤销）。刷新一次再试。
            GoogleDiagnostics.log("HTTP 401，尝试刷新令牌后重试")
            token = try await tokenProvider.forceRefreshAccessToken()
            urlRequest = try makeURLRequest(request, token: token)
            (data, response) = try await transport.send(urlRequest)
            GoogleDiagnostics.log("HTTP ← \(response.statusCode)（重试后）")
        }

        do {
            try validate(status: response.statusCode, data: data, response: response)
        } catch {
            let parsed = Self.parseError(data)
            GoogleDiagnostics.log("HTTP 失败 \(response.statusCode) reason=\(parsed.reason ?? "-") message=\(parsed.message ?? "-")")
            throw error
        }
        return data
    }

    private func makeURLRequest(_ request: GoogleAPIRequest, token: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleAPIError.network("无法构造请求 URL")
        }
        let relative = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        let basePath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        // 用 percentEncodedPath 而不是 appendingPathComponent：后者会把 `%` 再编码一次，
        // 使日历 id 里的 `@`（如 name@gmail.com）变成 `%2540`，Google 直接回 404。
        // 这里对每个路径段精确编码一次，`@` → `%40`。
        components.percentEncodedPath = basePath + "/" + Self.percentEncodedPath(relative)
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let finalURL = components.url else {
            throw GoogleAPIError.network("无法构造请求 URL")
        }

        var urlRequest = URLRequest(url: finalURL)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue(request.contentType ?? "application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    private func validate(status: Int, data: Data, response: HTTPURLResponse) throws {
        switch status {
        case 200..<300:
            return
        case 401:
            throw GoogleAPIError.unauthorized
        case 403:
            let parsed = Self.parseError(data)
            if parsed.reason == "rateLimitExceeded" || parsed.reason == "userRateLimitExceeded" {
                throw GoogleAPIError.rateLimited(retryAfter: Self.retryAfter(from: response))
            }
            throw GoogleAPIError.forbidden(parsed.message ?? "权限不足")
        case 404, 410:
            throw GoogleAPIError.notFound
        case 429:
            throw GoogleAPIError.rateLimited(retryAfter: Self.retryAfter(from: response))
        default:
            let parsed = Self.parseError(data)
            throw GoogleAPIError.http(status: status, message: parsed.message ?? "未知错误")
        }
    }

    /// 逐段编码路径。只保留 unreserved 字符，其余（含 `@`、空格）一律百分号编码。
    static func percentEncodedPath(_ path: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw)
    }

    struct ParsedError {
        let message: String?
        let reason: String?
    }

    static func parseError(_ data: Data) -> ParsedError {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return ParsedError(message: nil, reason: nil)
        }
        let message = error["message"] as? String
        let reason = (error["errors"] as? [[String: Any]])?.first?["reason"] as? String
        return ParsedError(message: message, reason: reason)
    }
}
