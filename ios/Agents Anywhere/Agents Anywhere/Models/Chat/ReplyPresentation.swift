import Foundation

nonisolated enum ReplyPresentation {
    /// UserDefaults key: true draws new glyphs with a plain opacity fade instead
    /// of the blur-and-rise reveal.
    static let plainFadeKey = "aa.native.chat.reveal.plain-fade"
    static let revealSeconds: TimeInterval = 0.24
    /// Streamed text waits in a buffer while the previous batch reveals. The
    /// next batch is published once that reveal ends, plus one 60 Hz frame, so
    /// at most one batch animates and layout lands between animations.
    static let batchInterval: TimeInterval = revealSeconds + 1.0 / 60
    /// A published batch starts drawing after its Markdown parse and the next
    /// frame. Drawing clocks stay alive this much longer than the reveal.
    static let drawSlack: TimeInterval = 0.1
    /// `Duration` is iOS 16; the delay is carried as plain seconds instead.
    static let settleDelay: TimeInterval = revealSeconds + drawSlack
}

/// Advance deadlines independently of the work done at each one, so processing
/// time doesn't accumulate into a slower cadence. Late deadlines skip ahead.
///
/// `ContinuousClock` is iOS 16, so the clock is a monotonic uptime in seconds.
/// `DispatchTime` has nanosecond resolution and is immune to wall-clock jumps,
/// which is the property the reveal cadence depends on.
nonisolated struct ReplyFlushSchedule {
    let interval: TimeInterval
    private(set) var deadline: TimeInterval

    init(start: TimeInterval = compatUptime(), interval: TimeInterval) {
        precondition(interval > 0)
        self.interval = interval
        deadline = start + interval
    }

    mutating func advance(after now: TimeInterval = compatUptime()) {
        deadline += interval
        if deadline <= now { deadline = now + interval }
    }
}

/// Monotonic uptime in seconds, the stand-in for `ContinuousClock.now`.
@inline(__always)
func compatUptime() -> TimeInterval {
    TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}
