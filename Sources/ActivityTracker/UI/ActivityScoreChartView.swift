import SwiftUI
import Charts

struct ActivityScoreChartView: View {
    let scores: [ActivityScore]
    let day: Date

    private var average: Int {
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0) { $0 + $1.score } / scores.count
    }

    var body: some View {
        if scores.isEmpty {
            Text("No activity-score data yet for this day.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(scores) { score in
                    AreaMark(
                        x: .value("Time", score.minuteTimestamp),
                        y: .value("Score", score.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", score.minuteTimestamp),
                        y: .value("Score", score.score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                }

                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(average)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour())
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
        }
    }
}
