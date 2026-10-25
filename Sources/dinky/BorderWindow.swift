import AppKit
import DinkyConfig
import DinkyPrivate

// The border of one window, or its noop glow: a dinky-owned SkyLight window kept directly below or above its target.
// Redraws only when the look or size changes; a plain move just re-places it.
final class BorderWindow {
    struct Look: Equatable {
        var size: CGSize
        var cornerRadius: Int
        var color: DinkyConfig.Color
        var width: Double
        /// The noop glow, `width` its spread, rather than a ring.
        var glow = false

        /// The same shape in another colour.
        func with(color: DinkyConfig.Color) -> Look {
            var look = self
            look.color = color
            return look
        }
    }

    private let target: UInt32
    /// The border's own WindowServer window id (0 until created).
    private(set) var id: UInt32 = 0
    private var scale = 0.0
    private var spaceID: UInt64 = 0
    private var drawn: Look?
    private var isShown = false
    /// The whole window's opacity, kept across a new window for another display.
    private var alpha = 1.0

    init(target: UInt32) {
        self.target = target
    }

    deinit {
        if id != 0 { dinky_border_destroy(id) }
    }

    /// Place and draw the border around `window`. With `moveOnly`, a border whose shape would change hides instead,
    /// as redrawing it at every size of a resize costs more than a frame; a new colour alone is drawn, once.
    func update(_ window: Window, color: DinkyConfig.Color, config: Borders, moveOnly: Bool = false) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: config.width)
        if moveOnly, drawn?.with(color: color) != look { return hide() }
        place(window, look: look, order: config.order == .above ? .above : .below)
    }

    /// Place and draw the noop glow around `window`, over it: `color` at its edge, fading out over `spread` points
    /// outside it and half that inside.
    func glow(_ window: Window, color: DinkyConfig.Color, spread: Double) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: spread, glow: true)
        place(window, look: look, order: .above)
    }

    /// The whole border's opacity, 0...1, without a redraw.
    func setAlpha(_ alpha: Double) {
        guard alpha != self.alpha else { return }
        self.alpha = alpha
        if id != 0 { dinky_border_set_alpha(id, alpha) }
    }

    private func place(_ window: Window, look: Look, order: DinkyBorderOrder) {
        let scale = backingScale(of: window.frame)
        if scale != self.scale { recreate(scale: scale) }
        guard id != 0 else { return }

        if spaceID != window.spaceID, window.spaceID != 0 {
            dinky_border_move_to_space(id, window.spaceID)
            spaceID = window.spaceID
        }
        if look == drawn {
            dinky_border_move(id, target, window.frame, look.width, order)
        } else {
            let color = look.color
            let rgba = DinkyBorderColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            if look.glow {
                dinky_glow_update(id, target, window.frame, Int32(window.cornerRadius), rgba, look.width)
            } else {
                dinky_border_update(id, target, window.frame, Int32(window.cornerRadius), rgba, look.width, order)
            }
            drawn = look
        }
        isShown = true
    }

    func hide() {
        guard isShown else { return }
        dinky_border_hide(id)
        isShown = false
    }

    // JankyBorders sets the resolution once, at creation; a display change gets a new window.
    // Widths and radii stay in points; the resolution alone decides the pixels.
    private func recreate(scale: Double) {
        if id != 0 { dinky_border_destroy(id) }
        id = dinky_border_create(scale)
        if id != 0, alpha != 1 { dinky_border_set_alpha(id, alpha) }
        self.scale = scale
        spaceID = 0
        drawn = nil
    }
}

// The backing scale of the screen under the frame's centre. Frames are top-left global,
// NSScreen frames bottom-left, flipped around the primary screen.
private func backingScale(of frame: CGRect) -> Double {
    let screens = NSScreen.screens
    guard let primary = screens.first else { return 2 }
    let center = CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
    let screen = screens.first { $0.frame.contains(center) } ?? primary
    return screen.backingScaleFactor
}
