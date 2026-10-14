import AppKit
import DinkyLayout
import ScreenCaptureKit

// `[scrolling] glide = 'snapshots'`: a strip scrolls as pictures. Before it sets off, the strip's windows are snapshot,
// and so is what is behind them on the display, without them; a window of dinky's own, over the display's visible
// area, shows that background with the windows' snapshots on it, and the animator moves the snapshots on every frame
// of the display, in strip coordinates, so they pass the screen edges as a strip would, where real windows have to
// stop. Meanwhile the real windows go straight to their places underneath. Once the glide has ended and the windows
// have landed, the stage fades out over them. The snapshots need Screen Recording; one that cannot be made in time
// leaves the glide to the windows. Main thread only.
final class GlideStage {
    /// How long the snapshots may take; past that the glide goes ahead with the windows themselves.
    private static let captureLimit: TimeInterval = 0.25
    /// How long after the glide the stage waits for the windows to land before it goes anyway.
    private static let landingLimit: TimeInterval = 0.4
    private static let fadeOut: TimeInterval = 0.1

    private let window: NSWindow
    /// The area the stage covers, in global coordinates with a top-left origin.
    private let area: CGRect
    private let root = CALayer()
    private let images: [WindowID: CGImage]
    private let scale: CGFloat
    private var layers: [WindowID: CALayer] = [:]
    private var glided = false
    private var landed = false
    private var removed = false
    /// Called once the stage is gone.
    var onRemoved: () -> Void = {}

    private init(area: CGRect, background: CGImage, images: [WindowID: CGImage], scale: CGFloat) {
        self.area = area
        self.images = images
        self.scale = scale
        let primary = NSScreen.screens.first?.frame.maxY ?? area.maxY
        let frame = NSRect(x: area.minX, y: primary - area.maxY, width: area.width, height: area.height)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        // Over the workspace's windows, its floating ones too, for the moment of the glide.
        window.level = .floating
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.isGeometryFlipped = true
        root.masksToBounds = true
        view.layer = root
        view.wantsLayer = true
        window.contentView = view
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let back = CALayer()
        back.frame = CGRect(origin: .zero, size: frame.size)
        back.contents = background
        back.contentsScale = scale
        root.addSublayer(back)
        CATransaction.commit()
    }

    /// Snapshots the windows `ids` and what is behind them on `display`, and calls `ready` on the main thread with a
    /// stage, or with nil when that could not be done within `captureLimit`.
    static func capture(_ ids: [WindowID], on display: Display, ready: @escaping (GlideStage?) -> Void) {
        let area = display.visibleArea
        let scale = screen(of: display.id)?.backingScaleFactor ?? 2
        var answered = false
        let answer = { (stage: GlideStage?) in
            guard !answered else { return stage?.remove(fading: false) ?? () }
            answered = true
            ready(stage)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + captureLimit) { answer(nil) }
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  let target = content.displays.first(where: { $0.displayID == display.id }) else { return answer(nil) }
            let wanted = Set(ids), own = getpid()
            let windows = content.windows.filter { wanted.contains($0.windowID) }
            // Behind the strip: the display without the strip's windows or dinky's own, such as the switcher fading out.
            let hidden = content.windows.filter { wanted.contains($0.windowID) || $0.owningApplication?.processID == own }
            let backConfiguration = SCStreamConfiguration()
            backConfiguration.sourceRect = CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY,
                                                  width: area.width, height: area.height)
            backConfiguration.width = Int(area.width * scale)
            backConfiguration.height = Int(area.height * scale)
            backConfiguration.showsCursor = false
            let backFilter = SCContentFilter(display: target, excludingWindows: hidden)
            var images: [WindowID: CGImage] = [:]
            await withTaskGroup(of: (WindowID, CGImage?).self) { group in
                for window in windows where window.frame.width > 1 && window.frame.height > 1 {
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(window.frame.width * scale)
                    configuration.height = Int(window.frame.height * scale)
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let id = window.windowID
                    group.addTask {
                        (id, try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration))
                    }
                }
                for await (id, image) in group { if let image { images[id] = image } }
            }
            guard let background = try? await SCScreenshotManager.captureImage(contentFilter: backFilter,
                                                                               configuration: backConfiguration)
            else { return answer(nil) }
            answer(GlideStage(area: area, background: background, images: images, scale: scale))
        }
    }

    /// Puts the snapshots at `frames`, global with a top-left origin, stacked as `order` has them, front first, and
    /// shows the stage. A window without a snapshot stays hidden behind the background until the stage goes.
    func show(at frames: [WindowID: CGRect], order: [WindowID], corners: [WindowID: CGFloat]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in order.reversed() {
            guard let image = images[id], let frame = frames[id] else { continue }
            let layer = CALayer()
            layer.contents = image
            layer.contentsScale = scale
            layer.contentsGravity = .resize
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 12
            layer.shadowOffset = .zero
            let radius = corners[id] ?? 10
            layer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius,
                                      cornerHeight: radius, transform: nil)
            layer.frame = frame.offsetBy(dx: -area.minX, dy: -area.minY)
            root.addSublayer(layer)
            layers[id] = layer
        }
        CATransaction.commit()
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    /// Moves the snapshots of the windows in `frames`. A strip's windows keep their sizes as it scrolls, so the
    /// shadows' outlines stay as `show` made them.
    func move(_ frames: [WindowID: CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, frame) in frames { layers[id]?.frame = frame.offsetBy(dx: -area.minX, dy: -area.minY) }
        CATransaction.commit()
    }

    /// The glide is over: the stage goes once the windows have landed, or after `landingLimit`.
    func glideEnded() {
        glided = true
        if landed { return remove(fading: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.landingLimit) { [weak self] in self?.remove(fading: true) }
    }

    /// The windows have been written to their places and read back.
    func windowsLanded() {
        landed = true
        if glided { remove(fading: true) }
    }

    /// Takes the stage away, fading it over the windows or at once.
    func remove(fading: Bool) {
        guard !removed else { return }
        removed = true
        let window = window
        let done = { [onRemoved] in
            window.orderOut(nil)
            onRemoved()
        }
        guard fading, window.isVisible else { return done() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            window.animator().alphaValue = 0
        }, completionHandler: done)
    }
}
