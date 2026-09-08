import Foundation

enum ExportRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    /// The [start, end) interval this range covers, anchored on `day`.
    /// Week/month use the calendar's own week/month boundaries (e.g. "this week"),
    /// not a trailing N-day window, so exports line up with how a spreadsheet user
    /// naturally thinks about "this week's data".
    func bounds(containing day: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: day)
            return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: day) ?? DateInterval(start: day, duration: 604_800)
            return (interval.start, interval.end)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: day) ?? DateInterval(start: day, duration: 2_592_000)
            return (interval.start, interval.end)
        }
    }

    var suggestedFilenameSuffix: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        }
    }
}

/// Renders tracked activity to CSV — opens directly in Excel, Numbers, or Google
/// Sheets. Rows are grouped, not raw per-switch intervals: every visit to the same
/// (day, app, domain) is summed into one row with a total duration and visit
/// count, rather than one row per app-switch — a day of normal use can otherwise
/// produce hundreds of rows for the same handful of apps, most of them
/// near-zero-duration noise from quick switches.
enum CSVExporter {
    private struct GroupKey: Hashable {
        let date: String
        let appName: String
        let domain: String
        let type: String
    }

    private struct Accumulator {
        var totalSeconds: TimeInterval = 0
        var sessionCount: Int = 0
        var weightedScoreSum: Double = 0
        var scoreWeight: TimeInterval = 0
    }

    static func generate(range: ExportRange, anchoredOn day: Date, calendar: Calendar = .current) -> String {
        let (start, end) = range.bounds(containing: day, calendar: calendar)
        var groups: [GroupKey: Accumulator] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for interval in ActivityStore.shared.intervals(from: start, to: end) {
            let clampedStart = max(interval.startTime, start)
            let clampedEnd = min(interval.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }

            let type: String
            let domain: String
            if interval.isIdle {
                type = interval.appName == "Paused" ? "Paused" : "Idle"
                domain = ""
            } else {
                type = "Active"
                domain = interval.domain ?? ""
            }

            for (dayStart, dayEnd) in splitByDay(clampedStart, clampedEnd, calendar: calendar) {
                let seconds = dayEnd.timeIntervalSince(dayStart)
                guard seconds > 0 else { continue }
                let key = GroupKey(date: dateFormatter.string(from: dayStart), appName: interval.appName, domain: domain, type: type)
                var acc = groups[key] ?? Accumulator()
                acc.totalSeconds += seconds
                acc.sessionCount += 1
                if type == "Active", let score = ActivityStore.shared.averageActivityScore(from: dayStart, to: dayEnd) {
                    acc.weightedScoreSum += Double(score) * seconds
                    acc.scoreWeight += seconds
                }
                groups[key] = acc
            }
        }

        // Meeting sessions are logged separately (see MeetingDetector) precisely
        // because they can overlap with app_intervals — e.g. a Teams call running
        // while Chrome is the focused/tracked app. Grouped the same way, but kept
        // in their own "Meeting" type so they're never confused with focused-app time.
        for meeting in ActivityStore.shared.meetingSessions(from: start, to: end) {
            let clampedStart = max(meeting.startTime, start)
            let clampedEnd = min(meeting.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }

            for (dayStart, dayEnd) in splitByDay(clampedStart, clampedEnd, calendar: calendar) {
                let seconds = dayEnd.timeIntervalSince(dayStart)
                guard seconds > 0 else { continue }
                let key = GroupKey(date: dateFormatter.string(from: dayStart), appName: meeting.appName, domain: "", type: "Meeting")
                var acc = groups[key] ?? Accumulator()
                acc.totalSeconds += seconds
                acc.sessionCount += 1
                groups[key] = acc
            }
        }

        let typeOrder = ["Active": 0, "Meeting": 1, "Idle": 2, "Paused": 3]
        let rows = groups
            .compactMap { key, acc -> (GroupKey, Accumulator, Int)? in
                let minutes = Int((acc.totalSeconds / 60).rounded())
                guard minutes >= 1 else { return nil } // drop rows that round to 0 — noise, not signal
                return (key, acc, minutes)
            }
            .sorted { lhs, rhs in
                if lhs.0.date != rhs.0.date { return lhs.0.date < rhs.0.date }
                let lOrder = typeOrder[lhs.0.type] ?? 99
                let rOrder = typeOrder[rhs.0.type] ?? 99
                if lOrder != rOrder { return lOrder < rOrder }
                return lhs.1.totalSeconds > rhs.1.totalSeconds
            }

        var lines = ["Date,App,Domain,Type,Total Duration (min),Visits,Avg Activity Score"]
        for (key, acc, minutes) in rows {
            let avgScore = acc.scoreWeight > 0 ? String(Int((acc.weightedScoreSum / acc.scoreWeight).rounded())) : ""
            let fields = [key.date, key.appName, key.domain, key.type, String(minutes), String(acc.sessionCount), avgScore]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }

    /// Splits [start, end) into per-calendar-day sub-ranges — needed because a
    /// week/month export's intervals can span a midnight boundary (most commonly
    /// an idle stretch left running overnight), and grouping must stay within a
    /// single day for the exported rows to line up with "day" the way a
    /// spreadsheet user expects.
    private static func splitByDay(_ start: Date, _ end: Date, calendar: Calendar) -> [(Date, Date)] {
        var result: [(Date, Date)] = []
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let segmentEnd = min(end, nextDayStart)
            result.append((cursor, segmentEnd))
            cursor = segmentEnd
        }
        return result
    }

    static func suggestedFilename(range: ExportRange, anchoredOn day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "ActivityTracker_\(range.suggestedFilenameSuffix)_\(formatter.string(from: day)).csv"
    }

    /// Quotes a field if it contains a comma, quote, or newline, per RFC 4180 —
    /// domains and app names can occasionally contain commas.
    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
