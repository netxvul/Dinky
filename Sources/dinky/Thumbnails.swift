import AppKit
import DinkyLayout
import DinkyPrivate
import ScreenCaptureKit

// Window thumbnails for the switcher, kept per window so the capsule draws at once and fresh captures
// fade in. ScreenCaptureKit captures a window's own backing, so a column parked off screen or under another column
// comes out whole. Capturing needs Screen Recording, asked for once per run, the first time the switcher shows;
// without it there are no thumbnails and the capsule shows app icons. Main thread only.
final class Thumbnails {
    static let shared = Thumbnails()

    /// Points tall the images are captured at, before the backing scale, when the caller does not say: the row's
    /// thumbnail, with room for its pick to grow.
    private static let height = SwitcherLayout.thumbHeight * 1.1

    /// How long `refreshSoon` waits for asks to stop before it captures.
    private static let quiet: TimeInterval = 0.6

    private var images: [WindowID: CGImage] = [:]
    private var asked = false
    private var observing = false
    /// The windows `refreshSoon` was asked for, at the scale asked last, and its wait.
    private var soon: Set<WindowID> = []
    private var soonScale: CGFloat = 2
    private var soonWork: DispatchWorkItem?

    func image(of id: WindowID) -> CGImage? { images[id] }

    /// Whether dinky may capture other apps' windows.
    var permitted: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for Screen Recording the first time in a run that thumbnails are wanted without it. macOS shows its
    /// prompt once; after that the grant is made in System Settings.
    func askOnce() {
        guard !asked, !permitted else { return }
        asked = true
        CGRequestScreenCaptureAccess()
    }

    /// Captures `ids` afresh and calls `done` on the main thread with each as it lands. Windows ScreenCaptureKit does
    /// not list are skipped.
    func refresh(_ ids: [WindowID], height points: CGFloat = height, scale: CGFloat,
                 done: @escaping (WindowID, CGImage) -> Void) {
        guard permitted, !ids.isEmpty else { return }
        observeClosing()
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            let wanted = Set(ids)
            for window in content.windows where wanted.contains(window.windowID) {
                let id = window.windowID, frame = window.frame
                guard frame.width > 1, frame.height > 1 else { continue }
                let configuration = SCStreamConfiguration()
                let height = points * scale
                configuration.height = Int(height)
                configuration.width = Int(height * frame.width / frame.height)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.scalesToFit = true
                let filter = SCContentFilter(desktopIndependentWindow: window)
                Task { @MainActor in
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    else { return }
                    self.images[id] = image
                    done(id, image)
                }
            }
        }
    }

    /// Captures one window, without telling anyone, to keep its picture from when it last had focus: once there has
    /// been no ask for `quiet`, together with every other window asked for meanwhile, from one window enumeration. A
    /// focus change asks for the window that lost focus, once for each switcher, just as the newly focused app
    /// activates, and ScreenCaptureKit at work then can hold up that app's commit to WindowServer for seconds.
    /// A window whose Space no display shows by then is skipped: macOS no longer draws it, so its picture would be
    /// stale or blank, and on a workspace switch `WorkspaceSwitcher.leaving(space:)` took a good one as it left.
    func refreshSoon(_ id: WindowID, scale: CGFloat) {
        soon.insert(id)
        soonScale = scale
        scheduleSoon()
    }

    /// Starts the wait of `refreshSoon` over, and again for as long as a click may still be activating an app.
    private func scheduleSoon() {
        soonWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !clickUnderWay(within: Self.quiet) else { return scheduleSoon() }
            let shown = Set(dinky_current_space_ids().map(\.uint64Value))
            let ids = soon.filter { shown.contains(dinky_window_space_id($0)) }
            soon = []
            soonWork = nil
            refresh(Array(ids), scale: soonScale) { _, _ in }
        }
        soonWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quiet, execute: work)
    }

    /// Drops closed windows' images.
    private func observeClosing() {
        guard !observing, let coordinator = AppState.shared.coordinator else { return }
        observing = true
        coordinator.model.observe { [weak self] event in
            guard let self, event.change == .removed, let id = event.window?.id else { return }
            images[id] = nil
        }
    }
}
