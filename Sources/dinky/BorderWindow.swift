import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// The border of one window, or its noop glow: a dinky-owned SkyLight window kept directly below or above its target.
// Redraws only when the look or size changes; a plain move just re-places it, and the glow fades without a redraw.
final class BorderWindow {
    /// The noop glow inside the window: its colour at `alpha` at the window's edge, fading to nothing `depth` points in.
    struct Glow: Equatable {
        var depth: Double
        var alpha: Double
    }

    struct Look: Equatable {
        var size: CGSize
        var cornerRadius: Int
        var color: DinkyConfig.Color
        var width: Double
        /// The noop glow inside the window, `width` its ring, rather than a plain ring.
        var glow: Glow?

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
    /// The noop glow's opacity as a whole.
    private var opacity = 1.0
    private(set) var isShown = false

    init(target: UInt32) {
        self.target = target
    }

    deinit {
        if id != 0 { dinky_border_destroy(id) }
    }

    /// Place and draw the border around `window`. With `moveOnly`, a border whose shape would change hides instead,
    /// as redrawing it at every size of a resize costs more than a frame; a new colour alone is drawn, once.
    func update(_ window: Window, color: DinkyConfig.Color, width: Double, config: Borders, moveOnly: Bool = false) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: width)
        if moveOnly, drawn?.with(color: color) != look { return hide() }
        place(window, look: look, order: config.order == .above ? .above : .below)
    }

    /// Place and draw the noop glow over `window` at `opacity` as a whole: a `width`-point ring of `color` around it and
    /// `glow` inside it, directly above `above`, the window or its own border when that is drawn above it.
    func glow(_ window: Window, color: DinkyConfig.Color, width: Double, glow: Glow, opacity: Double, above: UInt32) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: width, glow: glow)
        place(window, look: look, order: .above, above: above, opacity: opacity)
    }

    /// The noop glow at `opacity` as a whole where it is, when that differs from what it shows: a frame of its fading.
    func fade(_ opacity: Double) {
        guard id != 0, isShown, drawn?.glow != nil, opacity != self.opacity else { return }
        dinky_glow_fade(id, opacity)
        self.opacity = opacity
    }

    private func place(_ window: Window, look: Look, order: DinkyBorderOrder, above: UInt32 = 0, opacity: Double = 1) {
        let scale = backingScale(of: window.frame)
        if scale != self.scale { recreate(scale: scale) }
        guard id != 0 else { return }

        if spaceID != window.spaceID, window.spaceID != 0 {
            dinky_border_move_to_space(id, window.spaceID)
            spaceID = window.spaceID
        }
        if look == drawn, look.glow != nil {
            // The same glow a frame further on: moved, then faded, as at a frame of its fading.
            dinky_glow_move(id, target, above, window.frame, look.width)
            isShown = true
            fade(opacity)
            return
        }
        if look == drawn {
            dinky_border_move(id, target, window.frame, look.width, order)
        } else {
            let rgba = Self.rgba(look.color)
            if let glow = look.glow {
                dinky_glow_update(id, target, above, window.frame, Int32(window.cornerRadius), rgba,
                                  DinkyGlow(width: look.width, depth: glow.depth, alpha: glow.alpha), opacity)
                self.opacity = opacity
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

    private static func rgba(_ color: DinkyConfig.Color) -> DinkyBorderColor {
        DinkyBorderColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    // JankyBorders sets the resolution once, at creation; a display change gets a new window.
    // Widths and radii stay in points; the resolution alone decides the pixels.
    private func recreate(scale: Double) {
        if id != 0 { dinky_border_destroy(id) }
        id = dinky_border_create(scale)
        self.scale = scale
        spaceID = 0
        drawn = nil
        opacity = 1
    }
}

// The backing scale of the screen under the frame's centre.
private func backingScale(of frame: CGRect) -> Double {
    Double(screen(containing: frame)?.backingScaleFactor ?? 2)
}
