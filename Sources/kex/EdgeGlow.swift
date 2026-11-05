import AppKit
import KexConfig
import KexLayout

// The noop flash's look drawn on a display rather than round a window: a `width` ring at the very edge and the glow
// inside it fading to nothing `spread` points in. Along the left side, the right or both, faded out towards the top and
// bottom, as fingers push a strip on past its end (`[gestures.scroll] edge-flash`) or a binding finds no workspace to go
// to; or as one ring round all four edges, over the menu bar and the Dock, as a binding finds no display to go to. Fade
// in, held while the presses come, and fade out (Pulse). Never takes a click, on every Space and over full-screen
// windows, and goes as soon as Mission Control opens. Main thread only.
final class EdgeGlow: NSObject {
    /// Where on the screen it shows.
    enum Shape: Equatable {
        case sides(ScreenSides)
        case ring
    }

    /// What it shows: which edges of which screen, and how.
    private struct Look: Equatable {
        var frame: CGRect
        var shape: Shape
        var color: KexConfig.Color
        var width: Double
        var spread: Double
        var opacity: Double
        var scale: CGFloat
    }

    /// One along each side lit, or one over the whole screen for the ring: no more of the screen than it lights.
    private var panels: [NSPanel] = []
    private var look: Look?
    private var pulse: Pulse?
    private var link: CADisplayLink?
    private var lastTick = 0.0
    /// Counts glows, so the watch of one that has gone stops.
    private var generation = 0
    /// Stops of the glow along a side, as the noop flash's falls off: enough that the eye sees no steps.
    private static let stops = 16

    /// Glows on `screen` in `shape`, as `look` says. Again while it shows holds it: `Pulse.hold` longer, or when `keyed`
    /// until a held key's next repeat can come, so a held key shows it once.
    func flash(on screen: NSScreen, _ shape: Shape, look flash: NoopFlash.Look, keyed: Bool = false) {
        guard !MissionControl.shared.active else { return }
        let now = CACurrentMediaTime()
        // It reaches a quarter of the way across at most, so a ring's sides never meet, nor do the two sides lit together.
        let across = shape == .ring ? min(screen.frame.width, screen.frame.height) : screen.frame.width
        let look = Look(frame: screen.frame, shape: shape, color: flash.color.resolved, width: flash.width,
                        spread: min(flash.spread, Double(across) / 4), opacity: flash.opacity, scale: screen.backingScaleFactor)
        if look != self.look {
            // Other edges or another screen start afresh.
            if let old = self.look, old.frame != look.frame || old.shape != look.shape { end() }
            draw(look)
        }
        let first = keyed ? Pulse.holding(for: NSEvent.keyRepeatDelay) : Pulse.hold
        let again = keyed ? Pulse.holding(for: NSEvent.keyRepeatInterval) : Pulse.hold
        if pulse?.press(at: now, hold: again) != true { pulse = Pulse(at: now, hold: first) }
        let presence = CGFloat(pulse?.presence(at: now) ?? 0)
        for panel in panels {
            panel.alphaValue = presence
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        guard link == nil else { return }
        link = screen.displayLink(target: self, selector: #selector(tick))
        // A fade takes half a second: 60 frames a second are smooth, and each only sets the panels' opacity.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link?.add(to: .main, forMode: .common)
        lastTick = now
        watch(generation)
    }

    @objc private func tick(_ link: CADisplayLink) {
        lastTick = CACurrentMediaTime()
        guard !MissionControl.shared.active, let presence = pulse?.presence(at: link.targetTimestamp) else { return end() }
        for panel in panels { panel.alphaValue = CGFloat(presence) }
    }

    /// The panels of the look, one frame and one layer each, reusing those it has.
    private func draw(_ look: Look) {
        self.look = look
        let parts: [(frame: CGRect, layer: CALayer)]
        switch look.shape {
        case .ring: parts = [(look.frame, Self.ring(look))]
        case .sides(let sides):
            parts = [(ScreenSides.left, false), (.right, true)].filter { sides.contains($0.0) }.map { Self.side(look, right: $0.1) }
        }
        while panels.count > parts.count { panels.removeLast().orderOut(nil) }
        while panels.count < parts.count { panels.append(Self.makePanel()) }
        for (panel, part) in zip(panels, parts) {
            panel.setFrame(part.frame, display: false)
            // Hosting its own layer: the layer first, then wanting it.
            let view = NSView(frame: CGRect(origin: .zero, size: part.frame.size))
            view.layer = part.layer
            view.wantsLayer = true
            panel.contentView = view
        }
    }

    /// The ring at the very edge of one side and the glow inside it, both faded out towards the top and bottom, and the
    /// frame on the screen they go in.
    private static func side(_ look: Look, right: Bool) -> (frame: CGRect, layer: CALayer) {
        let reach = CGFloat(look.width + look.spread), height = look.frame.height
        let frame = CGRect(x: right ? look.frame.maxX - reach : look.frame.minX, y: look.frame.minY, width: reach, height: height)
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        let color = look.color.nsColor
        let ring = CALayer()
        ring.frame = CGRect(x: right ? reach - CGFloat(look.width) : 0, y: 0, width: CGFloat(look.width), height: height)
        ring.backgroundColor = color.cgColor
        root.addSublayer(ring)
        let glow = CAGradientLayer()
        glow.frame = CGRect(x: right ? 0 : CGFloat(look.width), y: 0, width: CGFloat(look.spread), height: height)
        // From the edge in: the noop flash's falloff, by e every third of the way and down to nothing at the end.
        let shares = (0..<stops).map { Double($0) / Double(stops - 1) }
        glow.colors = shares.map { share in
            color.withAlphaComponent(color.alphaComponent * look.opacity * falloff(share)).cgColor
        }
        glow.locations = shares.map { NSNumber(value: $0) }
        glow.startPoint = CGPoint(x: right ? 1 : 0, y: 0.5)
        glow.endPoint = CGPoint(x: right ? 0 : 1, y: 0.5)
        root.addSublayer(glow)
        // Nothing at the very top and bottom, full a fifth of the way in, so it never meets the next side.
        let fade = CAGradientLayer()
        fade.frame = root.bounds
        fade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        fade.locations = [0, 0.2, 0.8, 1]
        root.mask = fade
        for layer in [root, ring, glow, fade] { layer.contentsScale = look.scale }
        return (frame, root)
    }

    /// The ring round all four edges and the glow inside it, as one layer over the screen: a square just big enough for
    /// the corners, whose middle point stretches along the sides, so the screen's backing store is not spent on a middle
    /// with nothing in it.
    private static func ring(_ look: Look) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: look.frame.size)
        root.contentsScale = look.scale
        guard let image = ringCorners(look) else { return root }
        root.contents = image
        let share = look.scale / CGFloat(image.width)
        root.contentsCenter = CGRect(x: 0.5 - share / 2, y: 0.5 - share / 2, width: share, height: share)
        return root
    }

