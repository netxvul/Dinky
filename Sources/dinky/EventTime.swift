import CoreGraphics
import QuartzCore

/// When `event` happened, in `CACurrentMediaTime` seconds: its own timestamp, not when it got here. An event that
/// came through the session carries nanoseconds since startup, measured as `CACurrentMediaTime` is (seen on macOS 27,
/// where the host's ticks are not nanoseconds); one made here and never posted carries none, and is taken as now.
func eventTime(_ event: CGEvent) -> CFTimeInterval {
    event.timestamp == 0 ? CACurrentMediaTime() : CFTimeInterval(event.timestamp) / 1_000_000_000
}

/// How long ago `event` happened.
func eventAge(_ event: CGEvent) -> CFTimeInterval {
    CACurrentMediaTime() - eventTime(event)
}
