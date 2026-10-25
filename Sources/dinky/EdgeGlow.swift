import AppKit
import DinkyConfig
import DinkyLayout

// The glow along one side of a display, as fingers push a strip on past its end (`[gestures.scroll] edge-flash`): the
// noop flash's look, its `noop-flash-width` ring and the glow inside it fading to nothing `noop-flash-spread` points
// in, drawn along the display's left or right edge alone rather than round a window, and faded out towards the
// display's top and bottom. Fade in, held while the pushes come, and fade out (Pulse). Never takes a click, on every
// Space and over full-screen windows, and goes as soon as Mission Control opens. Main thread only.
final class EdgeGlow: NSObject {
    /// What it shows: which side of which screen, and how.
    private struct Look: Equatable {
        var frame: CGRect
        var right: Bool
        var color: DinkyConfig.Color
        var width: Double
        var spread: Double
        var opacity: Double
        var scale: CGFloat
    }

    private var panel: NSPanel?
    private var look: Look?
    private var pulse: Pulse?
    private var link: CADisplayLink?
    private var lastTick = 0.0
    /// Counts glows, so the watch of one that has gone stops.
    private var generation = 0
    /// Stops of the glow inside the ring, as the noop flash's falls off: enough that the eye sees no steps.
    private static let stops = 16

    /// Glows along the `right` side of `screen`, or its left, as `[borders]` draws the noop flash. Again while it shows
    /// holds it `Pulse.hold` longer.
    func flash(on screen: NSScreen, right: Bool, config: Borders) {
        guard !MissionControl.shared.active else { return }
        let now = CACurrentMediaTime()
        let look = Look(frame: screen.frame, right: right, color: config.noopFlashColor.resolved,
                        width: config.noopFlashWidth, spread: min(config.noopFlashSpread, Double(screen.frame.width) / 4),
                        opacity: config.noopFlashOpacity, scale: screen.backingScaleFactor)
        if look != self.look {
            // Another side or screen starts afresh.
            if let old = self.look, old.frame != look.frame || old.right != look.right { end() }
            draw(look)
        }
        if pulse?.press(at: now) != true { pulse = Pulse(at: now) }
        let panel = self.panel!
        panel.alphaValue = CGFloat(pulse?.presence(at: now) ?? 0)
        if !panel.isVisible { panel.orderFrontRegardless() }
        guard link == nil else { return }
        link = screen.displayLink(target: self, selector: #selector(tick))
        // A fade takes half a second: 60 frames a second are smooth, and each only sets the panel's opacity.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link?.add(to: .main, forMode: .common)
        lastTick = now
        watch(generation)
    }

    @objc private func tick(_ link: CADisplayLink) {
        lastTick = CACurrentMediaTime()
        guard !MissionControl.shared.active, let presence = pulse?.presence(at: link.targetTimestamp) else { return end() }
        panel?.alphaValue = CGFloat(presence)
    }

    /// The panel along the side, and in it the ring at the very edge and the glow inside it, both faded out towards
    /// the top and bottom.
    private func draw(_ look: Look) {
        self.look = look
        let reach = CGFloat(look.width + look.spread), height = look.frame.height
        let frame = CGRect(x: look.right ? look.frame.maxX - reach : look.frame.minX, y: look.frame.minY,
                           width: reach, height: height)
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        let color = look.color.nsColor
        let ring = CALayer()
        ring.frame = CGRect(x: look.right ? reach - CGFloat(look.width) : 0, y: 0, width: CGFloat(look.width),
                            height: height)
        ring.backgroundColor = color.cgColor
        root.addSublayer(ring)
        let glow = CAGradientLayer()
        glow.frame = CGRect(x: look.right ? 0 : CGFloat(look.width), y: 0, width: CGFloat(look.spread), height: height)
        // From the edge in: the noop flash's falloff, by e every third of the way and down to nothing at the end.
        let shares = (0..<Self.stops).map { Double($0) / Double(Self.stops - 1) }
        glow.colors = shares.map { share in
            color.withAlphaComponent(color.alphaComponent * look.opacity * Self.falloff(share)).cgColor
        }
        glow.locations = shares.map { NSNumber(value: $0) }
        glow.startPoint = CGPoint(x: look.right ? 1 : 0, y: 0.5)
        glow.endPoint = CGPoint(x: look.right ? 0 : 1, y: 0.5)
        root.addSublayer(glow)
        // Nothing at the very top and bottom, full a fifth of the way in, so it never meets the next side.
        let fade = CAGradientLayer()
        fade.frame = root.bounds
        fade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        fade.locations = [0, 0.2, 0.8, 1]
        root.mask = fade
        for layer in [root, ring, glow, fade] { layer.contentsScale = look.scale }

        // Hosting its own layer: the layer first, then wanting it.
        let view = NSView(frame: root.frame)
        view.layer = root
        view.wantsLayer = true
        panel.contentView = view
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
        panel.level = .popUpMenu
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
        panel?.orderOut(nil)
        generation += 1
    }
}
