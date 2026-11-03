import Foundation

public struct LogRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: String
    public var inputType: String?
    public var imageCount: Int?
    public var eventCount: Int?
    public var eventTypes: [String]?
    public var error: String?
    public var durationMs: Int?
    public var modifiedFields: [String]?
    public var writtenCount: Int?
    public var conflictCount: Int?
    public var skippedConflictCount: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: String,
        inputType: String? = nil,
        imageCount: Int? = nil,
        eventCount: Int? = nil,
        eventTypes: [String]? = nil,
        error: String? = nil,
        durationMs: Int? = nil,
        modifiedFields: [String]? = nil,
        writtenCount: Int? = nil,
        conflictCount: Int? = nil,
        skippedConflictCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.inputType = inputType
        self.imageCount = imageCount
        self.eventCount = eventCount
        self.eventTypes = eventTypes
        self.error = error
        self.durationMs = durationMs
        self.modifiedFields = modifiedFields
        self.writtenCount = writtenCount
        self.conflictCount = conflictCount
        self.skippedConflictCount = skippedConflictCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, inputType, imageCount, eventCount, durationMs, error
        case writtenCount, conflictCount, skippedConflictCount
        case ts, timestamp, types, eventTypes, editedFields, modifiedFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decode(String.self, forKey: .kind)
        if let ts = try container.decodeIfPresent(Date.self, forKey: .ts) {
            self.timestamp = ts
        } else {
            self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        }
        self.inputType = try container.decodeIfPresent(String.self, forKey: .inputType)
        self.imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount)
        self.eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount)
        self.eventTypes = try container.decodeIfPresent([String].self, forKey: .types)
            ?? container.decodeIfPresent([String].self, forKey: .eventTypes)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        self.modifiedFields = try container.decodeIfPresent([String].self, forKey: .editedFields)
            ?? container.decodeIfPresent([String].self, forKey: .modifiedFields)
        self.writtenCount = try container.decodeIfPresent(Int.self, forKey: .writtenCount)
        self.conflictCount = try container.decodeIfPresent(Int.self, forKey: .conflictCount)
        self.skippedConflictCount = try container.decodeIfPresent(Int.self, forKey: .skippedConflictCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .ts)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(inputType, forKey: .inputType)
        try container.encodeIfPresent(imageCount, forKey: .imageCount)
        try container.encodeIfPresent(eventCount, forKey: .eventCount)
        try container.encode(eventTypes, forKey: .types)
        try container.encode(error, forKey: .error)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(modifiedFields, forKey: .editedFields)
        try container.encodeIfPresent(writtenCount, forKey: .writtenCount)
        try container.encodeIfPresent(conflictCount, forKey: .conflictCount)
        try container.encodeIfPresent(skippedConflictCount, forKey: .skippedConflictCount)
    }
}

/// Defense in depth for the few free-form strings that can reach the log.
/// Titles, locations, evidence and mail bodies are never part of LogRecord.
public enum LogSanitizer {
    private static let idCardPattern = #"\b\d{17}[\dXx]\b"#
    private static let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
    private static let longDigitPattern = #"\d{10,}"#

    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        result = result.replacingOccurrences(
            of: idCardPattern,
            with: "[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: emailPattern,
            with: "[REDACTED]",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: longDigitPattern,
            with: "[REDACTED]",
            options: .regularExpression
        )
        return result
    }

    public static func sanitized(_ record: LogRecord) -> LogRecord {
        var result = record
        result.kind = redact(record.kind)
        result.inputType = record.inputType.map(redact)
        result.eventTypes = record.eventTypes?.map(redact)
        result.error = record.error.map(redact)
        result.modifiedFields = record.modifiedFields?.map(redact)
        return result
    }
}

public struct LogStats: Equatable, Sendable {
    public var usageCount: Int
    public var writeCount: Int
    public var modifiedWriteCount: Int
    public var missedFeedbackCount: Int
    public var windowDays: Int

    public static let empty = LogStats(
        usageCount: 0,
        writeCount: 0,
        modifiedWriteCount: 0,
        missedFeedbackCount: 0,
        windowDays: 14
    )

    public var modificationRate: Double {
        guard writeCount > 0 else { return 0 }
        return Double(modifiedWriteCount) / Double(writeCount)
    }
}

public final class LogService: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) throws {
        let baseDirectory: URL
        if let directory {
            baseDirectory = directory
        } else {
            baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("SchoolEventInbox", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("SchoolEventInbox", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileURL = baseDirectory.appendingPathComponent("log.jsonl")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public var path: String { fileURL.path }

    public func append(_ record: LogRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        let safeRecord = LogSanitizer.sanitized(record)
        var data = try encoder.encode(safeRecord)
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }

    public func records(limit: Int? = nil) -> [LogRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadAllLocked(limit: limit)
    }

    @discardableResult
    public func exportLast30(to destination: URL) throws -> Int {
        let recent = records(limit: 30)
        var output = Data()
        for record in recent {
            // Redact again at export time so legacy files are also protected.
            var data = try encoder.encode(LogSanitizer.sanitized(record))
            data.append(0x0A)
            output.append(data)
        }
        try output.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return recent.count
    }

    /// Deletes only log.jsonl. Used by the explicit, confirmed UI action.
    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    public func stats(days: Int = 14, now: Date = Date()) -> LogStats {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let recent = records().filter { $0.timestamp >= cutoff }
        let parses = recent.filter { $0.kind == "parse" }
        let writes = recent.filter { $0.kind == "write" }
        let modifiedWrites = writes.filter { !($0.modifiedFields ?? []).isEmpty }
        let feedback = recent.filter { $0.kind == "missed_feedback" }
        return LogStats(
            usageCount: parses.count,
            writeCount: writes.count,
            modifiedWriteCount: modifiedWrites.count,
            missedFeedbackCount: feedback.count,
            windowDays: days
        )
    }

    private func loadAllLocked(limit: Int?) -> [LogRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        var results: [LogRecord] = []
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(LogRecord.self, from: lineData) else {
                continue
            }
            results.append(LogSanitizer.sanitized(record))
        }
        if let limit {
            return Array(results.suffix(limit))
        }
        return results
    }
}
