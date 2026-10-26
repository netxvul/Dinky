import AppKit
import DinkyConfig
import DinkyLayout

// While a tiled window is dragged and a drop shows, the other windows have made room for it (Drag.swift), and the
// preview fills the frame the dragged window will have, shaped like a window: its corners rounded as the window's are,
// an accent border inside the frame and a translucent fill. The pointer is on the dragged window, so the preview goes
// above it to be seen. A window a swap takes to another display stays where it is till the drop, so a panel of the same
// look shows the frame it will have there. A swap is filled more strongly than a split, at the same border width. While
// the drag would go back, a quiet outline, kept below the dragged window, shows where it goes back to. Borderless
// panels that never take focus or clicks, put straight where they go, as the windows making room around them are.
// `[drag]` can set the preview's colours and the width of every outline, and turn the outline of where it goes back off.
final class DragPlaceholders {
    /// A frame, top-left global as windows' are, and the radius of the corners of the window it is for.
    typealias Shape = (frame: CGRect, radius: CGFloat)

    private lazy var home = Self.panel()
    private lazy var preview = Self.panel()
    private lazy var partner = Self.panel()
    private var style: Drag?
    /// Whether any panel may be up, since the last `hide()`.
    private var showing = false
    private var splitLook = PlaceholderLook(stroke: .controlAccentColor, fill: .controlAccentColor.withAlphaComponent(0.3), width: 3)
    private var swapLook = PlaceholderLook(stroke: .controlAccentColor, fill: .controlAccentColor.withAlphaComponent(0.45), width: 3)
    private var homeLook = PlaceholderLook(stroke: .secondaryLabelColor.withAlphaComponent(0.45),
                                           fill: .secondaryLabelColor.withAlphaComponent(0.06), width: 3)

    /// Show the feedback for the window `dragged`: `preview` where it will be, `partner` where a window it swaps with
    /// from another display will be, and `home` where it goes back to. Each left out is hidden.
    func show(dragged: WindowID, preview previewShape: Shape?, partner partnerShape: Shape?, home homeShape: Shape?, swap: Bool) {
        showing = true
        let look = swap ? swapLook : splitLook
        // Below the dragged window, as its tile is.
        if let homeShape { place(home, homeShape, homeLook, .below, dragged) } else { hide(home) }
        // In front of every window, the dragged one and those of another display it is over, which macOS can leave above
        // it: the partner first, so the preview ends up above it.
        if let partnerShape { place(partner, partnerShape, look, .above, dragged) } else { hide(partner) }
        if let previewShape { place(preview, previewShape, look, .above, dragged) } else { hide(preview) }
    }

    func hide() {
        // Called as the pointer moves with nothing to show: nothing to order out, nor panels to make for it.
        guard showing else { return }
        showing = false
        for panel in [home, preview, partner] { hide(panel) }
    }

    /// Take the preview's colours and the outlines' width from `[drag]`. Unset colours follow the accent colour.
    func update(style drag: Drag) {
        guard drag != style else { return }
        style = drag
        let border = drag.previewBorderColor?.nsColor ?? .controlAccentColor
        let fill = drag.previewFillColor?.nsColor ?? border.fading(to: 0.3)
        let width = CGFloat(drag.previewBorderWidth)
        splitLook = PlaceholderLook(stroke: border, fill: fill, width: width)
        // A swap: a stronger fill than a split, never a fainter one, with the same border.
        let alpha = fill.alphaComponent
        swapLook = PlaceholderLook(stroke: border, fill: fill.withAlphaComponent(max(alpha, min(alpha * 1.5, 0.6))), width: width)
        homeLook = PlaceholderLook(stroke: .secondaryLabelColor.withAlphaComponent(0.45),
                                   fill: .secondaryLabelColor.withAlphaComponent(0.06), width: width)
    }

    private func hide(_ panel: NSPanel) {
        panel.orderOut(nil)
    }

    private func place(_ panel: NSPanel, _ shape: Shape, _ look: PlaceholderLook, _ side: NSWindow.OrderingMode, _ window: WindowID) {
        (panel.contentView as! PlaceholderView).set(look, radius: shape.radius)
        let frame = Self.appKitFrame(shape.frame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // Above means in front of every window at its level; below, just behind the dragged window.
        panel.order(side, relativeTo: side == .above ? 0 : Int(window))
    }

    private static func panel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.contentView = PlaceholderView()
        return panel
    }

    /// Top-left global to AppKit's bottom-left, flipped around the primary screen.
    private static func appKitFrame(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct PlaceholderLook: Equatable {
    var stroke: NSColor
    var fill: NSColor
    var width: CGFloat
}

/// A window's shape: a rectangle filling the view, its corners rounded to the window's radius, filled and outlined
/// inside its edge.
private final class PlaceholderView: NSView {
    private var look = PlaceholderLook(stroke: .clear, fill: .clear, width: 0)
    private var radius: CGFloat = 0

    init() {
        super.init(frame: .zero)
        // Redrawn at each size the panel is given, not stretched from the last drawing.
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ look: PlaceholderLook, radius: CGFloat) {
        guard look != self.look || radius != self.radius else { return }
        (self.look, self.radius) = (look, radius)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The stroke sits inside the bounds, its middle half its width in from the edge, on corners that radius less,
        // so its outer edge follows the window's corners.
        let inset = look.width / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = max(min(radius - inset, rect.width / 2, rect.height / 2), 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        look.fill.setFill()
        path.fill()
        guard look.width > 0 else { return }
        path.lineWidth = look.width
        look.stroke.setStroke()
        path.stroke()
    }
}
