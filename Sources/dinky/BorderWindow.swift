import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// The border of one window, or its noop glow: a dinky-owned SkyLight window kept directly below or above its target.
// Redraws only when the look or size changes; a plain move just re-places it.
final class BorderWindow {
    struct Look: Equatable {
        var size: CGSize
        var cornerRadius: Int
        var color: DinkyConfig.Color
        var width: Double
        /// The noop glow's band inside the window, `width` its ring, rather than a plain ring.
        var glow: GlowBand?

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
    private(set) var isShown = false

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

    /// Place and draw the noop glow over `window`: a `width`-point ring of `color` around it and `band` inside it,
    /// directly above `above`, the window or its own border when that is drawn above it.
    func glow(_ window: Window, color: DinkyConfig.Color, width: Double, band: GlowBand, above: UInt32) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: width, glow: band)
        place(window, look: look, order: .above, above: above)
    }

    /// The noop glow drawn again with `band` where it is, when that differs from what is drawn: a frame of its fading.
    func redraw(_ band: GlowBand) {
        guard id != 0, isShown, var look = drawn, look.glow != nil, look.glow != band else { return }
        look.glow = band
        dinky_glow_draw(id, look.size, Int32(look.cornerRadius), Self.rgba(look.color),
                        Self.dinkyGlow(band, width: look.width))
        drawn = look
    }

    private func place(_ window: Window, look: Look, order: DinkyBorderOrder, above: UInt32 = 0) {
        let scale = backingScale(of: window.frame)
        if scale != self.scale { recreate(scale: scale) }
        guard id != 0 else { return }

        if spaceID != window.spaceID, window.spaceID != 0 {
            dinky_border_move_to_space(id, window.spaceID)
            spaceID = window.spaceID
        }
        var shape = drawn
        shape?.glow = look.glow
        if let band = look.glow, drawn?.glow?.depth == band.depth, shape == look {
            // The same glow a frame further on: moved, then only its band drawn again, as at a frame of its fading.
            // A new depth is drawn whole, as a redraw clears only as far as the band reaches.
            dinky_glow_move(id, target, above, window.frame, look.width)
            isShown = true
            redraw(band)
            return
        }
        if look == drawn {
            dinky_border_move(id, target, window.frame, look.width, order)
        } else {
            let rgba = Self.rgba(look.color)
            if let band = look.glow {
                dinky_glow_update(id, target, above, window.frame, Int32(window.cornerRadius), rgba,
                                  Self.dinkyGlow(band, width: look.width))
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

    /// The glow as the C side takes it: `band` inside a `width`-point ring.
    private static func dinkyGlow(_ band: GlowBand, width: Double) -> DinkyGlow {
        DinkyGlow(width: width, ring: band.ring, depth: band.depth, alpha: band.alpha)
    }

    // JankyBorders sets the resolution once, at creation; a display change gets a new window.
    // Widths and radii stay in points; the resolution alone decides the pixels.
    private func recreate(scale: Double) {
        if id != 0 { dinky_border_destroy(id) }
        id = dinky_border_create(scale)
        self.scale = scale
        spaceID = 0
        drawn = nil
    }
}

// The backing scale of the screen under the frame's centre.
private func backingScale(of frame: CGRect) -> Double {
    Double(screen(containing: frame)?.backingScaleFactor ?? 2)
}
