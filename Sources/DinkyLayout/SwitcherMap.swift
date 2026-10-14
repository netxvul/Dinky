import CoreGraphics

/// The switcher's capsule as a map of a tiled workspace, in its own coordinates with a top-left origin: each window's
/// tile scaled down to `height` with the workspace's proportions, a gap of `cellGap` between neighbours. The padding
/// around the tiles grows with the corner radius so the corners never clip a tile, and a map too wide for `maxWidth`
/// is scaled down whole.
public struct SwitcherMap: Equatable {
    public static let height: CGFloat = 220
    public static let minPadding: CGFloat = 14
    public static let cellGap: CGFloat = 4

    public let size: CGSize
    /// Each window's cell, in the order of the frames given.
    public let frames: [CGRect]

    /// `tiles` are the windows' tiles and `bounds` the workspace's area, in any one coordinate space.
    public init(tiles: [CGRect], bounds: CGRect, cornerRadius: CGFloat, maxWidth: CGFloat) {
        let padding = Self.padding(cornerRadius: cornerRadius)
        guard bounds.width > 0, bounds.height > 0 else {
            size = CGSize(width: padding * 2, height: padding * 2)
            frames = tiles.map { _ in .zero }
            return
        }
        var scale = (Self.height - padding * 2) / bounds.height
        if bounds.width * scale + padding * 2 > maxWidth { scale = max(maxWidth - padding * 2, 0) / bounds.width }
        size = CGSize(width: (bounds.width * scale + padding * 2).rounded(), height: (bounds.height * scale + padding * 2).rounded())
        let half = Self.cellGap / 2
        frames = tiles.map { tile in
            let x = (padding + (tile.minX - bounds.minX) * scale).rounded()
            let y = (padding + (tile.minY - bounds.minY) * scale).rounded()
            let maxX = (padding + (tile.maxX - bounds.minX) * scale).rounded()
            let maxY = (padding + (tile.maxY - bounds.minY) * scale).rounded()
            return CGRect(x: x, y: y, width: maxX - x, height: maxY - y).insetBy(dx: half, dy: half)
        }
    }

    /// Room for the corners: at least `minPadding`, and as far in as a corner of that radius reaches along the
    /// diagonal, about 0.3 of it.
    public static func padding(cornerRadius: CGFloat) -> CGFloat {
        max(minPadding, (cornerRadius * (1 - 1 / 2.squareRoot())).rounded(.up))
    }

    /// The cell under `point`, else the nearest. Nil with no cells.
    public func index(at point: CGPoint) -> Int? {
        if let i = frames.firstIndex(where: { $0.contains(point) }) { return i }
        func distance(_ r: CGRect) -> CGFloat {
            hypot(max(r.minX - point.x, 0, point.x - r.maxX), max(r.minY - point.y, 0, point.y - r.maxY))
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) }
    }

    /// The cell a key in `direction` picks from cell `index`: of the cells whose centres lie that way and that share
    /// some of its span across the way, the nearest, counting a step across twice as far as one along. Nil when there
    /// is none.
    public func neighbor(of index: Int, toward direction: Direction) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let from = CGPoint(x: frames[index].midX, y: frames[index].midY)
        func score(_ i: Int) -> CGFloat? {
            let dx = frames[i].midX - from.x, dy = frames[i].midY - from.y
            let (along, across) = switch direction {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .up: (-dy, dx)
            case .down: (dy, dx)
            }
            let other = frames[i], here = frames[index]
            let shares = direction == .left || direction == .right
                ? other.minY < here.maxY && other.maxY > here.minY
                : other.minX < here.maxX && other.maxX > here.minX
            return along > 1 && shares ? along + abs(across) * 2 : nil
        }
        return frames.indices.filter { $0 != index }.compactMap { i in score(i).map { (i, $0) } }.min { $0.1 < $1.1 }?.0
    }

    /// Where the map goes in global coordinates (top-left origin): cell `anchor` centred on `pointer`, kept
    /// `SwitcherLayout.screenMargin` inside `visible`.
    public func origin(anchor: Int, pointer: CGPoint, visible: CGRect) -> CGPoint {
        let centre = frames.indices.contains(anchor) ? CGPoint(x: frames[anchor].midX, y: frames[anchor].midY)
                                                     : CGPoint(x: size.width / 2, y: size.height / 2)
        let margin = SwitcherLayout.screenMargin
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(v, low), max(high, low)) }
        let x = clamp(pointer.x - centre.x, visible.minX + margin, visible.maxX - margin - size.width)
        let y = clamp(pointer.y - centre.y, visible.minY + margin, visible.maxY - margin - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

extension Workspace {
    /// Each tiled window's tile, without fullscreen or a strip's parking: what the switcher's map shows.
    public var tileFrames: [WindowID: CGRect] { tiledLayout().frames }
}
