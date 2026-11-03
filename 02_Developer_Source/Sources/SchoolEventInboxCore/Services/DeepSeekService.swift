import Foundation

public protocol DeepSeekClient: Sendable {
    func parse(text: String, systemPrompt: String, apiKey: String) async throws -> ParseResponse
}

public enum DeepSeekError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case missingSystemPrompt
    case unauthorized
    case insufficientBalance
    case rateLimited
    case serviceUnavailable
    case timedOut
    case networkUnavailable
    case badResponse
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "未配置 DeepSeek API Key"
        case .missingSystemPrompt: return "缺少 system_prompt.txt"
        case .unauthorized: return "API Key 无效或未授权"
        case .insufficientBalance: return "DeepSeek 账户余额不足"
        case .rateLimited: return "调用过于频繁，请稍后重试"
        case .serviceUnavailable: return "DeepSeek 服务暂时不可用"
        case .timedOut: return "请求超时"
        case .networkUnavailable: return "网络不可用"
        case .badResponse: return "模型返回内容无法解析"
        case .httpError(let code): return "服务返回 HTTP \(code)"
        }
    }
}

public final class DeepSeekService: DeepSeekClient, @unchecked Sendable {
    private let endpoint: URL
    private let session: URLSession
    private let model: String

    public init(
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        model: String = "deepseek-chat",
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.model = model
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 90
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    public func parse(text: String, systemPrompt: String, apiKey: String) async throws -> ParseResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekError.missingAPIKey }
        guard !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingSystemPrompt
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let timeZone = TimeZone.current.identifier
        let userMessage = """
        当前日期时间：\(formatter.string(from: now))
        本机时区：\(timeZone)
        输入内容（邮件正文或本地 OCR 文本）：
        ---
        \(text)
        ---
        请只输出严格 JSON。
        """

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userMessage)
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object"),
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw DeepSeekError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw DeepSeekError.networkUnavailable
            default:
                throw DeepSeekError.badResponse
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.badResponse
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw DeepSeekError.unauthorized
        case 402:
            throw DeepSeekError.insufficientBalance
        case 429:
            throw DeepSeekError.rateLimited
        case 500...599:
            throw DeepSeekError.serviceUnavailable
        default:
            throw DeepSeekError.httpError(http.statusCode)
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw DeepSeekError.badResponse
        }

        guard let content = chatResponse.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.badResponse
        }

        let fallback = EnglishBirthdayListParser.parse(text: text, now: Date(), timeZone: .current)

        let json = try extractJSONObject(from: content)
        let parsed: ParseResponse
        do {
            parsed = try JSONDecoder().decode(ParseResponse.self, from: json)
        } catch {
            if let fallback { return ParseResponse(events: ParsedEventSanitizer.sanitize(fallback), error: nil) }
            throw DeepSeekError.badResponse
        }

        // The model has returned seven events for the list but sometimes labels
        // every one as "other". For an entire English month/day/name list, use
        // the deterministic birthday normalization instead.
        if let fallback {
            return ParseResponse(events: ParsedEventSanitizer.sanitize(fallback), error: nil)
        }

        let sanitized = ParsedEventSanitizer.sanitize(parsed.events)
        if sanitized.isEmpty {
            if let error = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                return ParseResponse(events: [], error: shortError(error))
            }
            return ParseResponse(events: [], error: "未识别到可确认的事件")
        }
        return ParseResponse(events: sanitized, error: nil)
    }

    private func extractJSONObject(from content: String) throws -> Data {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        // Defensive fallback for a model that wraps JSON in a code fence despite
        // response_format=json_object. We do not attempt to repair invalid JSON.
        let cleaned = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = cleaned.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        throw DeepSeekError.badResponse
    }

    private func shortError(_ message: String) -> String {
        let oneLine = message.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(oneLine.prefix(80))
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
