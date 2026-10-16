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

    /// Fetching SCShareableContent (enumerating every window) costs ~50-70ms, so a recent copy is reused across
    /// scrolls and refreshed in the background. A copy this fresh is used as is; one this stale triggers a background
    /// refresh for the next scroll; past `contentMaxAge` the scroll waits for a fresh fetch. The window list may then
    /// lag reality by up to that age — a window that just joined the strip can miss this glide's snapshot and hide
    /// until the stage goes, which the background refresh keeps rare.
    private static let contentMaxAge: TimeInterval = 2.0
    private static let contentFreshenAfter: TimeInterval = 0.4
    private static var cachedContent: (content: SCShareableContent, at: CFTimeInterval)?
    private static var freshening = false

    /// A recent window enumeration, reused when fresh enough so a scroll need not wait ~60ms for a new one.
    private static func shareableContent() async -> SCShareableContent? {
        let now = CACurrentMediaTime()
        if let cached = cachedContent, now - cached.at < contentMaxAge {
            if now - cached.at > contentFreshenAfter { freshenContent() }
            return cached.content
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return cachedContent?.content   // a stale copy beats failing the glide
        }
        cachedContent = (content, CACurrentMediaTime())
        return content
    }

    /// Refreshes the cached enumeration in the background, so the next scroll reuses a current one without waiting.
    private static func freshenContent() {
        guard !freshening else { return }
        freshening = true
        Task { @MainActor in
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                cachedContent = (content, CACurrentMediaTime())
            }
            freshening = false
        }
    }

    /// Window snapshots kept between scrolls: capturing them is the bulk of a glide's setup, so a run of scrolls
    /// reuses recent ones and only the background is taken each time. Reused up to `shotMaxAge`; past
    /// `shotFreshenAfter` a reused one is re-captured in the background so the picture stays current.
    private static let shotMaxAge: TimeInterval = 5.0
    private static let shotFreshenAfter: TimeInterval = 1.0
    private static var shotCache: [WindowID: (image: CGImage, at: CFTimeInterval)] = [:]
    private static var fresheningShots: Set<WindowID> = []

    /// The filter and configuration to snapshot one window at `scale`.
    private static func windowConfig(_ window: SCWindow, scale: CGFloat) -> (SCContentFilter, SCStreamConfiguration) {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return (SCContentFilter(desktopIndependentWindow: window), configuration)
    }

    /// Re-captures one window's snapshot into the cache in the background, so a reused one does not grow stale.
    private static func freshenShot(_ window: SCWindow, scale: CGFloat) {
        let id = window.windowID
        guard !fresheningShots.contains(id), window.frame.width > 1, window.frame.height > 1 else { return }
        fresheningShots.insert(id)
        let (filter, configuration) = windowConfig(window, scale: scale)
        Task { @MainActor in
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                shotCache[id] = (image, CACurrentMediaTime())
            }
            fresheningShots.remove(id)
        }
    }

    /// Drops window snapshots older than `at`, so closed windows do not linger in the cache.
    private static func pruneShots(before at: CFTimeInterval) {
        shotCache = shotCache.filter { $0.value.at >= at }
    }

    /// Background snapshots per display, cached and freshened like the window shots.
    private static var bgCache: [CGDirectDisplayID: (image: CGImage, at: CFTimeInterval)] = [:]
    private static var fresheningBg: Set<CGDirectDisplayID> = []

    /// Re-captures a display's background into the cache in the background, so a reused one does not grow stale.
    private static func freshenBackground(_ displayID: CGDirectDisplayID, filter: SCContentFilter, configuration: SCStreamConfiguration) {
        guard !fresheningBg.contains(displayID) else { return }
        fresheningBg.insert(displayID)
        Task { @MainActor in
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                bgCache[displayID] = (image, CACurrentMediaTime())
            }
            fresheningBg.remove(displayID)
        }
    }

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
            guard let content = await shareableContent(),
                  let target = content.displays.first(where: { $0.displayID == display.id }) else { return answer(nil) }
            let wanted = Set(ids), own = getpid()
            let windows = content.windows.filter { wanted.contains($0.windowID) }
            let now = CACurrentMediaTime()
            pruneShots(before: now - shotMaxAge)
            // Reuse recent window snapshots: a window's content barely changes from one scroll to the next, and the
            // real window shows crisp again once the glide lands. Only windows missing or stale are captured now, and
            // soon-to-expire ones are freshened in the background, so a run of scrolls pays only for the background.
            var images: [WindowID: CGImage] = [:]
            var toCapture: [SCWindow] = []
            for window in windows {
                if let cached = shotCache[window.windowID], now - cached.at < shotMaxAge {
                    images[window.windowID] = cached.image
                    if now - cached.at > shotFreshenAfter { freshenShot(window, scale: scale) }
                } else if window.frame.width > 1 && window.frame.height > 1 {
                    toCapture.append(window)
                }
            }
            // Behind the strip: the display without the strip's windows or dinky's own, such as the switcher fading out.
            let hidden = content.windows.filter { wanted.contains($0.windowID) || $0.owningApplication?.processID == own }
            let backConfiguration = SCStreamConfiguration()
            backConfiguration.sourceRect = CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY,
                                                  width: area.width, height: area.height)
            backConfiguration.width = Int(area.width * scale)
            backConfiguration.height = Int(area.height * scale)
            backConfiguration.showsCursor = false
            let backFilter = SCContentFilter(display: target, excludingWindows: hidden)
            // What is behind the strip barely changes as the strip scrolls, so the background is cached like the
            // window shots: reused when fresh, freshened in the background when stale, captured now only when absent.
            var cachedBackground: CGImage?
            if let cached = bgCache[display.id], now - cached.at < shotMaxAge {
                cachedBackground = cached.image
                if now - cached.at > shotFreshenAfter { freshenBackground(display.id, filter: backFilter, configuration: backConfiguration) }
            }
            async let backgroundShot: CGImage? = cachedBackground == nil
                ? (try? await SCScreenshotManager.captureImage(contentFilter: backFilter, configuration: backConfiguration))
                : nil
            await withTaskGroup(of: (WindowID, CGImage?).self) { group in
                for window in toCapture {
                    let (filter, configuration) = windowConfig(window, scale: scale)
                    let id = window.windowID
                    group.addTask {
                        (id, try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration))
                    }
                }
                for await (id, image) in group {
                    if let image { images[id] = image; shotCache[id] = (image, CACurrentMediaTime()) }
                }
            }
            let background: CGImage
            if let cachedBackground {
                background = cachedBackground
            } else {
                guard let fresh = await backgroundShot else { return answer(nil) }
                bgCache[display.id] = (fresh, CACurrentMediaTime())
                background = fresh
            }
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
            layer.shadowOpacity = Self.shadowOpacity * edgeShadow(frame)
            layer.shadowRadius = 8
            // Down: a shadow's offset points up on screen, even under the flipped root.
            layer.shadowOffset = CGSize(width: 0, height: -8)
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
        for (id, frame) in frames {
            layers[id]?.frame = frame.offsetBy(dx: -area.minX, dy: -area.minY)
            layers[id]?.shadowOpacity = Self.shadowOpacity * edgeShadow(frame)
        }
        CATransaction.commit()
    }

    /// The snapshots' shadow, fitted to an inactive window's own (measured on macOS 27): faint above, strongest below.
    private static let shadowOpacity: Float = 0.2

    /// How much of its shadow a snapshot at `frame` shows: all of it in view, none tucked under the peek at an edge
    /// (`Workspace.tuck` on screen), where it would only pile up above and below the peek in front, and in between
    /// as it slides out from under it.
    private func edgeShadow(_ frame: CGRect) -> Float {
        guard frame.minX < area.minX - 1 || frame.maxX > area.maxX + 1 else { return 1 }
        let shows = min(frame.maxX, area.maxX) - max(frame.minX, area.minX)
        return Float(min(max((shows - Workspace.tuck) / (Workspace.peek - Workspace.tuck), 0), 1))
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
