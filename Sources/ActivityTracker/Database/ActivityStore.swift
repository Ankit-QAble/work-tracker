import Foundation
import GRDB

/// Simple data-access layer sitting on top of DatabaseManager.
/// Everything here is synchronous-but-fast (SQLite on local disk); callers on the main
/// actor are fine to call it directly for the small reads/writes this app does.
final class ActivityStore {
    static let shared = ActivityStore()
    private var db: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {}

    // MARK: - App intervals

    /// Closes any still-open interval (end_time IS NULL) and opens a new one.
    /// Returns the new interval's row id.
    @discardableResult
    func startInterval(appName: String, windowTitle: String?, url: String?, domain: String?, isIdle: Bool, at date: Date = Date()) -> Int64? {
        do {
            return try db.write { db in
                try self.closeOpenIntervals(db, at: date)
                var interval = AppInterval(
                    id: nil,
                    appName: appName,
                    windowTitle: windowTitle,
                    url: url,
                    domain: domain,
                    startTime: date,
                    endTime: nil,
                    isIdle: isIdle
                )
                try interval.insert(db)
                return interval.id
            }
        } catch {
            Log.error("startInterval failed: \(error)")
            return nil
        }
    }

    /// Closes whatever interval is currently open, without opening a new one (e.g. on quit).
    func closeCurrentInterval(at date: Date = Date()) {
        do {
            try db.write { db in
                try self.closeOpenIntervals(db, at: date)
            }
        } catch {
            Log.error("closeCurrentInterval failed: \(error)")
        }
    }

    private func closeOpenIntervals(_ db: Database, at date: Date) throws {
        try db.execute(
            sql: "UPDATE app_intervals SET end_time = ? WHERE end_time IS NULL",
            arguments: [date]
        )
    }

    /// Updates the window title / URL / domain of whatever interval is currently open,
    /// without closing it. Used by the browser and window-title pollers so a fast-changing
    /// tab/title doesn't fragment the underlying app interval into dozens of tiny rows.
    func updateOpenInterval(windowTitle: String? = nil, url: String? = nil, domain: String? = nil) {
        do {
            try db.write { db in
                guard var interval = try AppInterval
                    .filter(AppInterval.Columns.endTime == nil)
                    .order(AppInterval.Columns.startTime.desc)
                    .fetchOne(db)
                else { return }
                if let windowTitle { interval.windowTitle = windowTitle }
                if let url { interval.url = url }
                if let domain { interval.domain = domain }
                try interval.update(db)
            }
        } catch {
            Log.error("updateOpenInterval failed: \(error)")
        }
    }

    /// Reattributes a previously-idle interval to a real app as tracked time — used
    /// when the user, on returning from being away, says "actually count that as
    /// work" in the idle-resume prompt.
    func reattributeAsTracked(intervalId: Int64, appName: String) {
        do {
            try db.write { db in
                guard var interval = try AppInterval.fetchOne(db, key: intervalId) else { return }
                interval.isIdle = false
                interval.appName = appName
                try interval.update(db)
            }
        } catch {
            Log.error("reattributeAsTracked failed: \(error)")
        }
    }

    func currentOpenInterval() -> AppInterval? {
        try? db.read { db in
            try AppInterval
                .filter(AppInterval.Columns.endTime == nil)
                .order(AppInterval.Columns.startTime.desc)
                .fetchOne(db)
        }
    }

    func intervals(on day: Date, calendar: Calendar = .current) -> [AppInterval] {
        let (start, end) = dayBounds(day, calendar: calendar)
        return (try? db.read { db in
            try AppInterval
                .filter(AppInterval.Columns.startTime < end)
                .filter(AppInterval.Columns.endTime == nil || AppInterval.Columns.endTime > start)
                .order(AppInterval.Columns.startTime.asc)
                .fetchAll(db)
        }) ?? []
    }

