import Foundation
import Network

/// 接收 Google 授权回调的本地 HTTP 监听器（OAuth 2.0 loopback 流程）。
///
/// 只监听 `127.0.0.1` 上的随机端口，只处理第一个 `/callback` 请求，回一个
/// 人类可读的页面后即可关闭。绑定回环地址而非全部接口，避免 macOS 弹出
/// "允许接受传入连接" 的防火墙询问。
public actor GoogleOAuthLoopbackServer {
    public struct Callback: Equatable, Sendable {
        public let code: String?
        public let state: String?
        public let error: String?
        public let errorDescription: String?

        public init(code: String?, state: String?, error: String? = nil, errorDescription: String? = nil) {
            self.code = code
            self.state = state
            self.error = error
            self.errorDescription = errorDescription
        }
    }

    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<Callback, Error>?
    private var pendingCallback: Callback?

    public init() {}

    /// 启动监听并返回系统分配的端口号。
    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw GoogleOAuthError.listenerFailed(error.localizedDescription)
        }

        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handle(connection) }
        }
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// 等待浏览器回调。超时抛 `GoogleOAuthError.callbackTimeout`。
    public func waitForCallback(timeout: TimeInterval = 180) async throws -> Callback {
        if let pending = pendingCallback {
            pendingCallback = nil
            return pending
        }

        let timeoutTask = Task { [weak self, timeout] in
            try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
            await self?.failPending(with: GoogleOAuthError.callbackTimeout)
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            self.callbackContinuation = continuation
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        pendingCallback = nil
        callbackContinuation?.resume(throwing: GoogleOAuthError.callbackTimeout)
        callbackContinuation = nil
    }

    // MARK: - 内部

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                failReady(with: GoogleOAuthError.listenerFailed("未能获取监听端口"))
                return
            }
            readyContinuation?.resume(returning: port)
            readyContinuation = nil
        case .failed(let error):
            failReady(with: GoogleOAuthError.listenerFailed(error.localizedDescription))
        case .cancelled:
            failReady(with: GoogleOAuthError.listenerFailed("监听已取消"))
        default:
            break
        }
    }

    private func failReady(with error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func failPending(with error: Error) {
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            Task {
                guard let data, let callback = Self.parseCallback(from: data) else {
                    await self.respond(connection: connection, title: "无效请求", message: "这不是 Google 授权回调。")
                    return
                }
                await self.deliver(callback)
                if callback.error != nil {
                    await self.respond(
                        connection: connection,
                        title: "授权未完成",
                        message: "Google 返回了错误，请回到 More calendar 查看详情。"
                    )
                } else {
                    await self.respond(
                        connection: connection,
                        title: "授权成功",
                        message: "已经连接 Google 账户，可以关闭此页面回到 More calendar。"
                    )
                }
            }
        }
    }

    private func deliver(_ callback: Callback) {
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(returning: callback)
        } else {
            pendingCallback = callback
        }
    }

    private func respond(connection: NWConnection, title: String, message: String) {
        let body = """
        <!doctype html>
        <html lang="zh-Hans"><head><meta charset="utf-8">
        <title>\(title)</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:48px;max-width:520px;margin:0 auto;color:#1d1d1f">
        <h1 style="font-size:22px">\(title)</h1>
        <p style="font-size:15px;line-height:1.6;color:#6e6e73">\(message)</p>
        </body></html>
        """
        let data = Data(body.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r
        
        """
        var response = Data(header.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// 解析 `GET /callback?code=...&state=... HTTP/1.1`。
    /// `nonisolated` 便于在测试里直接喂字节串。
    public nonisolated static func parseCallback(from data: Data) -> Callback? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let firstLine = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let target = String(parts[1])
        let path = target.split(separator: "?").first.map(String.init) ?? target
        guard let components = URLComponents(string: "http://127.0.0.1" + target),
              // 注册的 redirect_uri 不带路径，浏览器会请求 "/"；同时兼容历史 /callback。
              ["", "/", "/callback"].contains(components.path.isEmpty ? "" : components.path),
              path.hasPrefix("/") else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        return Callback(
            code: value("code"),
            state: value("state"),
            error: value("error"),
            errorDescription: value("error_description")
        )
    }
}