    /// The square of `ring`, as draw_glow in borders.m draws a window's glow, its bands whole paths so the corners run
    /// on unbroken: outermost first, a point deep each and copied over the next one's first point so neighbours meet
    /// without a seam, rounding more the deeper they reach.
    private static func ringCorners(_ look: Look) -> CGImage? {
        let width = CGFloat(look.width), spread = CGFloat(look.spread)
        // Past the deepest band and the round of its corners, with a point in the middle to stretch.
        let side = (2 * (width + spread * 1.5 + 1)).rounded(.up)
        let pixels = Int((side * look.scale).rounded())
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: look.scale, y: look.scale)
        context.setBlendMode(.copy)
        let bounds = CGRect(x: 0, y: 0, width: side, height: side), color = look.color.nsColor
        func band(from: CGFloat, to: CGFloat, alpha: Double) {
            let path = CGMutablePath()
            for depth in [from, to] {
                // From the screen's own edge, whose corners are square: the ring keeps them, the glow rounds them.
                let radius = max(depth - width, 0) / 2
                path.addRoundedRect(in: bounds.insetBy(dx: depth, dy: depth), cornerWidth: radius, cornerHeight: radius)
            }
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * alpha).cgColor)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        if width > 0 { band(from: 0, to: width + 1, alpha: 1) }
        var from = 0.0
        while from < look.spread {
            let to = min(from + 1, look.spread)
            band(from: width + from, to: width + (to < look.spread ? to + 1 : to),
                 alpha: look.opacity * falloff((from + to) / 2 / look.spread))
            from += 1
        }
        return context.makeImage()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // Above the Dock and the menu bar, as the HUD is, but not at a menu's level or a modal panel's, which turn
        // hover focus off while they show.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        return panel
    }

    /// How strong the glow is `share` of the way in from the edge to as deep as it reaches, as borders.m's
    /// glow_falloff has it for the noop flash.
    private static func falloff(_ share: Double) -> Double {
        (exp(-3 * share) - exp(-3)) / (1 - exp(-3))
    }

    /// A display link whose screen goes away stops firing: the glow goes all the same.
    private func watch(_ generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == generation else { return }
            if CACurrentMediaTime() - self.lastTick > 0.5 { self.end() } else { self.watch(generation) }
        }
    }

    /// Goes at once, as the Space changes.
    func dismiss() {
        guard link != nil else { return }
        end()
    }

    private func end() {
        link?.invalidate()
        link = nil
        pulse = nil
        for panel in panels { panel.orderOut(nil) }
        generation += 1
    }
}
