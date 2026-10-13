import CoreGraphics

/// `cycle-size`: step a window through sizes given as shares of its display, the next after the one it has now.
public enum SizeCycle {
    /// How close a share must be to count as one of the sizes: apps that snap to a grid or keep a minimum size
    /// land near a size, not on it.
    public static let tolerance = 0.02

    /// The share after the one `current` is at, wrapping; the first when it is at none of them.
    public static func next(after current: Double, in shares: [Double]) -> Double {
        guard let index = shares.firstIndex(where: { abs($0 - current) <= tolerance }) else { return shares[0] }
        return shares[(index + 1) % shares.count]
    }
}

extension FloatingFrame {
    /// A frame `share` of `area`'s width and height, centred in it. Edges rounded to whole points.
    public static func centered(_ share: Double, in area: CGRect) -> CGRect {
        let width = (area.width * CGFloat(share)).rounded(), height = (area.height * CGFloat(share)).rounded()
        let x = (area.midX - width / 2).rounded(), y = (area.midY - height / 2).rounded()
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension Workspace {
    /// Give the focused window the width after the one it has now among `shares` of the area inside the outer gaps.
    /// A scrolling column takes it as its width; a tile along its nearest horizontal tiles container, its siblings
    /// giving or taking the difference as `resize` has them. False when nothing visibly changed.
    @discardableResult
    public mutating func cycleWidth(through shares: [Double]) -> Bool {
        guard !shares.isEmpty, let focused else { return false }
        endFullscreen()
        if isScrolling {
            guard let column = root.path(of: focused)?.first else { return false }
            let old = width(ofColumn: column)
            let (before, offset) = (tiledLayout(), scrollOffset)
            setWidth(ofColumn: column, SizeCycle.next(after: old, in: shares))
            reveal(focused)
            // A lone column fills the screen whatever its width, so the step is undone, as `resizeColumn` does.
            guard tiledLayout() == before else { return true }
            setWidth(ofColumn: column, old)
            scrollOffset = offset
            return false
        }
        let area = gaps.inset(bounds).width
        guard area > 0, let frame = tiledLayout().frames[focused] else { return false }
        let target = CGFloat(SizeCycle.next(after: Double(frame.width / area), in: shares)) * area
        return resize(by: target - frame.width, along: .horizontal)
    }
}
