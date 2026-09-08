import SwiftUI

/// A single horizontal bar spanning the selected day (00:00-24:00), broken into
/// colored segments per app interval, with hour gridlines/labels and a marker for
/// the current time when viewing today. Idle gaps render in a flat gray.
struct TimelineBarView: View {
    let intervals: [AppInterval]
    let day: Date

    private var dayBounds: (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    var body: some View {
        GeometryReader { geo in
            let (dayStart, dayEnd) = dayBounds
            let totalSeconds = dayEnd.timeIntervalSince(dayStart)
            let barHeight: CGFloat = 34

            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.radiusSmall).fill(Color.gray.opacity(0.12))

                    ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                        let clampedStart = max(interval.startTime, dayStart)
                        let clampedEnd = min(interval.endTime ?? Date(), dayEnd)
                        let width = max(0, clampedEnd.timeIntervalSince(clampedStart) / totalSeconds) * geo.size.width
                        let x = (clampedStart.timeIntervalSince(dayStart) / totalSeconds) * geo.size.width

                        Rectangle()
                            .fill(interval.isIdle ? Color.gray.opacity(0.45) : colorForName(interval.appName))
                            .frame(width: max(1, width))
                            .position(x: x + width / 2, y: barHeight / 2)
                            .help("\(interval.appName)\(interval.isIdle ? " (idle)" : "")")
                    }

                    // Hour gridlines every 3 hours.
                    ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                        let x = (Double(hour) * 3600 / totalSeconds) * geo.size.width
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1, height: barHeight)
                            .position(x: x, y: barHeight / 2)
                    }

                    if Calendar.current.isDateInToday(day) {
                        let nowOffset = Date().timeIntervalSince(dayStart)
                        if nowOffset >= 0, nowOffset <= totalSeconds {
                            let x = (nowOffset / totalSeconds) * geo.size.width
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 1.5, height: barHeight + 6)
                                .position(x: x, y: barHeight / 2)
                        }
                    }
                }
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))

                HStack {
                    ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                        Text(hourLabel(hour))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        if hour < 24 { Spacer() }
                    }
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12am" }
        if h == 12 { return "12pm" }
        return h < 12 ? "\(h)am" : "\(h - 12)pm"
    }
}