    /// All intervals overlapping [start, end) — the general-purpose version of
    /// `intervals(on:)`, used by CSV export for week/month ranges.
    func intervals(from start: Date, to end: Date) -> [AppInterval] {
        (try? db.read { db in
            try AppInterval
                .filter(AppInterval.Columns.startTime < end)
                .filter(AppInterval.Columns.endTime == nil || AppInterval.Columns.endTime > start)
                .order(AppInterval.Columns.startTime.asc)
                .fetchAll(db)
        }) ?? []
    }

    /// Average activity score recorded during [start, end) — used to annotate each
    /// exported interval with how "active" it was, without a per-interval join.
    func averageActivityScore(from start: Date, to end: Date) -> Int? {
        let scores: [ActivityScore] = (try? db.read { db in
            try ActivityScore
                .filter(Column("minute_timestamp") >= start && Column("minute_timestamp") < end)
                .fetchAll(db)
        }) ?? []
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0) { $0 + $1.score } / scores.count
    }

    func appTimeSummary(on day: Date, calendar: Calendar = .current) -> [AppTimeSummary] {
        let intervals = self.intervals(on: day, calendar: calendar)
        let (start, end) = dayBounds(day, calendar: calendar)
        var totals: [String: TimeInterval] = [:]
        for interval in intervals where !interval.isIdle {
            let clampedStart = max(interval.startTime, start)
            let clampedEnd = min(interval.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }
            totals[interval.appName, default: 0] += clampedEnd.timeIntervalSince(clampedStart)
        }
        return totals.map { AppTimeSummary(appName: $0.key, totalSeconds: $0.value) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    func domainTimeSummary(on day: Date, calendar: Calendar = .current) -> [DomainTimeSummary] {
        let intervals = self.intervals(on: day, calendar: calendar)
        let (start, end) = dayBounds(day, calendar: calendar)
        var totals: [String: TimeInterval] = [:]
        for interval in intervals {
            guard let domain = interval.domain, !interval.isIdle else { continue }
            let clampedStart = max(interval.startTime, start)
            let clampedEnd = min(interval.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }
            totals[domain, default: 0] += clampedEnd.timeIntervalSince(clampedStart)
        }
        return totals.map { DomainTimeSummary(domain: $0.key, totalSeconds: $0.value) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private func dayBounds(_ day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    // MARK: - Activity scores

    @discardableResult
    func recordActivityScore(minuteTimestamp: Date, eventCount: Int, score: Int, appIntervalId: Int64?) -> Int64? {
        do {
            return try db.write { db in
                var row = ActivityScore(
                    id: nil,
                    minuteTimestamp: minuteTimestamp,
                    eventCount: eventCount,
                    score: score,
                    appIntervalId: appIntervalId
                )
                try row.insert(db)
                return row.id
            }
        } catch {
            Log.error("recordActivityScore failed: \(error)")
            return nil
        }
    }

    func activityScores(on day: Date, calendar: Calendar = .current) -> [ActivityScore] {
        let (start, end) = dayBounds(day, calendar: calendar)
        return (try? db.read { db in
            try ActivityScore
                .filter(Column("minute_timestamp") >= start && Column("minute_timestamp") < end)
                .order(Column("minute_timestamp").asc)
                .fetchAll(db)
        }) ?? []
    }

    // MARK: - Screenshots

    @discardableResult
    func recordScreenshot(timestamp: Date, filePath: String, activityScore: Int?, appIntervalId: Int64?) -> Int64? {
        do {
            return try db.write { db in
                var row = Screenshot(
                    id: nil,
                    timestamp: timestamp,
                    filePath: filePath,
                    activityScore: activityScore,
                    appIntervalId: appIntervalId
                )
                try row.insert(db)
                return row.id
            }
        } catch {
            Log.error("recordScreenshot failed: \(error)")
            return nil
        }
    }

    func screenshots(on day: Date, calendar: Calendar = .current) -> [Screenshot] {
        let (start, end) = dayBounds(day, calendar: calendar)
        return (try? db.read { db in
            try Screenshot
                .filter(Column("timestamp") >= start && Column("timestamp") < end)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }) ?? []
    }
}
