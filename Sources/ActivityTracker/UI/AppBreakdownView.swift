import SwiftUI

struct AppBreakdownView: View {
    let summary: [AppTimeSummary]

    var body: some View {
        RankedBreakdownList(
            rows: summary.prefix(8).map { RankedRow(id: $0.appName, name: $0.appName, seconds: $0.totalSeconds) },
            emptyText: "No data yet for this day."
        )
    }
}

struct DomainBreakdownView: View {
    let summary: [DomainTimeSummary]

    var body: some View {
        RankedBreakdownList(
            rows: summary.prefix(8).map { RankedRow(id: $0.domain, name: $0.domain, seconds: $0.totalSeconds) },
            emptyText: "No browser activity yet for this day."
        )
    }
}

private struct RankedRow: Identifiable {
    let id: String
    let name: String
    let seconds: TimeInterval
}

/// Shared rendering for "time per X" lists: a color swatch, name, proportional bar
/// (relative to the largest item), and formatted duration — reads cleanly at a
/// glance and scales better than a generic bar chart for 5-10 items.
private struct RankedBreakdownList: View {
    let rows: [RankedRow]
    let emptyText: String

    private var maxSeconds: TimeInterval {
        rows.map(\.seconds).max() ?? 1
    }

    var body: some View {
        if rows.isEmpty {
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(colorForName(row.name))
                            .frame(width: 8, height: 8)

                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colorForName(row.name))
                                    .frame(width: max(3, geo.size.width * (row.seconds / maxSeconds)))
                            }
                        }
                        .frame(height: 6)

                        Text(formatDuration(row.seconds))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }
}
