import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @State private var selectedDay: Date = Date()
    @State private var intervals: [AppInterval] = []
    @State private var appSummary: [AppTimeSummary] = []
    @State private var domainSummary: [DomainTimeSummary] = []
    @State private var activityScores: [ActivityScore] = []
    @State private var screenshots: [Screenshot] = []
    @State private var meetingSessions: [MeetingSession] = []
    @ObservedObject private var settings = AppSettings.shared

    private let store = ActivityStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.spacingLarge)
                .padding(.vertical, DS.spacing)
                .background(.thinMaterial)
                .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacingLarge) {
                    statRow

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Timeline", systemImage: "chart.bar.doc.horizontal")
                        TimelineBarView(intervals: intervals, meetingSessions: meetingSessions, day: selectedDay)
                            .frame(height: meetingSessions.isEmpty ? 64 : 78)
                            .card()
                    }

                    HStack(alignment: .top, spacing: DS.spacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Time per App", systemImage: "app.badge")
                            AppBreakdownView(summary: appSummary)
                                .card()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Time per Domain", systemImage: "globe")
                            DomainBreakdownView(summary: domainSummary)
                                .card()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Activity Score", systemImage: "waveform.path.ecg")
                        ActivityScoreChartView(scores: activityScores, day: selectedDay)
                            .frame(height: 200)
                            .card()
                    }

                    if settings.screenshotsEnabled || !screenshots.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Screenshots", systemImage: "photo.on.rectangle")
                            ScreenshotStripView(screenshots: screenshots)
                                .card()
                        }
                    }
                }
                .padding(DS.spacingLarge)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 940, minHeight: 700)
        .onAppear { reload() }
        .onChange(of: selectedDay) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardShouldRefresh)) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack(spacing: DS.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity Dashboard")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(selectedDay.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                DatePicker("", selection: $selectedDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Button { shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(Calendar.current.isDateInToday(selectedDay))
            }
            Button {
                selectedDay = Date()
            } label: {
                Text("Today")
            }
            .buttonStyle(.bordered)
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh")

            Menu {
                ForEach(ExportRange.allCases) { range in
                    Button("Export \(range.rawValue) as CSV…") {
                        exportCSV(range: range)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
    }

    /// Generates the CSV in memory, then hands the save location decision to the
    /// user via a standard save panel — the file only gets written where they
    /// explicitly choose to put it.
    private func exportCSV(range: ExportRange) {
        let csv = CSVExporter.generate(range: range, anchoredOn: selectedDay)

        let panel = NSSavePanel()
        panel.title = "Export Activity Data"
        panel.nameFieldStringValue = CSVExporter.suggestedFilename(range: range, anchoredOn: selectedDay)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                Log.info("Exported CSV to \(url.path)")
            } catch {
                Log.error("CSV export failed: \(error)")
            }
        }
    }

    private var statRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.spacing)], spacing: DS.spacing) {
            StatTile(
                title: "Tracked Time",
                value: formatDuration(appSummary.reduce(0) { $0 + $1.totalSeconds }),
                systemImage: "clock.fill",
                tint: .blue
            )
            StatTile(
                title: "Idle Time",
                value: formatDuration(idleSeconds),
                systemImage: "moon.zzz.fill",
                tint: .orange
            )
            StatTile(
                title: "Top App",
                value: appSummary.first?.appName ?? "—",
                systemImage: "star.fill",
                tint: .purple
            )
            StatTile(
                title: "Avg. Activity",
                value: activeActivityScores.isEmpty ? "—" : "\(averageScore)",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: .green
            )
            if !meetingSessions.isEmpty {
                StatTile(
                    title: "Meeting Time",
                    value: formatDuration(meetingSeconds),
                    systemImage: "video.fill",
                    tint: .pink
                )
            }
        }
    }

    /// Meeting time is tracked separately from — and can overlap with — Tracked
    /// Time, since a call can run in the background while you're focused on a
    /// different app (see MeetingDetector). It deliberately isn't subtracted from
    /// or added into Tracked Time; the two answer different questions.
    private var meetingSeconds: TimeInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDay)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return meetingSessions.reduce(0) { total, session in
            let clampedStart = max(session.startTime, start)
            let clampedEnd = min(session.endTime ?? Date(), end)
            return total + max(0, clampedEnd.timeIntervalSince(clampedStart))
        }
    }

    /// Idle time doesn't count toward "Tracked Time" (see
    /// `ActivityStore.appTimeSummary`, which excludes `isIdle` rows entirely) —
    /// shown as its own tile so it's visible at a glance how much of the day the
    /// app detected as inactivity. Pausing, unlike idle, isn't tracked at all —
    /// it's a deliberate choice not to be measured, so it leaves a plain gap in
    /// the data rather than its own category (see TrackingCoordinator.togglePause).
    private var idleSeconds: TimeInterval { nonTrackedSeconds(matching: "Idle") }

    private func nonTrackedSeconds(matching appName: String) -> TimeInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDay)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return intervals
            .filter { $0.isIdle && $0.appName == appName }
            .reduce(0) { total, interval in
                let clampedStart = max(interval.startTime, start)
                let clampedEnd = min(interval.endTime ?? Date(), end)
                return total + max(0, clampedEnd.timeIntervalSince(clampedStart))
            }
    }

    /// Activity-score minutes tied to an idle interval always score 0 (there's no
    /// input by definition while idle) — including them would make "Avg. Activity"
    /// measure how much of the day you were away rather than how active you were
    /// while actually working, which only gets worse the more time you spend away
    /// from the keyboard regardless of how intensely you work when you're at it.
    private var activeActivityScores: [ActivityScore] {
        let idleIntervalIDs = Set(intervals.filter { $0.isIdle }.compactMap { $0.id })
        return activityScores.filter { score in
            guard let id = score.appIntervalId else { return true }
            return !idleIntervalIDs.contains(id)
        }
    }

    private var averageScore: Int {
        guard !activeActivityScores.isEmpty else { return 0 }
        return activeActivityScores.reduce(0) { $0 + $1.score } / activeActivityScores.count
    }

    private func shiftDay(by delta: Int) {
        if let newDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = min(newDay, Date())
        }
    }

    private func reload() {
        Log.info("Dashboard reload (day: \(selectedDay.formatted(date: .abbreviated, time: .omitted)))")
        intervals = store.intervals(on: selectedDay)
        appSummary = store.appTimeSummary(on: selectedDay)
        domainSummary = store.domainTimeSummary(on: selectedDay)
        activityScores = store.activityScores(on: selectedDay)
        screenshots = store.screenshots(on: selectedDay)
        meetingSessions = store.meetingSessions(on: selectedDay)
    }
}

// MARK: - Helpers

func formatDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds) / 60
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

/// Deterministic-ish color per app/domain name so the same name always renders the
/// same color across the timeline and the breakdown charts.
func colorForName(_ name: String) -> Color {
    var hasher = Hashher()
    hasher.combine(name)
    let hue = Double(hasher.value % 360) / 360.0
    return Color(hue: hue, saturation: 0.55, brightness: 0.85)
}

/// Tiny stable string hash (avoids relying on Swift's randomized Hasher across runs
/// within the same process — this doesn't need cryptographic quality, just stability).
struct Hashher {
    var value: Int = 0
    mutating func combine(_ string: String) {
        for scalar in string.unicodeScalars {
            value = (value &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
    }
}
