import Foundation

/// Google 接入的本地诊断日志。
///
/// 只写本机 JSONL，不发送给 Google。用于回答"为什么浏览器没弹出来"这类
/// 纯本地问题：每一步都留痕，失败时能定位到具体阶段。
///
/// **约定**：不要在这里写入 client_secret / refresh_token / access_token。
public enum GoogleDiagnostics {
    private static let lock = NSLock()
    private static var sink: ((String) -> Void)?

    public static func install(_ sink: @escaping (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.sink = sink
    }

    public static func log(_ message: String) {
        lock.lock()
        let sink = self.sink
        lock.unlock()
        sink?("[\(Self.timestamp())] \(message)")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
