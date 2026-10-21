import CoreGraphics

/// The switcher's capsule, in its own coordinates with a top-left origin: a row of thumbnails in the workspace's
/// order, a group's windows side by side a little closer than the columns, or, when their tiles sit apart, as the
/// tiles do on screen, so a column of two stacked shows one over the other; the same padding on every side, as the
/// map's grows with the corner radius. Each thumbnail is `thumbHeight` tall and as wide as its window's aspect gives,
/// within `minThumbWidth` and `maxThumbWidth`, and a group shown as its tiles takes the room its tiles' bounding box
/// would; a row too wide for `maxWidth` is scaled down whole.
public struct SwitcherLayout: Equatable {
    public static let thumbHeight: CGFloat = 100
    public static let minThumbWidth: CGFloat = 64
    public static let maxThumbWidth: CGFloat = 220
    public static let columnGap: CGFloat = 12
    public static let stackGap: CGFloat = 4
    /// Points under the row for its windows' titles, when they show.
    public static let titleHeight: CGFloat = 18
    /// Points kept between the capsule and the screen's edges.
    public static let screenMargin: CGFloat = 8
    /// Points between a capsule shown at the top or bottom and the menu bar or Dock, as the HUD's `offset`.
    public static let edgeMargin: CGFloat = 16

    public let size: CGSize
    /// Each window's thumbnail, in the order given.
    public let frames: [CGRect]

    /// One group of the row: a strip's column, or a part of a tree's root.
    public enum Group: Equatable, Sendable {
        /// Its windows side by side, by their width-to-height ratios.
        case sideBySide([CGFloat])
        /// Its windows where their tiles are, scaled down together.
        case tiles([CGRect])

        /// The windows as their `tiles` sit when there are two or more and none overlaps another, as a column's stacked
        /// windows sit; else side by side by `aspects`, as a lone window, an accordion's windows, or windows with no
        /// tiles (a free workspace's).
        public init(aspects: [CGFloat], tiles: [CGRect]) {
            let apart = tiles.count > 1 && tiles.count == aspects.count && tiles.indices.allSatisfy { i in
                tiles.indices.allSatisfy { j in
                    let overlap = tiles[i].intersection(tiles[j])
                    return j <= i || overlap.isNull || overlap.width < 1 || overlap.height < 1
                }
            }
            self = apart ? .tiles(tiles) : .sideBySide(aspects)
        }
    }

    /// `columns` holds each group's windows' width-to-height ratios, left to right, side by side.
    public init(columns: [[CGFloat]], cornerRadius: CGFloat = 0, maxWidth: CGFloat, titles: Bool = false) {
        self.init(groups: columns.map(Group.sideBySide), cornerRadius: cornerRadius, maxWidth: maxWidth, titles: titles)
    }

    /// `groups` left to right: a strip's columns, or the parts of a tree's root. With `titles`, the capsule is
    /// `titleHeight` taller, for the titles under the thumbnails.
    public init(groups: [Group], cornerRadius: CGFloat = 0, maxWidth: CGFloat, titles: Bool = false) {
        let padding = SwitcherMap.padding(cornerRadius: cornerRadius)
        func thumbWidth(_ aspect: CGFloat) -> CGFloat { min(max(Self.thumbHeight * aspect, Self.minThumbWidth), Self.maxThumbWidth) }
        // A thumbnail's width for each window side by side, or one for the slot a group's tiles share.
        let widths = groups.map { group -> [CGFloat] in
            switch group {
            case .sideBySide(let aspects): return aspects.map(thumbWidth)
            case .tiles(let tiles):
                let box = tiles.reduce(CGRect.null) { $0.union($1) }
                return [thumbWidth(box.height > 0 ? box.width / box.height : 1)]
            }
        }
        let gaps = CGFloat(max(groups.count - 1, 0)) * Self.columnGap
            + widths.reduce(0) { $0 + CGFloat(max($1.count - 1, 0)) } * Self.stackGap
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
                let slot = CGRect(x: x, y: padding, width: scaled, height: height)
                if case .tiles(let tiles) = groups[c] { frames += Self.place(tiles, in: slot) } else { frames.append(slot) }
                x += scaled
            }
        }
        let total = x + padding
        let tall = padding * 2 + height + (titles ? Self.titleHeight : 0)
        size = CGSize(width: max(total, tall), height: tall)
        self.frames = frames
    }

    /// `tiles` scaled from their bounding box into `slot`, `stackGap` apart where one meets another: an edge inside the
    /// box gives up half of it.
    static func place(_ tiles: [CGRect], in slot: CGRect) -> [CGRect] {
        let box = tiles.reduce(CGRect.null) { $0.union($1) }
        guard box.width > 0, box.height > 0 else { return tiles.map { _ in slot } }
        let half = Self.stackGap / 2
        func x(_ v: CGFloat) -> CGFloat { slot.minX + (v - box.minX) / box.width * slot.width }
        func y(_ v: CGFloat) -> CGFloat { slot.minY + (v - box.minY) / box.height * slot.height }
        return tiles.map { tile in
            let minX = (tile.minX > box.minX + 1 ? x(tile.minX) + half : slot.minX).rounded()
            let maxX = (tile.maxX < box.maxX - 1 ? x(tile.maxX) - half : slot.maxX).rounded()
            let minY = (tile.minY > box.minY + 1 ? y(tile.minY) + half : slot.minY).rounded()
            let maxY = (tile.maxY < box.maxY - 1 ? y(tile.maxY) - half : slot.maxY).rounded()
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    /// The thumbnail at `point` in the capsule: the nearest, so across a row each reaches halfway into the gaps beside
    /// it and the first and last on past the ends, and a column's stacked thumbnails split it by height. Nil with no
    /// thumbnails.
    public func index(at point: CGPoint) -> Int? {
        func distance(_ frame: CGRect) -> CGFloat {
            hypot(max(frame.minX - point.x, 0, point.x - frame.maxX), max(frame.minY - point.y, 0, point.y - frame.maxY))
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) }
    }

    /// The thumbnail a key picks from `index` of `count` in a row: left and up the one before, right and down the one
    /// after, round from one end to the other.
    public static func step(_ index: Int, count: Int, toward direction: Direction) -> Int {
        guard count > 0 else { return 0 }
        let forward = direction == .right || direction == .down
        return ((index + (forward ? 1 : -1)) % count + count) % count
    }

    /// The indices of `frames` as they read: left to right by their left edges, those within a point of each other
    /// top to bottom. The switchers hand out their letters in this order.
    public static func readingOrder(_ frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            let (fa, fb) = (frames[a], frames[b])
            if abs(fa.minX - fb.minX) > 1 { return fa.minX < fb.minX }
            if abs(fa.minY - fb.minY) > 1 { return fa.minY < fb.minY }
            return a < b
        }
    }

    /// Where a capsule of `size` goes to sit in the middle of `visible`, in global coordinates (top-left origin).
    public static func centred(_ size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
    }

    /// Where a capsule of `size` goes across the middle of `visible`, `edgeMargin` below its top (the menu bar) or above
    /// its bottom (the Dock), in global coordinates (top-left origin).
    public static func edge(_ size: CGSize, in visible: CGRect, top: Bool) -> CGPoint {
        let y = top ? visible.minY + edgeMargin : max(visible.maxY - edgeMargin - size.height, visible.minY)
        return CGPoint(x: (visible.midX - size.width / 2).rounded(), y: y.rounded())
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
