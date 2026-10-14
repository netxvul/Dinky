import AppKit
import DinkyLayout
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

    private var images: [WindowID: CGImage] = [:]
    private var asked = false
    private var observing = false

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

    /// Captures one window, without telling anyone: keeps a window's picture from when it last had focus.
    func refresh(_ id: WindowID, height: CGFloat = height, scale: CGFloat) {
        refresh([id], height: height, scale: scale) { _, _ in }
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
