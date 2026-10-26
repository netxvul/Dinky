import AppKit
import DinkyPrivate

/// A tap of the trackpad, light (`actuation` 3) as a switcher's pick moves, or as strong as asked. dinky is never the active app, which the public performer
/// needs, so the trackpad's actuator directly, and the public performer only where that is missing. Logged with
/// `why`, as `haptic: …`, so a tap felt can be told from the trackpad's own.
func tapTrackpad(_ why: String, actuation: Int32 = 3) {
    let tapped = dinky_trackpad_tap(actuation)
    if !tapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    print("\(stamp()) haptic: \(why), actuation \(actuation)" + (tapped ? "" : ", no actuator: through NSHapticFeedbackManager"))
    fflush(stdout)
}
