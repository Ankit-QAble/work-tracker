import Foundation
import CoreGraphics

/// Listens for keyboard/mouse *events* via a CGEventTap and turns them into a 0-100
/// "activity score" per 60-second window. Only event counts are ever touched — key
/// codes, characters, and click targets are never read or stored.
final class ActivityScoreTracker {
    /// (minuteStart, eventCount, score)
    private let onMinuteFinished: (Date, Int, Int) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var minuteTimer: DispatchSourceTimer?

    private var currentMinuteStart: Date
    private var eventCount: Int = 0
    private var hasLoggedPermissionDenial = false

    /// Timestamp of the most recent raw input event seen by the tap. Exposed so
    /// IdleMonitor can use it as a second, independent idle signal alongside
    /// CGEventSource — on some setups (e.g. certain remote-input/virtualization
    /// paths) events reliably reach an active CGEventTap without ever updating
    /// CGEventSourceSecondsSinceLastEventType, which otherwise reports permanently
    /// stale idle time despite genuine, continuous input.
    private(set) var lastEventDate = Date()

    func secondsSinceLastEvent() -> TimeInterval {
        Date().timeIntervalSince(lastEventDate)
    }

    /// Events/minute considered "fully active" (100). Tunable normalization curve —
    /// typical sustained typing + mouse use lands well under this, so 100 is rare
    /// by design; it's a ceiling, not an average.
    private let maxEventsPerMinuteForFullScore = 600

    init(onMinuteFinished: @escaping (Date, Int, Int) -> Void) {
        self.onMinuteFinished = onMinuteFinished
        self.currentMinuteStart = Self.flooredToMinute(Date())
    }

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon in
                if let refcon {
                    let tracker = Unmanaged<ActivityScoreTracker>.fromOpaque(refcon).takeUnretainedValue()
                    tracker.eventCount += 1
                    tracker.lastEventDate = Date()
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        ) else {
            if !hasLoggedPermissionDenial {
                Log.error("Failed to create CGEventTap — Input Monitoring permission likely not granted. Grant it in System Settings > Privacy & Security > Input Monitoring.")
                hasLoggedPermissionDenial = true
            }
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        startMinuteTimer()
        startDiagTimer()
        Log.info("ActivityScoreTracker started")
    }

    private var diagTimer: DispatchSourceTimer?

    /// Short-interval diagnostic separate from the once-a-minute score row — lets us
    /// confirm the tap is actually receiving events in near-real-time while debugging,
    /// without waiting for a full minute boundary.
    private func startDiagTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Log.info("eventTap diag: runningEventCountThisMinute=\(self.eventCount)")
        }
        t.resume()
        diagTimer = t
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        minuteTimer?.cancel()
        minuteTimer = nil
        diagTimer?.cancel()
        diagTimer = nil
    }

    private func startMinuteTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Align roughly to the top of the minute, then fire every 60s.
        let now = Date()
        let nextMinute = Self.flooredToMinute(now).addingTimeInterval(60)
        t.schedule(deadline: .now() + nextMinute.timeIntervalSince(now), repeating: 60)
        t.setEventHandler { [weak self] in self?.finishMinute() }
        t.resume()
        minuteTimer = t
    }

    private func finishMinute() {
        let count = eventCount
        eventCount = 0
        let score = Self.normalize(eventCount: count, maxForFullScore: maxEventsPerMinuteForFullScore)
        let minute = currentMinuteStart
        currentMinuteStart = Self.flooredToMinute(Date())
        onMinuteFinished(minute, count, score)
    }

    private static func normalize(eventCount: Int, maxForFullScore: Int) -> Int {
        guard maxForFullScore > 0 else { return 0 }
        let ratio = Double(eventCount) / Double(maxForFullScore)
        return max(0, min(100, Int((ratio * 100).rounded())))
    }

    private static func flooredToMinute(_ date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (interval / 60).rounded(.down) * 60)
    }

    deinit { stop() }
}
