import AppKit
import DinkyPrivate

/// A tap of the trackpad, as strong as `actuation` (see `HapticStrength`): as a switcher's pick moves, a bound swipe runs or a strip's column passes under the fingers. dinky is never the active app, which the public performer
/// needs, so the trackpad's actuator directly, and the public performer only where that is missing. Logged with
/// `why`, as `haptic: …`, so a tap felt can be told from the trackpad's own.
func tapTrackpad(_ why: String, actuation: Int32) {
    let tapped = dinky_trackpad_tap(actuation)
    if !tapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    print("\(stamp()) haptic: \(why), actuation \(actuation)" + (tapped ? "" : ", no actuator: through NSHapticFeedbackManager"))
    fflush(stdout)
}
