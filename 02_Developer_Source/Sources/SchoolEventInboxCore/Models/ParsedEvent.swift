import Foundation

/// One candidate event as returned by DeepSeek. Dates stay as strings at the
/// boundary so malformed or ambiguous model output cannot be silently repaired.
public struct ParsedEvent: Codable, Equatable, Sendable {
    public var type: EventType
    public var title: String
    public var start: String?
    public var end: String?
    public var allDay: Bool
    public var location: String?
    public var confidence: Double
    public var evidence: String
    public var needsConfirmation: Bool
    public var notes: String

    public init(
        type: EventType,
        title: String,
        start: String?,
        end: String?,
        allDay: Bool,
        location: String?,
        confidence: Double,
        evidence: String,
        needsConfirmation: Bool,
        notes: String
    ) {
        self.type = type
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.confidence = confidence
        self.evidence = evidence
        self.needsConfirmation = needsConfirmation
        self.notes = notes
    }

    /// Presentation mapping requested for the confirmation cards.
    public var symbolName: String { type.symbolName }
    public var colorToken: String { type.colorToken }

    private enum CodingKeys: String, CodingKey {
        case type, title, start, end, allDay, location, confidence, evidence, needsConfirmation, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawType = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
        self.type = rawType.flatMap(EventType.init(rawValue:)) ?? .other
        self.title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "未命名事件"
        self.start = (try? container.decodeIfPresent(String.self, forKey: .start)) ?? nil
        self.end = (try? container.decodeIfPresent(String.self, forKey: .end)) ?? nil
        self.allDay = ((try? container.decodeIfPresent(Bool.self, forKey: .allDay)) ?? nil) ?? false
        self.location = (try? container.decodeIfPresent(String.self, forKey: .location)) ?? nil
        if let number = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            self.confidence = number
        } else if let string = try? container.decodeIfPresent(String.self, forKey: .confidence),
                  let number = Double(string) {
            self.confidence = number
        } else {
            self.confidence = 0
        }
        self.evidence = ((try? container.decodeIfPresent(String.self, forKey: .evidence)) ?? nil) ?? ""
        self.needsConfirmation = ((try? container.decodeIfPresent(Bool.self, forKey: .needsConfirmation)) ?? nil) ?? true
        self.notes = ((try? container.decodeIfPresent(String.self, forKey: .notes)) ?? nil) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encode(allDay, forKey: .allDay)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(needsConfirmation, forKey: .needsConfirmation)
        try container.encode(notes, forKey: .notes)
    }
}

/// Top-level payload from DeepSeek: either candidates or a short error.
public struct ParseResponse: Codable, Equatable, Sendable {
    public var events: [ParsedEvent]
    public var error: String?

    public init(events: [ParsedEvent], error: String? = nil) {
        self.events = events
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case events, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.events = (try? container.decodeIfPresent([ParsedEvent].self, forKey: .events)) ?? []
        self.error = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? nil
    }
}

public enum ParsedEventSanitizer {
    /// Enforces the local safety rules regardless of what the model returned.
    /// The first release never auto-writes any event, so every candidate remains
    /// confirmation-gated. Critical types can never be downgraded by the model.
    public static func sanitize(_ events: [ParsedEvent]) -> [ParsedEvent] {
        events.prefix(50).map { event in
            var result = event
            result.type = event.type
            result.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.title.isEmpty {
                result.title = "未命名事件"
            }
            result.evidence = event.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            result.notes = event.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            result.location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            result.confidence = min(max(event.confidence, 0), 1)

            if event.type.requiresConfirmation && !event.needsConfirmation {
                result.notes = appendNote("模型曾试图降低确认要求，已强制改为需要确认。", to: result.notes)
            }
            if result.start == nil {
                result.notes = appendNote("未识别到开始时间，需人工补充。", to: result.notes)
            }
            result.needsConfirmation = true
            return result
        }
    }

    public static func appendNote(_ note: String, to existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(note) {
            return trimmed
        }
        return trimmed.isEmpty ? note : "\(trimmed)；\(note)"
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
