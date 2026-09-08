import Foundation
import ScreenCaptureKit
import AppKit
import CoreImage

/// Captures one screenshot at a random moment within each N-minute block, when enabled.
/// Off by default — this is the most sensitive feature in the app.
final class ScreenshotManager {
    private let intervalIdProvider: () -> Int64?
    private var blockTimer: DispatchSourceTimer?
    private var captureTask: Task<Void, Never>?
    private var latestScore: Int = 0
    private var hasLoggedPermissionDenial = false

    init(intervalIdProvider: @escaping () -> Int64?) {
        self.intervalIdProvider = intervalIdProvider
    }

    func noteLatestScore(_ score: Int) {
        latestScore = score
    }

    func start(intervalMinutes: Double) {
        stop()
        scheduleNextBlock(blockSeconds: max(60, intervalMinutes * 60))
        Log.info("ScreenshotManager enabled (every \(Int(intervalMinutes)) min)")
    }

    func stop() {
        blockTimer?.cancel()
        blockTimer = nil
        captureTask?.cancel()
        captureTask = nil
    }

    private func scheduleNextBlock(blockSeconds: Double) {
        let randomOffset = Double.random(in: 0..<blockSeconds)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + randomOffset)
        t.setEventHandler { [weak self] in
            self?.captureNow()
            self?.scheduleNextBlock(blockSeconds: blockSeconds)
        }
        t.resume()
        blockTimer = t
    }

    private func captureNow() {
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.showsCursor = false

                let cgImage: CGImage
                if #available(macOS 14.0, *) {
                    cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                } else {
                    return
                }

                try self.save(cgImage: cgImage)
            } catch {
                if !self.hasLoggedPermissionDenial {
                    Log.error("Screenshot capture failed (Screen Recording permission likely not granted): \(error)")
                    self.hasLoggedPermissionDenial = true
                }
            }
        }
    }

    private func save(cgImage: CGImage) throws {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
            throw NSError(domain: "ScreenshotManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }

        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "\(formatter.string(from: timestamp)).jpg"
        let fileURL = DatabaseManager.screenshotsDirectory.appendingPathComponent(filename)

        try jpegData.write(to: fileURL)

        ActivityStore.shared.recordScreenshot(
            timestamp: timestamp,
            filePath: fileURL.path,
            activityScore: latestScore,
            appIntervalId: intervalIdProvider()
        )
        Log.info("Screenshot saved: \(filename)")
    }

    deinit { stop() }
}
