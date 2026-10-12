import AppKit
import DinkyConfig
import DinkyLayout

// While a tiled window is dragged: a quiet outline of the tile it came from, kept below the dragged window, and
// over the tile under the pointer the drop's feedback, as yabai's insert feedback shows it: an accent border with a
// translucent fill over the part the window will take, the whole tile for a swap, the half on that side for a
// split, with a faint outline of the tile around a half. The pointer is on the dragged window, so the feedback goes
// above it to be seen. Borderless panels that never take focus or clicks. They move between tiles and halves,
// gliding briefly when animations are on; nothing reflows until the drop. `[drag]` can set the preview's colours
// and the width of every outline, and turn the home outline off; the faint tile outline follows the preview's border.
// A swap is drawn heavier than a split, and lights up the dragged window's own tile too, where the other window will
// go: the dragged window mostly covers the tile it would swap with.
final class DragPlaceholders {
    private lazy var home = Self.panel(PlaceholderView(stroke: .secondaryLabelColor.withAlphaComponent(0.45),
                                                       fill: .secondaryLabelColor.withAlphaComponent(0.06)))
    private lazy var tile = Self.panel(PlaceholderView(stroke: .controlAccentColor.withAlphaComponent(0.4), fill: .clear))
    private lazy var preview = Self.panel(PlaceholderView(stroke: .controlAccentColor,
                                                          fill: .controlAccentColor.withAlphaComponent(0.3)))
    /// The same look as the preview, over the dragged window's tile while a drop would swap.
    private lazy var swapHome = Self.panel(PlaceholderView(stroke: .controlAccentColor,
                                                           fill: .controlAccentColor.withAlphaComponent(0.45)))
    private var style: Drag?
    private var splitLook = Look(stroke: .controlAccentColor, fill: .controlAccentColor.withAlphaComponent(0.3), width: 3)
    private var swapLook = Look(stroke: .controlAccentColor, fill: .controlAccentColor.withAlphaComponent(0.45), width: 6)

    private struct Look {
        var stroke: NSColor
        var fill: NSColor
        var width: CGFloat
    }
    /// Where each panel was last asked to go, so a glide under way is not restarted towards the same place.
    private var placed: [ObjectIdentifier: CGRect] = [:]

    private static let glide: TimeInterval = 0.08

    /// Show the outlines for a window being dragged: `home` is its tile, `target` the tile it would drop onto and
    /// `preview` the part of it the window would take, all of it for a `swap`, which also lights up `home`.
    /// `outlinesHome` shows the quiet outline of `home` the rest of the time. Rects are top-left global, as tiles are.
    /// `squareEdge` is the preview's edge along a split, towards the tile's middle, drawn with square corners.
    func show(dragged: WindowID, home homeRect: CGRect, outlinesHome: Bool, target targetRect: CGRect?,
              preview previewRect: CGRect?, swap: Bool, squareEdge: Direction?, cornerRadius: CGFloat, animated: Bool) {
        let swapping = swap && previewRect != nil
        let look = swapping ? swapLook : splitLook
        view(preview).set(stroke: look.stroke, fill: look.fill, width: look.width)
        view(preview).squareEdge = squareEdge
        if swapping {
            hide(home)
            // Below the dragged window, as its tile is: where it shows past the window, the other window will go.
            place(swapHome, at: homeRect, .below, dragged, cornerRadius: cornerRadius, animated: false)
        } else {
            hide(swapHome)
            if outlinesHome {
                place(home, at: homeRect, .below, dragged, cornerRadius: cornerRadius, animated: false)
            } else {
                hide(home)
            }
        }
        // Each goes straight above the dragged window, so the preview, placed first, ends up above the tile.
        if let previewRect {
            place(preview, at: previewRect, .above, dragged, cornerRadius: cornerRadius, animated: animated)
        } else {
            hide(preview)
        }
        if let targetRect, let previewRect, previewRect != targetRect {
            place(tile, at: targetRect, .above, dragged, cornerRadius: cornerRadius, animated: false)
        } else {
            hide(tile)
        }
    }

    func hide() {
        for panel in [home, tile, preview, swapHome] { hide(panel) }
    }

