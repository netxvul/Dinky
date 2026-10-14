import AppKit
import DinkyPrivate

/// A light tap of the trackpad as a switcher's pick moves. dinky is never the active app, which the public performer
/// needs, so the trackpad's actuator directly, and the public performer only where that is missing.
func tapTrackpad() {
    if !dinky_trackpad_tap(3) { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
}
