import Foundation
import GRDB

/// One continuous stretch of time spent in a single frontmost app (or idle).
struct AppInterval: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "app_intervals"

    var id: Int64?
    var appName: String
    var windowTitle: String?
    var url: String?
    var domain: String?
    var startTime: Date
    var endTime: Date?
    var isIdle: Bool

    enum Columns {
        static let id = Column("id")
        static let appName = Column("app_name")
        static let windowTitle = Column("window_title")
        static let url = Column("url")
        static let domain = Column("domain")
        static let startTime = Column("start_time")
        static let endTime = Column("end_time")
        static let isIdle = Column("is_idle")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case appName = "app_name"
        case windowTitle = "window_title"
        case url
        case domain
        case startTime = "start_time"
        case endTime = "end_time"
        case isIdle = "is_idle"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One minute-bucket of input-event-derived activity score.
struct ActivityScore: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "activity_scores"

    var id: Int64?
    var minuteTimestamp: Date
    var eventCount: Int
    var score: Int
    var appIntervalId: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case minuteTimestamp = "minute_timestamp"
        case eventCount = "event_count"
        case score
        case appIntervalId = "app_interval_id"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One captured screenshot.
struct Screenshot: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "screenshots"

    var id: Int64?
    var timestamp: Date
    var filePath: String
    var activityScore: Int?
    var appIntervalId: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case filePath = "file_path"
        case activityScore = "activity_score"
        case appIntervalId = "app_interval_id"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Aggregated time-per-app, used by the dashboard.
struct AppTimeSummary: Identifiable {
    var id: String { appName }
    var appName: String
    var totalSeconds: TimeInterval
}

/// Aggregated time-per-domain, used by the dashboard.
struct DomainTimeSummary: Identifiable {
    var id: String { domain }
    var domain: String
    var totalSeconds: TimeInterval
}
