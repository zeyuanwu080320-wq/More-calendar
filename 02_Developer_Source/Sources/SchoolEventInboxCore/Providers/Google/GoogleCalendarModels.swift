import Foundation

/// `GET /users/me/calendarList` 的一项。
public struct GoogleCalendarListEntry: Decodable, Equatable, Sendable {
    public let id: String
    public let summary: String
    public let primary: Bool?
    public let accessRole: String?
    public let timeZone: String?
    public let backgroundColor: String?
    public let selected: Bool?

    public var isWritable: Bool {
        guard let accessRole else { return false }
        return accessRole == "owner" || accessRole == "writer"
    }
}

struct GoogleCalendarListResponse: Decodable, Sendable {
    let items: [GoogleCalendarListEntry]?
    let nextPageToken: String?
}

public struct GoogleEventDateTime: Codable, Equatable, Sendable {
    /// 定时事件用 RFC3339 时间。
    public var dateTime: String?
    /// 全天事件用 `yyyy-MM-dd`；`end.date` 是**排他**的次日。
    public var date: String?
    public var timeZone: String?

    public init(dateTime: String? = nil, date: String? = nil, timeZone: String? = nil) {
        self.dateTime = dateTime
        self.date = date
        self.timeZone = timeZone
    }
}

public struct GoogleExtendedProperties: Codable, Equatable, Sendable {
    public var `private`: [String: String]?

    public init(private: [String: String]? = nil) {
        self.private = `private`
    }
}

/// Google Calendar 的事件资源。既用作请求体，也用作响应体。
public struct GoogleEvent: Codable, Equatable, Sendable {
    public var id: String?
    public var summary: String?
    public var notes: String?
    public var location: String?
    public var start: GoogleEventDateTime?
    public var end: GoogleEventDateTime?
    public var recurrence: [String]?
    public var status: String?
    public var colorId: String?
    public var extendedProperties: GoogleExtendedProperties?
    public var transparency: String?
    /// 循环事件的**实例**会带上父事件 id；删除整条系列时要用它。
    public var recurringEventId: String?

    public init(
        id: String? = nil,
        summary: String? = nil,
        notes: String? = nil,
        location: String? = nil,
        start: GoogleEventDateTime? = nil,
        end: GoogleEventDateTime? = nil,
        recurrence: [String]? = nil,
        status: String? = nil,
        colorId: String? = nil,
        extendedProperties: GoogleExtendedProperties? = nil,
        transparency: String? = nil,
        recurringEventId: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.notes = notes
        self.location = location
        self.start = start
        self.end = end
        self.recurrence = recurrence
        self.status = status
        self.colorId = colorId
        self.extendedProperties = extendedProperties
        self.transparency = transparency
        self.recurringEventId = recurringEventId
    }

    enum CodingKeys: String, CodingKey {
        case id, summary, location, start, end, recurrence, status, colorId, extendedProperties, transparency
        case recurringEventId
        case notes = "description"
    }
}

public struct GoogleEventsListResponse: Decodable, Sendable {
    public let items: [GoogleEvent]?
    public let nextPageToken: String?
    public let summary: String?
    public let timeZone: String?
}
