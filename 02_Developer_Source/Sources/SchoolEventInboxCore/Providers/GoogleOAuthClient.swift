import Foundation

/// Google 桌面端 OAuth 凭据（`google_client_secret.json` 的 `installed` 节点）。
///
/// 结构说明：Google Cloud 下载的桌面凭据顶层是 `installed`，Web 应用是 `web`。
/// 本项目只走 **installed + loopback（http://localhost）** 流程。
///
/// 安全约定：
/// - `clientSecret` 虽然对 installed app 不算机密，但**不要打进日志或错误信息**。
/// - 真正需要保护的是换回来的 `refresh_token`，它走 Keychain，不在这里。
public struct GoogleOAuthClient: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let redirectURIs: [String]
    public let authURI: URL?
    public let tokenURI: URL?
    public let projectID: String?

    public init(
        clientID: String,
        clientSecret: String,
        redirectURIs: [String] = [],
        authURI: URL? = nil,
        tokenURI: URL? = nil,
        projectID: String? = nil
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURIs = redirectURIs
        self.authURI = authURI
        self.tokenURI = tokenURI
        self.projectID = projectID
    }

    /// 安全的摘要，用于日志/诊断：只暴露 client_id 的前缀。
    public var redactedSummary: String {
        let prefix = clientID.split(separator: "-").first.map(String.init) ?? "?"
        return "GoogleOAuthClient(project=\(projectID ?? "?"), clientID=\(prefix)-…, redirectURIs=\(redirectURIs.count))"
    }
}

public enum GoogleOAuthClientError: LocalizedError, Equatable, Sendable {
    case missing
    case unreadable(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .missing:
            return "未找到 Google 凭据文件 google_client_secret.json，请放到 ~/Library/Application Support/More calendar/ 下"
        case .unreadable(let path):
            return "无法读取 Google 凭据文件：\(path)"
        case .malformed(let reason):
            return "Google 凭据文件格式不正确：\(reason)"
        }
    }
}

/// 凭据查找与解析。
///
/// **为什么不在 App bundle 里**：这个仓库与 Release zip 都是公开的，把凭据打进
/// `.app` 等于随每次发布公开分发。因此默认从用户目录读取：
///
/// 1. `~/Library/Application Support/More calendar/google_client_secret.json`（优先）
/// 2. `Bundle.main` 内的同名资源（**可选**回退；只有显式把它拷进 Contents/Resources 时才存在）
///
/// 仓库里的 `02_Developer_Source/Support/google_client_secret.json` **仅作版本备份**，
/// 不会被 `build_app.sh` 拷进 `.app`；改了凭据要同步到上面第 1 条的真实路径才生效。
///
/// 构建脚本 **不会** 把凭据拷进 `.app`，所以公开分发的包天然不含凭据。
public enum GoogleOAuthClientLoader {
    public static let fileName = "google_client_secret"
    public static let fileExtension = "json"
    /// 用户目录下的子目录名，与 App 显示名保持一致。
    public static let applicationSupportFolderName = "More calendar"

    /// 默认搜索顺序。纯路径计算，不读文件，便于断言。
    public static func defaultSearchURLs(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) -> [URL] {
        var urls: [URL] = []
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            urls.append(
                appSupport
                    .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
                    .appendingPathComponent("\(fileName).\(fileExtension)")
            )
        }
        if let bundled = bundle.url(forResource: fileName, withExtension: fileExtension) {
            urls.append(bundled)
        }
        return urls
    }

    /// 按默认顺序加载第一个存在的凭据。
    public static func load(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> GoogleOAuthClient {
        let candidates = defaultSearchURLs(fileManager: fileManager, bundle: bundle)
        guard !candidates.isEmpty else { throw GoogleOAuthClientError.missing }

        var lastError: GoogleOAuthClientError?
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                return try load(from: url, fileManager: fileManager)
            } catch let error as GoogleOAuthClientError {
                lastError = error
            }
        }
        // 文件存在但格式坏 —— 报格式错误比"找不到"更有诊断价值。
        if let lastError { throw lastError }
        throw GoogleOAuthClientError.missing
    }

    /// 从指定路径加载。测试与"导入凭据"入口都会用它。
    public static func load(
        from url: URL,
        fileManager: FileManager = .default
    ) throws -> GoogleOAuthClient {
        guard fileManager.fileExists(atPath: url.path) else {
            throw GoogleOAuthClientError.missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GoogleOAuthClientError.unreadable(url.path)
        }
        return try parse(data)
    }

    /// 解析凭据 JSON。`installed` 与 `web` 两种顶层节点都接受。
    public static func parse(_ data: Data) throws -> GoogleOAuthClient {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GoogleOAuthClientError.malformed("不是合法 JSON")
        }
        guard let root = object as? [String: Any] else {
            throw GoogleOAuthClientError.malformed("顶层不是 JSON 对象")
        }
        guard let node = (root["installed"] as? [String: Any]) ?? (root["web"] as? [String: Any]) else {
            throw GoogleOAuthClientError.malformed("缺少 installed / web 节点")
        }
        guard let clientID = node["client_id"] as? String, !clientID.isEmpty else {
            throw GoogleOAuthClientError.malformed("缺少 client_id")
        }
        guard let clientSecret = node["client_secret"] as? String, !clientSecret.isEmpty else {
            throw GoogleOAuthClientError.malformed("缺少 client_secret")
        }

        return GoogleOAuthClient(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURIs: node["redirect_uris"] as? [String] ?? [],
            authURI: (node["auth_uri"] as? String).flatMap(URL.init(string:)),
            tokenURI: (node["token_uri"] as? String).flatMap(URL.init(string:)),
            projectID: node["project_id"] as? String
        )
    }
}
