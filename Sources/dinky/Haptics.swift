import AppKit
import DinkyPrivate

/// A tap of the trackpad as a switcher's pick moves or a strip's column passes under the fingers. dinky is never the active app, which the public performer
/// needs, so the trackpad's actuator directly, and the public performer only where that is missing. Logged with
/// `why`, as `haptic: …`, so a tap felt can be told from the trackpad's own.
func tapTrackpad(_ why: String) {
    // Actuation 4, as a bound swipe's: 3 returns success on a MacBook's built-in Force Touch trackpad but is not felt.
    let tapped = dinky_trackpad_tap(4)
    if !tapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    print("\(stamp()) haptic: \(why)" + (tapped ? "" : ", no actuator: through NSHapticFeedbackManager"))
    fflush(stdout)
}
