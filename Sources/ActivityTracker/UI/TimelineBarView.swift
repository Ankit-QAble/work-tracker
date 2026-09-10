import SwiftUI

/// A single horizontal bar spanning a configurable hour window of the selected day
/// (default 9am-11pm, see AppSettings.timelineStartHour/EndHour) — broken into
/// colored segments per app interval, with hourly gridlines/labels, a marker for
/// the current time when viewing today, and a legend identifying each color.
/// Idle gaps render in gray. Meeting sessions render as a thin separate strip
/// above the main bar, since they can overlap with it (a meeting can run while a
/// different app is the one actually being tracked below).
struct TimelineBarView: View {
    let intervals: [AppInterval]
    var meetingSessions: [MeetingSession] = []
    let day: Date

    @ObservedObject private var settings = AppSettings.shared

    private var windowBounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let start = cal.date(byAdding: .hour, value: Int(settings.timelineStartHour), to: dayStart)!
        let end = cal.date(byAdding: .hour, value: Int(settings.timelineEndHour) + 1, to: dayStart)!
        return (start, end)
    }

    private var hourStep: Int {
        let range = Int(settings.timelineEndHour) - Int(settings.timelineStartHour) + 1
        return range > 16 ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let (windowStart, windowEnd) = windowBounds
                let totalSeconds = windowEnd.timeIntervalSince(windowStart)
                let barHeight: CGFloat = 46
                let meetingBarHeight: CGFloat = 10

                VStack(alignment: .leading, spacing: 4) {
                    if !meetingSessions.isEmpty {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.08))
                            ForEach(Array(meetingSessions.enumerated()), id: \.offset) { _, session in
                                let clampedStart = max(session.startTime, windowStart)
                                let clampedEnd = min(session.endTime ?? Date(), windowEnd)
                                if clampedEnd > clampedStart {
                                    let width = (clampedEnd.timeIntervalSince(clampedStart) / totalSeconds) * geo.size.width
                                    let x = (clampedStart.timeIntervalSince(windowStart) / totalSeconds) * geo.size.width

                                    Rectangle()
                                        .fill(Color.pink.opacity(0.75))
                                        .frame(width: max(1, width))
                                        .position(x: x + width / 2, y: meetingBarHeight / 2)
                                        .help("\(session.appName) meeting: \(timeRangeLabel(clampedStart, clampedEnd))")
                                }
                            }
                        }
                        .frame(height: meetingBarHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DS.radiusSmall).fill(Color.gray.opacity(0.12))

                        ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                            let clampedStart = max(interval.startTime, windowStart)
                            let clampedEnd = min(interval.endTime ?? Date(), windowEnd)
                            if clampedEnd > clampedStart {
                                let width = (clampedEnd.timeIntervalSince(clampedStart) / totalSeconds) * geo.size.width
                                let x = (clampedStart.timeIntervalSince(windowStart) / totalSeconds) * geo.size.width

                                Rectangle()
                                    .fill(colorFor(interval))
                                    .frame(width: max(1, width))
                                    .position(x: x + width / 2, y: barHeight / 2)
                                    .help("\(interval.appName) — \(timeRangeLabel(clampedStart, clampedEnd))")
                            }
                        }

                        ForEach(hourTicks, id: \.self) { hour in
                            let x = tickX(hour: hour, windowStart: windowStart, totalSeconds: totalSeconds, width: geo.size.width)
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 1, height: barHeight)
                                .position(x: x, y: barHeight / 2)
                        }

                        if Calendar.current.isDateInToday(day) {
                            let now = Date()
                            if now >= windowStart, now <= windowEnd {
                                let x = (now.timeIntervalSince(windowStart) / totalSeconds) * geo.size.width
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 1.5, height: barHeight + 6)
                                    .position(x: x, y: barHeight / 2)
                            }
                        }
                    }
                    .frame(height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))

                    ZStack(alignment: .topLeading) {
                        ForEach(hourTicks, id: \.self) { hour in
                            let x = tickX(hour: hour, windowStart: windowStart, totalSeconds: totalSeconds, width: geo.size.width)
                            Text(hourLabel(hour))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(x: min(max(x, 14), geo.size.width - 14), y: 6)
                        }
                    }
                    .frame(height: 14)
                }
            }
            .frame(height: meetingSessions.isEmpty ? 66 : 80)

            legend
        }
    }

    /// Which hours to draw a tick/label at — includes the window's start and end
    /// hours explicitly (so the bar's edges are always labeled) plus every
    /// `hourStep` hours in between.
    private var hourTicks: [Int] {
        let start = Int(settings.timelineStartHour)
        let end = Int(settings.timelineEndHour) + 1
        var hours = Array(stride(from: start, through: end, by: hourStep))
        if hours.last != end { hours.append(end) }
        return hours
    }

    private func tickX(hour: Int, windowStart: Date, totalSeconds: TimeInterval, width: CGFloat) -> CGFloat {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let tickDate = cal.date(byAdding: .hour, value: hour, to: dayStart)!
        return (tickDate.timeIntervalSince(windowStart) / totalSeconds) * width
    }

    /// Color swatches for the apps actually visible in this window, ranked by how
    /// much time they took up — without this, the timeline's colors are only
    /// decodable one segment at a time via hover, which is exactly what made it
    /// hard to read at a glance.
    private var legend: some View {
        let (windowStart, windowEnd) = windowBounds
        var totals: [String: TimeInterval] = [:]
        for interval in intervals where !interval.isIdle {
            let clampedStart = max(interval.startTime, windowStart)
            let clampedEnd = min(interval.endTime ?? Date(), windowEnd)
            guard clampedEnd > clampedStart else { continue }
            totals[interval.appName, default: 0] += clampedEnd.timeIntervalSince(clampedStart)
        }
        let ranked = totals.sorted { $0.value > $1.value }
        let shown = ranked.prefix(8)
        let remainder = ranked.count - shown.count

        return Group {
            if !shown.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(shown), id: \.key) { name, _ in
                        HStack(spacing: 5) {
                            Circle().fill(colorForName(name)).frame(width: 7, height: 7)
                            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if remainder > 0 {
                        Text("+\(remainder) more").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        Text("Idle").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Idle time renders as gray (excluded from time-per-app totals) — see
    /// `colorForName` for how active apps get their colors.
    private func colorFor(_ interval: AppInterval) -> Color {
        guard interval.isIdle else { return colorForName(interval.appName) }
        return Color.gray.opacity(0.5)
    }

    private func timeRangeLabel(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if h == 0 { return "12am" }
        if h == 12 { return "12pm" }
        return h < 12 ? "\(h)am" : "\(h - 12)pm"
    }
}
