import CoreGraphics

/// A workspace drawn small for the workspace switcher, in the card's own coordinates with a top-left origin: the
/// display scaled to `height` with its own proportions, each window where it is now. A tree's windows as its layout
/// puts them, an accordion's neighbours peeking out by at least `minimumPeek` so they show at this size, and those
/// another window covers marked `behind`; a fixed workspace's empty cells; a strip's columns in view only, pulled in
/// from the sides to leave room for a sliver of each side that has columns parked off screen, with their count; and
/// floating windows over everything, as given. A workspace with a window fullscreen shows that one alone.
public struct Miniature: Equatable {
    public struct Tile: Equatable {
        public let id: WindowID
        public let frame: CGRect
        /// Under another window, as an accordion's neighbours are.
        public let behind: Bool
    }

    /// Points a neighbour in an accordion peeks out by in the card, at the least.
    public static let minimumPeek: CGFloat = 5
    /// Points between neighbouring tiles, half on each.
    public static let tileGap: CGFloat = 2
    /// Share of the card's width kept at each side of a strip with columns parked off screen.
    public static let parkedInset: CGFloat = 0.1
    /// Share of the card's width a parked sliver takes.
    public static let parkedSliver: CGFloat = 0.055

    public let size: CGSize
    /// Back to front.
    public private(set) var tiles: [Tile] = []
    public private(set) var emptyCells: [CGRect] = []
    /// Columns of a strip off screen to the left and to the right.
    public private(set) var parkedLeft = 0
    public private(set) var parkedRight = 0
    public private(set) var fullscreen = false

    /// `screen` is the display's frame, in the coordinates of the workspace's and the windows' frames. `known` says
    /// which of the workspace's windows to draw. `floating` is back to front.
    public init(screen: CGRect, height: CGFloat, workspace: Workspace?, known: (WindowID) -> Bool = { _ in true },
                floating: [(id: WindowID, frame: CGRect)] = []) {
        let scale = screen.height > 0 ? height / screen.height : 0
        size = CGSize(width: (screen.width * scale).rounded(), height: height)
        func map(_ rect: CGRect, x0: CGFloat = 0, xScale: CGFloat = scale) -> CGRect {
            let x = (x0 + (rect.minX - screen.minX) * xScale).rounded(), y = ((rect.minY - screen.minY) * scale).rounded()
            let maxX = (x0 + (rect.maxX - screen.minX) * xScale).rounded(), maxY = ((rect.maxY - screen.minY) * scale).rounded()
            let half = Self.tileGap / 2
            return CGRect(x: x, y: y, width: maxX - x, height: maxY - y).insetBy(dx: half, dy: half)
        }
        if let workspace, scale > 0 {
            if let id = workspace.fullscreenWindows.first(where: known), let frame = workspace.layout().frames[id] {
                fullscreen = true
                tiles = [Tile(id: id, frame: map(frame), behind: false)]
            } else if workspace.isScrolling {
                let strip = workspace.tiledLayout().frames
                var shown: [(WindowID, CGRect)] = [], pinned: [(WindowID, CGRect)] = []
                for column in workspace.root.children {
                    let ids = column.windows.filter { known($0) && strip[$0] != nil }
                    guard let first = ids.first else { continue }
                    let frames = ids.map { strip[$0]! }
                    // Pins in place, over the band; a band column under one is out of view.
                    if workspace.pinSide(of: first) != nil {
                        pinned += zip(ids, frames)
                    } else if workspace.isInView(first) {
                        shown += zip(ids, frames)
                    } else if strip[first]!.midX < (workspace.pinnedWindows.isEmpty ? workspace.bounds.midX
                                                     : workspace.bandRect.midX) {
                        parkedLeft += 1
                    } else {
                        parkedRight += 1
                    }
                }
                let parked = parkedLeft + parkedRight > 0
                let inset = parked ? (size.width * Self.parkedInset).rounded() : 0
                let xScale = parked && screen.width > 0 ? (size.width - inset * 2) / screen.width : scale
                tiles = (shown + pinned).map { Tile(id: $0.0, frame: map($0.1, x0: inset, xScale: xScale), behind: false) }
            } else {
                var roomy = workspace
                roomy.accordionPadding = max(workspace.accordionPadding, Self.minimumPeek / scale)
                let layout = roomy.layout()
                let order = layout.order.filter { known($0) && layout.frames[$0] != nil }
                // Front to back, each behind any in front of it that it overlaps.
                var front: [CGRect] = []
                for id in order {
                    let frame = map(layout.frames[id]!)
                    let behind = front.contains { $0.intersection(frame).width > 1 && $0.intersection(frame).height > 1 }
                    tiles.insert(Tile(id: id, frame: frame, behind: behind), at: 0)
                    front.append(frame)
                }
                if case .fixed = workspace.algorithm {
                    let empty = layout.containerRects.filter { path, _ in
                        guard !path.isEmpty, case .container(let c) = roomy.root.node(at: path) else { return false }
                        return Node.container(c).windows.isEmpty
                    }.values
                    // An empty container inside another counts once, as the outer one.
                    emptyCells = empty.filter { rect in !empty.contains { $0 != rect && $0.contains(rect) } }
                        .map { map($0) }.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
                }
            }
        }
        if scale > 0 {
            tiles += floating.map { Tile(id: $0.id, frame: map($0.frame), behind: false) }
        }
    }

