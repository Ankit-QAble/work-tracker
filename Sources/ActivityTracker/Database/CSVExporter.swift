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

/// Renders tracked activity intervals to CSV — opens directly in Excel, Numbers, or
/// Google Sheets. One row per app interval (the same granularity stored in the DB),
/// clamped to the export range, with a per-interval average activity score.
enum CSVExporter {
    static func generate(range: ExportRange, anchoredOn day: Date, calendar: Calendar = .current) -> String {
        let (start, end) = range.bounds(containing: day, calendar: calendar)
        let intervals = ActivityStore.shared.intervals(from: start, to: end)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        var lines = ["Date,Start Time,End Time,Duration (min),App,Window Title,URL,Domain,Type,Avg Activity Score"]

        for interval in intervals {
            let clampedStart = max(interval.startTime, start)
            let clampedEnd = min(interval.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }

            let durationMinutes = Int((clampedEnd.timeIntervalSince(clampedStart) / 60).rounded())
            let avgScore = ActivityStore.shared.averageActivityScore(from: clampedStart, to: clampedEnd)

            let fields = [
                dateFormatter.string(from: clampedStart),
                timeFormatter.string(from: clampedStart),
                timeFormatter.string(from: clampedEnd),
                String(durationMinutes),
                interval.appName,
                interval.windowTitle ?? "",
                interval.url ?? "",
                interval.domain ?? "",
                interval.isIdle ? "Idle" : "Active",
                avgScore.map(String.init) ?? ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        // Meeting sessions are logged separately (see MeetingDetector) precisely
        // because they can overlap with app_intervals — e.g. a Teams call running
        // while Chrome is the focused/tracked app. Rows here will legitimately
        // overlap in time with rows above; that's intentional, not a duplicate.
        let meetings = ActivityStore.shared.meetingSessions(from: start, to: end)
        for meeting in meetings {
            let clampedStart = max(meeting.startTime, start)
            let clampedEnd = min(meeting.endTime ?? Date(), end)
            guard clampedEnd > clampedStart else { continue }

            let durationMinutes = Int((clampedEnd.timeIntervalSince(clampedStart) / 60).rounded())
            let fields = [
                dateFormatter.string(from: clampedStart),
                timeFormatter.string(from: clampedStart),
                timeFormatter.string(from: clampedEnd),
                String(durationMinutes),
                meeting.appName,
                "", "", "",
                "Meeting",
                ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }

    static func suggestedFilename(range: ExportRange, anchoredOn day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "ActivityTracker_\(range.suggestedFilenameSuffix)_\(formatter.string(from: day)).csv"
    }

    /// Quotes a field if it contains a comma, quote, or newline, per RFC 4180 —
    /// window titles and URLs routinely contain commas.
    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
