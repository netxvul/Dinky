import CoreGraphics

/// The switcher's capsule, in its own coordinates with a top-left origin: a row of thumbnails in the workspace's
/// order, a group's windows side by side a little closer than the columns, the same padding on every side, as the
/// map's grows with the corner radius. Each thumbnail is `thumbHeight` tall and as wide as its window's aspect gives,
/// within `minThumbWidth` and `maxThumbWidth`; a row too wide for `maxWidth` is scaled down whole.
public struct SwitcherLayout: Equatable {
    public static let thumbHeight: CGFloat = 100
    public static let minThumbWidth: CGFloat = 64
    public static let maxThumbWidth: CGFloat = 220
    public static let columnGap: CGFloat = 12
    public static let stackGap: CGFloat = 4
    /// Points kept between the capsule and the screen's edges.
    public static let screenMargin: CGFloat = 8

    public let size: CGSize
    /// Each window's thumbnail, in the order given.
    public let frames: [CGRect]

    /// `columns` holds each group's windows' width-to-height ratios, left to right: a strip's columns, or the parts of
    /// a tree's root.
    public init(columns: [[CGFloat]], cornerRadius: CGFloat = 0, maxWidth: CGFloat) {
        let padding = SwitcherMap.padding(cornerRadius: cornerRadius)
        let widths = columns.map { $0.map { min(max(Self.thumbHeight * $0, Self.minThumbWidth), Self.maxThumbWidth) } }
        let gaps = CGFloat(max(columns.count - 1, 0)) * Self.columnGap
            + columns.reduce(0) { $0 + CGFloat(max($1.count - 1, 0)) } * Self.stackGap
        let natural = widths.joined().reduce(0, +)
        let room = maxWidth - padding * 2 - gaps
        let scale = natural > room && natural > 0 ? max(room, 0) / natural : 1
        let height = (Self.thumbHeight * scale).rounded()
        var frames: [CGRect] = []
        var x = padding
        for (c, column) in widths.enumerated() {
            if c > 0 { x += Self.columnGap }
            for (w, width) in column.enumerated() {
                if w > 0 { x += Self.stackGap }
                // Down, so a row scaled to fit stays inside `maxWidth`.
                let scaled = (width * scale).rounded(.down)
                frames.append(CGRect(x: x, y: padding, width: scaled, height: height))
                x += scaled
            }
        }
        let total = x + padding
        let tall = padding * 2 + height
        size = CGSize(width: max(total, tall), height: tall)
        self.frames = frames
    }

    /// The thumbnail at `x` across the capsule: the one whose span, extended halfway into the gaps beside it, holds
    /// `x`, the first or last beyond the ends. Nil with no thumbnails.
    public func index(atX x: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        for i in frames.indices.dropLast() where x < (frames[i].maxX + frames[i + 1].minX) / 2 { return i }
        return frames.count - 1
    }

    /// The thumbnail a key picks from `index` of `count` in a row: left and up the one before, right and down the one
    /// after, round from one end to the other.
    public static func step(_ index: Int, count: Int, toward direction: Direction) -> Int {
        guard count > 0 else { return 0 }
        let forward = direction == .right || direction == .down
        return ((index + (forward ? 1 : -1)) % count + count) % count
    }

    /// Where a capsule of `size` goes to sit in the middle of `visible`, in global coordinates (top-left origin).
    public static func centred(_ size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
    }

    /// Where the capsule goes in global coordinates (top-left origin): thumbnail `anchor` centred on `pointer`, kept
    /// `screenMargin` inside `visible`.
    public func origin(anchor: Int, pointer: CGPoint, visible: CGRect) -> CGPoint {
        let centre = frames.indices.contains(anchor) ? CGPoint(x: frames[anchor].midX, y: frames[anchor].midY)
                                                     : CGPoint(x: size.width / 2, y: size.height / 2)
        let margin = Self.screenMargin
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(v, low), max(high, low)) }
        let x = clamp(pointer.x - centre.x, visible.minX + margin, visible.maxX - margin - size.width)
        let y = clamp(pointer.y - centre.y, visible.minY + margin, visible.maxY - margin - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
