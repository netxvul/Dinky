import CoreGraphics

// Where tiling commands put a floating window. `area` is the display's visible area inside its outer gaps;
// results are kept inside it and edges are rounded to whole points. Top-left origin, as AX uses.

/// The point of a floating window that stays put while `resize` changes its size.
public enum ResizeAnchor: String, Equatable, Sendable {
    case center
    case topLeft = "top-left"
}

public enum FloatingFrame {
    /// The smallest a floating window is resized to.
    public static let minimumSize = CGSize(width: 100, height: 100)

    /// `frame` shifted `step` points in a direction, the same size, stopping at the edge of `area`.
    public static func moved(_ frame: CGRect, _ direction: Direction, by step: CGFloat, within area: CGRect) -> CGRect {
        var moved = frame
        switch direction {
        case .left: moved.origin.x -= step
        case .right: moved.origin.x += step
        case .up: moved.origin.y -= step
        case .down: moved.origin.y += step
        }
        return inside(moved, area)
    }

    /// `frame` grown by `delta` points (shrunk when negative) about `anchor`: in width, height, or with no axis both.
    /// No smaller than `minimumSize`, no larger than `area`, and kept inside it, so a window against an edge grows
    /// away from it.
    public static func resized(_ frame: CGRect, by delta: CGFloat, along axis: Orientation?, within area: CGRect,
                               anchor: ResizeAnchor = .center) -> CGRect {
        func extent(_ current: CGFloat, minimum: CGFloat, maximum: CGFloat, changes: Bool) -> CGFloat {
            min(max(changes ? current + delta : current, min(minimum, maximum)), maximum)
        }
        let width = extent(frame.width, minimum: minimumSize.width, maximum: area.width, changes: axis != .vertical)
        let height = extent(frame.height, minimum: minimumSize.height, maximum: area.height, changes: axis != .horizontal)
        let origin = switch anchor {
        case .center: CGPoint(x: frame.midX - width / 2, y: frame.midY - height / 2)
        case .topLeft: frame.origin
        }
        return inside(CGRect(origin: origin, size: CGSize(width: width, height: height)), area)
    }

    /// The frame a floating window fills the display with: all of `area`, as fullscreen gives a tile.
    public static func filling(_ area: CGRect) -> CGRect { rounded(area) }

    /// `frame` moved inside `area`; along an axis it is too big for, against the top or left edge.
    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        let x = max(min(frame.minX, area.maxX - frame.width), area.minX)
        let y = max(min(frame.minY, area.maxY - frame.height), area.minY)
        return rounded(CGRect(x: x, y: y, width: frame.width, height: frame.height))
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }
}
