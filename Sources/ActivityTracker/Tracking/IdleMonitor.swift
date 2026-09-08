import Foundation
import CoreGraphics
import ApplicationServices

/// Polls system-wide idle time and fires a callback when crossing the idle threshold
/// in either direction. No polling of keystrokes/content — just "how long since the
/// last HID event".
///
/// Primary signal is CGEventSource (the standard, permission-free API for this).
/// It's combined with an optional supplementary signal — in practice, the timestamp
/// of the last event seen by ActivityScoreTracker's CGEventTap — because on some
/// setups (observed on at least one real machine during development: certain
/// remote-input/virtualization input paths) genuine, continuous input reliably
/// reaches an active CGEventTap while CGEventSourceSecondsSinceLastEventType stays
/// permanently stale. Taking whichever signal shows more recent activity keeps idle
/// detection correct in both the normal case and that one.
final class IdleMonitor {
    private let thresholdProvider: () -> Double
    private let onIdleChanged: (Bool) -> Void
    private let supplementaryIdleSecondsProvider: (() -> Double?)?
    private var timer: DispatchSourceTimer?
    private(set) var isIdle = false

    private let pollInterval: TimeInterval = 2.0

    init(
        thresholdProvider: @escaping () -> Double,
        onIdleChanged: @escaping (Bool) -> Void,
        supplementaryIdleSecondsProvider: (() -> Double?)? = nil
    ) {
        self.thresholdProvider = thresholdProvider
        self.onIdleChanged = onIdleChanged
        self.supplementaryIdleSecondsProvider = supplementaryIdleSecondsProvider
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()
        timer = t
        Log.info("IdleMonitor started (threshold \(Int(thresholdProvider()))s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let cgEventSourceIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        var idleSeconds = cgEventSourceIdle
        if let supplemental = supplementaryIdleSecondsProvider?() {
            idleSeconds = min(idleSeconds, supplemental)
        }
        let threshold = thresholdProvider()
        let nowIdle = idleSeconds >= threshold

        if nowIdle != isIdle {
            isIdle = nowIdle
            Log.info(nowIdle ? "Went idle after \(Int(idleSeconds))s" : "Resumed from idle")
            onIdleChanged(nowIdle)
        }
    }

    deinit { stop() }
}
