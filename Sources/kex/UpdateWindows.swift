import AppKit
import Sparkle

// Sparkle's windows, as "A new version of Kex is available", belong to kex, which tiles no window of its own and, an
// agent app, is not brought forward when one opens: the windows kex raises into order went over it, and a tiled window
// could cover half of it. So each of them floats above the tiled windows, in the middle of its display, and kex is
// activated for it to take the keyboard.
final class UpdateWindows: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        bringForward()
    }

    func standardUserDriverDidShowModalAlert() {
        bringForward()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        bringForward()
    }

    /// Sparkle shows its window just after telling of it, so again a moment later, once it is on screen.
    private func bringForward() {
        for delay in [0.0, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.floatSparkleWindows() }
        }
    }

    private static func floatSparkleWindows() {
        let windows = NSApp.windows.filter { $0.isVisible && isSparkle($0) }
        guard !windows.isEmpty else { return }
        for window in windows where window.level.rawValue < NSWindow.Level.floating.rawValue {
            window.level = .floating
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.last?.makeKeyAndOrderFront(nil)
    }

    /// One of Sparkle's windows: its update alert, its progress, or an alert it shows. Kex's own overlays (borders, the
    /// HUD, the switchers) are none of these.
    private static func isSparkle(_ window: NSWindow) -> Bool {
        let owners = [window.windowController.map { String(describing: type(of: $0)) }, String(describing: type(of: window))]
        return owners.compactMap { $0 }.contains { $0.hasPrefix("SU") || $0.hasPrefix("SPU") || $0.contains("AlertPanel") }
    }
}
