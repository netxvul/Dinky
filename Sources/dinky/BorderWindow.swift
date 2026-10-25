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
        /// The noop glow's bands inside the window, `width` its ring, rather than a plain ring.
        var glow: GlowBands?

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

    /// Place and draw the noop glow over `window`: a `width`-point ring of `color` around it and `bands` inside it,
    /// directly above `above`, the window or its own border when that is drawn above it.
    func glow(_ window: Window, color: DinkyConfig.Color, width: Double, bands: GlowBands, above: UInt32) {
        let look = Look(size: window.frame.size, cornerRadius: window.cornerRadius,
                        color: color, width: width, glow: bands)
        place(window, look: look, order: .above, above: above)
    }

    /// The noop glow drawn again with `bands` where it is, when they differ from what is drawn: a frame of its breathing.
    func redraw(_ bands: GlowBands) {
        guard id != 0, isShown, var look = drawn, look.glow != nil, look.glow != bands else { return }
        look.glow = bands
        Self.withGlow(bands, width: look.width) { glow in
            dinky_glow_draw(id, look.size, Int32(look.cornerRadius), Self.rgba(look.color), glow)
        }
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
        if let bands = look.glow, drawn?.glow?.spread == bands.spread, shape == look {
            // The same glow a frame further on: moved, then only its bands drawn again, as at a frame of its breathing.
            // A new spread is drawn whole, as a redraw clears only as far as the bands reach.
            dinky_glow_move(id, target, above, window.frame, look.width)
            isShown = true
            redraw(bands)
            return
        }
        if look == drawn {
            dinky_border_move(id, target, window.frame, look.width, order)
        } else {
            let rgba = Self.rgba(look.color)
            if let bands = look.glow {
                Self.withGlow(bands, width: look.width) { glow in
                    dinky_glow_update(id, target, above, window.frame, Int32(window.cornerRadius), rgba, glow)
                }
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

    /// The bands as the C side takes them, for the length of `body`.
    private static func withGlow(_ bands: GlowBands, width: Double, _ body: (DinkyGlow) -> Void) {
        bands.edges.withUnsafeBufferPointer { edges in
            bands.alphas.withUnsafeBufferPointer { alphas in
                body(DinkyGlow(width: width, ring: bands.ring, edges: edges.baseAddress!, alphas: alphas.baseAddress!,
                               count: Int32(alphas.count), extent: bands.spread))
            }
        }
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
