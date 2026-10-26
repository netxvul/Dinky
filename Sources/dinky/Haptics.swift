import AppKit
import DinkyPrivate

/// A light tap of the trackpad as a switcher's pick moves. dinky is never the active app, which the public performer
/// needs, so the trackpad's actuator directly, and the public performer only where that is missing. Logged with
/// `why`, as `haptic: …`, so a tap felt can be told from the trackpad's own.
func tapTrackpad(_ why: String) {
    let tapped = dinky_trackpad_tap(3)
    if !tapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    print("\(stamp()) haptic: \(why)" + (tapped ? "" : ", no actuator: through NSHapticFeedbackManager"))
    fflush(stdout)
}
