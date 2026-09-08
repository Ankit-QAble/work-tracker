import Foundation
import GRDB

/// Owns the on-disk SQLite database and schema migrations.
/// All data lives under ~/Library/Application Support/ActivityTracker/ — nothing leaves this Mac.
final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ActivityTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var screenshotsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        let dbURL = Self.appSupportDirectory.appendingPathComponent("activity.sqlite")
        do {
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try Self.migrator.migrate(dbQueue)
            Log.info("Database ready at \(dbURL.path)")
        } catch {
            fatalError("Failed to open/migrate database: \(error)")
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "app_intervals") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("app_name", .text).notNull()
                t.column("window_title", .text)
                t.column("url", .text)
                t.column("domain", .text)
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
                t.column("is_idle", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_app_intervals_start", on: "app_intervals", columns: ["start_time"])
            try db.create(index: "idx_app_intervals_domain", on: "app_intervals", columns: ["domain"])

            try db.create(table: "activity_scores") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("minute_timestamp", .datetime).notNull()
                t.column("event_count", .integer).notNull()
                t.column("score", .integer).notNull()
                t.column("app_interval_id", .integer).references("app_intervals", onDelete: .setNull)
            }
            try db.create(index: "idx_activity_scores_minute", on: "activity_scores", columns: ["minute_timestamp"])

            try db.create(table: "screenshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("file_path", .text).notNull()
                t.column("activity_score", .integer)
                t.column("app_interval_id", .integer).references("app_intervals", onDelete: .setNull)
            }
            try db.create(index: "idx_screenshots_timestamp", on: "screenshots", columns: ["timestamp"])
        }

        migrator.registerMigration("v2_meeting_sessions") { db in
            // Deliberately separate from app_intervals: a meeting can legitimately
            // overlap with whatever app is frontmost (e.g. Teams call running while
            // you're actively working in Chrome on a second monitor), whereas
            // app_intervals models a single sequential "what's frontmost right now"
            // timeline that can't represent overlap.
            try db.create(table: "meeting_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("app_name", .text).notNull()
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
            }
            try db.create(index: "idx_meeting_sessions_start", on: "meeting_sessions", columns: ["start_time"])
        }

        return migrator
    }
}

/// Tiny logging shim. Uses os_log (unified logging) rather than plain print() so output
/// shows up in Console.app / `log stream` regardless of how the app was launched
/// (Finder, `open`, LaunchAgent) — plain stdout is otherwise discarded for GUI apps
/// not attached to a terminal. Format strings use `%{public}@` because the unified
/// log redacts dynamic string arguments as "<private>" by default. No key content,
/// no PII beyond what the user is explicitly tracking (app names, titles, URLs).
import os.log

enum Log {
    private static let logger = OSLog(subsystem: "com.ankit.activitytracker", category: "general")

    static func info(_ message: String) {
        os_log("%{public}@", log: logger, type: .info, message)
    }
    static func error(_ message: String) {
        os_log("ERROR: %{public}@", log: logger, type: .error, message)
    }
}