    /// Where the sliver of a side's parked columns goes, nil when that side has none.
    public func parkedSliver(left: Bool) -> CGRect? {
        guard left ? parkedLeft > 0 : parkedRight > 0 else { return nil }
        let width = max((size.width * Self.parkedSliver).rounded(), 3), inset = (size.height * 0.06).rounded()
        return CGRect(x: left ? 0 : size.width - width, y: inset, width: width, height: size.height - inset * 2)
    }
}

/// A layout as the workspace switcher's schematic cards draw it: a fixed picture of the kind of layout, the same
/// whatever windows the workspace has.
public enum Schematic: Equatable, Sendable {
    /// One window on one side, two stacked on the other: `horizontal` side by side, `vertical` one over the other.
    case tiles(Orientation)
    /// Three windows, the front one with its neighbours peeking out along `orientation`.
    case accordion(Orientation)
    /// Two columns in view, the second a stack of two, and a sliver of a parked column each side.
    case scrolling
    /// A window in every cell of the template, at most four each way.
    case fixed(rows: Int, columns: Int)
    /// Three windows of different sizes overlapping.
    case floating
    /// One window filling the display.
    case fullscreen
}

extension Miniature {
    /// Points between a schematic card's edge and its windows, and between neighbouring windows.
    public static let schematicGap: CGFloat = 3

    /// The fixed picture of `schematic` on a card of the display `screen` scaled to `height`: windows a clear gap
    /// apart and from the edge, numbered from 1, back to front.
    public init(schematic: Schematic, screen: CGRect, height: CGFloat) {
        self.init(screen: screen, height: height, workspace: nil)
        let w = size.width, h = size.height, g = Self.schematicGap
        let area = CGRect(x: g, y: g, width: w - g * 2, height: h - g * 2)
        /// `r` in two along `axis`, a gap between.
        func split(_ r: CGRect, _ axis: Orientation) -> (CGRect, CGRect) {
            axis == .horizontal
                ? (CGRect(x: r.minX, y: r.minY, width: (r.width - g) / 2, height: r.height),
                   CGRect(x: r.minX + (r.width + g) / 2, y: r.minY, width: (r.width - g) / 2, height: r.height))
                : (CGRect(x: r.minX, y: r.minY, width: r.width, height: (r.height - g) / 2),
                   CGRect(x: r.minX, y: r.minY + (r.height + g) / 2, width: r.width, height: (r.height - g) / 2))
        }
        var frames: [(CGRect, Bool)] = []
        switch schematic {
        case .tiles(let axis):
            let (first, rest) = split(area, axis)
            let (a, b) = split(rest, axis.opposite)
            frames = [(first, false), (a, false), (b, false)]
        case .accordion(let axis):
            let along = axis == .horizontal ? area.width : area.height
            let peek = max(Self.minimumPeek + 2, (along * 0.06).rounded())
            func at(_ offset: CGFloat) -> CGRect {
                axis == .horizontal
                    ? CGRect(x: area.minX + offset, y: area.minY, width: area.width - peek * 2, height: area.height)
                    : CGRect(x: area.minX, y: area.minY + offset, width: area.width, height: area.height - peek * 2)
            }
            frames = [(at(0), true), (at(peek * 2), true), (at(peek), false)]
        case .scrolling:
            // The columns in view pulled in, room either side for a parked column's sliver and a gap.
            let inset = max((w * Self.parkedInset).rounded(), g * 2 + 4)
            let (first, second) = split(CGRect(x: inset, y: area.minY, width: w - inset * 2, height: area.height), .horizontal)
            let (a, b) = split(second, .vertical)
            frames = [(first, false), (a, false), (b, false)]
            parkedLeft = 1
            parkedRight = 1
        case .fixed(let rows, let columns):
            let rows = min(max(rows, 1), 4), columns = min(max(columns, 1), 4)
            let cw = (area.width - g * CGFloat(columns - 1)) / CGFloat(columns)
            let ch = (area.height - g * CGFloat(rows - 1)) / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<columns {
                    frames.append((CGRect(x: area.minX + CGFloat(c) * (cw + g), y: area.minY + CGFloat(r) * (ch + g),
                                          width: cw, height: ch), false))
                }
            }
        case .floating:
            frames = [(CGRect(x: w * 0.08, y: h * 0.1, width: w * 0.5, height: h * 0.56), false),
                      (CGRect(x: w * 0.38, y: h * 0.26, width: w * 0.54, height: h * 0.62), false),
                      (CGRect(x: w * 0.12, y: h * 0.52, width: w * 0.3, height: h * 0.38), false)]
        case .fullscreen:
            frames = [(area, false)]
            fullscreen = true
        }
        tiles = frames.enumerated().map { i, entry in
            let r = entry.0
            let x = r.minX.rounded(), y = r.minY.rounded()
            return Tile(id: WindowID(i + 1), frame: CGRect(x: x, y: y, width: r.maxX.rounded() - x, height: r.maxY.rounded() - y),
                        behind: entry.1)
        }
    }

    /// Where a schematic card's sliver of a side's parked column goes: hanging off the edge, as tall as the
    /// windows. Nil when that side has none.
    public func schematicSliver(left: Bool) -> CGRect? {
        guard left ? parkedLeft > 0 : parkedRight > 0 else { return nil }
        let g = Self.schematicGap, width = max((size.width * 0.045).rounded(), 4)
        return CGRect(x: left ? 0 : size.width - width, y: g, width: width, height: size.height - g * 2)
    }
}
