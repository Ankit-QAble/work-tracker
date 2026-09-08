import SwiftUI
import AppKit

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case screenshots = "Screenshots"
    case excludedApps = "Excluded Apps"
    case permissions = "Permissions"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .screenshots: return "camera.viewfinder"
        case .excludedApps: return "eye.slash"
        case .permissions: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(170)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacing) {
                    switch selection ?? .general {
                    case .general: GeneralSettingsPane()
                    case .screenshots: ScreenshotSettingsPane()
                    case .excludedApps: ExcludedAppsPane()
                    case .permissions: PermissionsPane()
                    }
                }
                .padding(DS.spacingLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection?.rawValue ?? "Settings")
        }
        .frame(width: 620, height: 460)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Idle Detection", systemImage: "moon.zzz")
            VStack(alignment: .leading, spacing: 10) {
                Text("Tracking auto-pauses after this much time with no keyboard/mouse activity, and logs the gap as idle time.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: $settings.idleThresholdSeconds, in: 30...900, step: 30)
                    Text(formatDuration(settings.idleThresholdSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .card()

            SectionHeader(title: "Idle Resume Prompt", systemImage: "arrow.uturn.backward.circle")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Ask when I return from a long idle stretch", isOn: $settings.idlePromptEnabled)
                    .toggleStyle(.switch)
                Text("If you've been idle longer than this, a small popup asks whether to count that time as work (attributed to whatever app you were in before) or leave it as idle. Ignoring it defaults to idle — nothing changes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: $settings.idlePromptThresholdSeconds, in: 60...1800, step: 60)
                        .disabled(!settings.idlePromptEnabled)
                    Text(formatDuration(settings.idlePromptThresholdSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .card()
        }
    }
}

private struct ScreenshotSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Periodic Screenshots", systemImage: "camera.viewfinder")
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Capture periodic screenshots", isOn: Binding(
                    get: { settings.screenshotsEnabled },
                    set: { newValue in
                        settings.screenshotsEnabled = newValue
                        TrackingCoordinator.shared.applyScreenshotSetting()
                    }
                ))
                .toggleStyle(.switch)

                Text("Off by default — this is the most sensitive feature. When on, one screenshot is captured at a random moment within each interval below and saved locally under ~/Library/Application Support/ActivityTracker/screenshots/. Nothing is ever uploaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Every")
                        .font(.system(size: 12))
                    Slider(value: Binding(
                        get: { settings.screenshotIntervalMinutes },
                        set: { newValue in
                            settings.screenshotIntervalMinutes = newValue
                            if settings.screenshotsEnabled {
                                TrackingCoordinator.shared.applyScreenshotSetting()
                            }
                        }
                    ), in: 1...60, step: 1)
                    .disabled(!settings.screenshotsEnabled)
                    Text("\(Int(settings.screenshotIntervalMinutes)) min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .card()
        }
    }
}

private struct ExcludedAppsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newExcludedApp: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Never Track These Apps", systemImage: "eye.slash")
            VStack(alignment: .leading, spacing: 12) {
                Text("Apps listed here are never tracked — no time interval, window title, URL, or screenshot is recorded while they're frontmost.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("App name (e.g. 1Password)", text: $newExcludedApp)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addExcludedApp)
                    Button("Add", action: addExcludedApp)
                        .disabled(newExcludedApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if settings.excludedApps.isEmpty {
                    Text("No apps excluded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.excludedApps.enumerated()), id: \.element) { index, app in
                            if index > 0 { Divider() }
                            HStack {
                                Image(systemName: "app.dashed").foregroundStyle(.secondary)
                                Text(app).font(.system(size: 12))
                                Spacer()
                                Button {
                                    settings.excludedApps.removeAll { $0 == app }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func addExcludedApp() {
        let trimmed = newExcludedApp.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.excludedApps.contains(trimmed) else { return }
        settings.excludedApps.append(trimmed)
        newExcludedApp = ""
    }
}

private struct PermissionsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "System Permissions", systemImage: "lock.shield")
            VStack(alignment: .leading, spacing: 14) {
                Text("Each feature below needs a one-time grant in System Settings. If something isn't tracking, check here first.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                PermissionRow(icon: "accessibility", name: "Accessibility", detail: "Window titles for non-browser apps")
                PermissionRow(icon: "keyboard", name: "Input Monitoring", detail: "Per-minute activity score")
                PermissionRow(icon: "safari", name: "Automation (Chrome)", detail: "Browser tab URL & title")
                PermissionRow(icon: "camera", name: "Screen Recording", detail: "Optional periodic screenshots")

                Button("Open Privacy & Security Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.top, 4)
            }
            .card()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