    /// Take the preview's colours and the outlines' width from `[drag]`. Unset colours follow the accent colour.
    func update(style drag: Drag) {
        guard drag != style else { return }
        style = drag
        let border = drag.previewBorderColor.map(Self.nsColor) ?? .controlAccentColor
        let fill = drag.previewFillColor.map(Self.nsColor) ?? border.withAlphaComponent(border.alphaComponent * 0.3)
        let width = CGFloat(drag.previewBorderWidth)
        splitLook = Look(stroke: border, fill: fill, width: width)
        // A swap: a heavier border and a stronger fill than a split.
        swapLook = Look(stroke: border, fill: fill.withAlphaComponent(min(fill.alphaComponent * 1.5, 0.6)),
                        width: max(width + 3, 4))
        view(swapHome).set(stroke: swapLook.stroke, fill: swapLook.fill, width: swapLook.width)
        view(tile).set(stroke: border.withAlphaComponent(border.alphaComponent * 0.4), fill: .clear, width: width)
        view(home).set(stroke: .secondaryLabelColor.withAlphaComponent(0.45),
                       fill: .secondaryLabelColor.withAlphaComponent(0.06), width: width)
    }

    private func view(_ panel: NSPanel) -> PlaceholderView { panel.contentView as! PlaceholderView }

    private static func nsColor(_ color: DinkyConfig.Color) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private func hide(_ panel: NSPanel) {
        panel.orderOut(nil)
        placed[ObjectIdentifier(panel)] = nil
    }

    private func place(_ panel: NSPanel, at rect: CGRect, _ side: NSWindow.OrderingMode, _ window: WindowID,
                       cornerRadius: CGFloat, animated: Bool) {
        (panel.contentView as! PlaceholderView).cornerRadius = cornerRadius
        let frame = Self.appKitFrame(rect), key = ObjectIdentifier(panel)
        // A panel coming into view appears where it goes; one already showing glides there.
        if placed[key] != frame {
            if animated, placed[key] != nil, panel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.glide
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
            placed[key] = frame
        }
        panel.order(side, relativeTo: Int(window))
    }

    private static func panel(_ view: PlaceholderView) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.contentView = view
        return panel
    }

    /// Top-left global to AppKit's bottom-left, flipped around the primary screen.
    private static func appKitFrame(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

private final class PlaceholderView: NSView {
    private var stroke: NSColor
    private var fill: NSColor
    private var width: CGFloat = 3
    var cornerRadius: CGFloat = 10 { didSet { if cornerRadius != oldValue { needsDisplay = true } } }
    /// The edge whose two corners are square, nil for all four rounded.
    var squareEdge: Direction? { didSet { if squareEdge != oldValue { needsDisplay = true } } }

    init(stroke: NSColor, fill: NSColor) {
        self.stroke = stroke
        self.fill = fill
        super.init(frame: .zero)
        // Redrawn at every size a glide passes through, not stretched from the last drawing.
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(stroke: NSColor, fill: NSColor, width: CGFloat) {
        guard stroke != self.stroke || fill != self.fill || width != self.width else { return }
        (self.stroke, self.fill, self.width) = (stroke, fill, width)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The stroke sits inside the bounds, half its width in from the edge.
        let inset = width / 2
        let path = Self.path(bounds.insetBy(dx: inset, dy: inset), radius: cornerRadius, square: squareEdge)
        fill.setFill()
        path.fill()
        guard width > 0 else { return }
        path.lineWidth = width
        stroke.setStroke()
        path.stroke()
    }

    /// A rounded rectangle whose corners on `square` have no radius. The view is not flipped: up is maxY.
    private static func path(_ r: CGRect, radius: CGFloat, square: Direction?) -> NSBezierPath {
        guard let square else { return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
        let radius = min(radius, r.width / 2, r.height / 2)
        // Corners counter-clockwise from the middle of the bottom edge, each with the two edges it joins.
        let corners: [(CGPoint, Set<Direction>)] = [
            (CGPoint(x: r.maxX, y: r.minY), [.right, .down]), (CGPoint(x: r.maxX, y: r.maxY), [.right, .up]),
            (CGPoint(x: r.minX, y: r.maxY), [.left, .up]), (CGPoint(x: r.minX, y: r.minY), [.left, .down]),
        ]
        let path = NSBezierPath()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        for (i, corner) in corners.enumerated() {
            let next = corners[(i + 1) % 4].0
            path.appendArc(from: corner.0, to: next, radius: corner.1.contains(square) ? 0 : radius)
        }
        path.close()
        return path
    }
}
