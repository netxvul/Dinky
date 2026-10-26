import CoreGraphics

// Pinned columns, after SlideScroll's: a column of the strip held at the left or right side of the screen while the
// rest scroll between, in the band. A pinned column stays in the tree, as the strip's first column (left) or its last
// (right), so stacking, joining, the switchers and drops treat it as any column; the workspace only marks which
// column each side holds, by one of its windows, and the slot rules: a mark whose window has left the end column is
// dropped, the columns never moved for it (`settlePins`). Each side holds one column at most. Pinned, a column keeps
// its share of the area inside the outer gaps, the band never narrower than `minimumBandShare` of it nor than its
// widest window takes. Unpinned, it goes back between the columns it was pinned from. Outside the scrolling layout
// the marks sleep, kept for when it scrolls again.

/// A side of the screen a column can be pinned to.
public enum PinSide: String, Equatable, Hashable, Sendable, CaseIterable {
    case left, right

    /// The direction from the band towards this side.
    public var direction: Direction { self == .left ? .left : .right }

    /// The side `direction` points to, nil for up and down.
    public init?(_ direction: Direction) {
        switch direction {
        case .left: self = .left
        case .right: self = .right
        case .up, .down: return nil
        }
    }
}

/// Where a pinned column was in the band: a window of the column left of it and of the one right of it, nil at an end.
public struct PinOrigin: Equatable, Sendable {
    var before: WindowID?
    var after: WindowID?
}

/// What a `pin` or `unpin` did.
public enum PinChange: Equatable, Sendable {
    /// The column was pinned or unpinned.
    case changed
    /// It already was as asked.
    case unchanged
    /// It could not be, for the reason given.
    case refused(String)
}

extension Workspace {
    /// The narrowest the band goes, as a share of the area inside the outer gaps.
    public static let minimumBandShare = 0.25

    /// Counts marks `settlePins` dropped, which only an edit that moved a pinned column off its end would leave: tests
    /// assert it stays 0.
    nonisolated(unsafe) public static var pinsSettled = 0

    /// The index of the column pinned to `side`, nil when none is or the layout does not scroll.
    func pinnedIndex(_ side: PinSide) -> Int? {
        guard isScrolling, let id = pins[side], !root.children.isEmpty else { return nil }
        let slot = side == .left ? 0 : root.children.count - 1
        return root.children[slot].windows.contains(id) ? slot : nil
    }

    /// The side `id`'s column is pinned to, nil when it is in the band or not here.
    public func pinSide(of id: WindowID) -> PinSide? {
        PinSide.allCases.first { side in pinnedIndex(side).map { root.children[$0].windows.contains(id) } ?? false }
    }

    /// The side the column at `index` is pinned to, if any.
    func pinSide(ofColumn index: Int) -> PinSide? {
        PinSide.allCases.first { pinnedIndex($0) == index }
    }

    /// The windows of the pinned columns, left one first.
    public var pinnedWindows: [WindowID] {
        PinSide.allCases.compactMap(pinnedIndex).flatMap { root.children[$0].windows }
    }

    /// The width of the pinned column at `index` along the strip: its share of the area inside the outer gaps, grown to
    /// what its windows take, a half inner gap of it towards the band.
    func pinSpan(_ index: Int) -> CGFloat {
        let gap = gaps.horizontal
        let minimum = root.children[index].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
        return max((gaps.inset(bounds).width * CGFloat(width(ofColumn: index))).rounded(), minimum + gap / 2)
    }

    /// Where the pinned column at `index` goes: from the outer gap on its side, its span less the half gap towards
    /// the band, the strip's height.
    func pinRect(_ index: Int) -> CGRect {
        let inset = gaps.inset(bounds), width = pinSpan(index) - gaps.horizontal / 2
        let x = index == 0 && pinnedIndex(.left) == 0 ? inset.minX : inset.maxX - width
        return CGRect(x: x, y: inset.minY, width: width, height: inset.height)
    }

    /// Whether the band keeps room enough: `minimumBandShare` of the area inside the outer gaps, and its widest column.
    var bandHasRoom: Bool {
        let gap = gaps.horizontal, band = bandRange
        let widest = band.map {
            root.children[$0].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
        }.max() ?? 0
        let room = stripInset.width
        return room >= gaps.inset(bounds).width * CGFloat(Self.minimumBandShare) - 0.5 && room >= widest + gap - 0.5
    }

    /// Pin the focused window's column to `side`. Pinned there already, it stays, or with `toggle` is unpinned; pinned to
    /// the other side, it moves across. A column already pinned to `side` goes back to where it was pinned from. With
    /// `freeSideOnly`, as a rule pins, a side another column holds is left to it. Refused outside the scrolling layout,
    /// with nothing focused, or where the band would be left too little room.
    @discardableResult
    public mutating func pin(_ side: PinSide, toggle: Bool = false, freeSideOnly: Bool = false) -> PinChange {
        guard isScrolling else { return .refused("only a scrolling strip pins columns") }
        guard let focused, let column = root.path(of: focused)?.first else { return .refused("nothing to pin") }
        if let pinned = pinSide(ofColumn: column) {
            if pinned == side { return toggle ? unpin(side) : .unchanged }
        } else if freeSideOnly, pinnedIndex(side) != nil {
            return .refused("the \(side.rawValue) side is pinned already")
        }
        var pinned = self
        pinned.endFullscreen()
        if let from = pinned.pinSide(ofColumn: column) {
            // Across from the other side, its origin going with it.
            let node = pinned.root.children[column]
            let origin = pinned.pinOrigins.removeValue(forKey: from)
            pinned.pins[from] = nil
            pinned.root.remove(at: column)
            if pinned.pinnedIndex(side) != nil { _ = pinned.unpin(side) }
            pinned.place(node, pinnedTo: side, by: focused, origin: origin ?? PinOrigin())
        } else {
            let band = pinned.bandRange, windows = pinned.root.children.map(\.windows)
            let origin = PinOrigin(before: column > band.lowerBound ? windows[column - 1].first : nil,
                                   after: column < band.upperBound - 1 ? windows[column + 1].first : nil)
            if pinned.pinnedIndex(side) != nil { _ = pinned.unpin(side) }
            guard let index = pinned.root.path(of: focused)?.first else { return .refused("nothing to pin") }
            let node = pinned.root.children[index]
            pinned.root.remove(at: index)
            pinned.place(node, pinnedTo: side, by: focused, origin: origin)
            // Focus goes back from the pin to where the column was.
            if pinned.bandFocus.map({ pinned.pinSide(of: $0) != nil }) ?? true {
                pinned.bandFocus = (side == .left ? origin.after ?? origin.before : origin.before ?? origin.after)
                    .flatMap { pinned.bandIndex(of: $0) }.flatMap { pinned.root.children[$0].windows.first }
            }
        }
        guard pinned.bandHasRoom else { return .refused("the band would be left too little room") }
        self = pinned
        focus(focused)
        return .changed
    }

    /// Put `node`, a column taken out of the tree, at `side`'s end, pinned by `id`.
    private mutating func place(_ node: Node, pinnedTo side: PinSide, by id: WindowID, origin: PinOrigin) {
        root.insert(node, at: side == .left ? 0 : root.children.count)
        pins[side] = id
        pinOrigins[side] = origin
    }

    /// Unpin the column pinned to `side`, or with nil the focused window's column: it goes back between the columns it
    /// was pinned from, or failing them to the band's end beside where it was pinned. Refused with nothing pinned there.
    @discardableResult
    public mutating func unpin(_ side: PinSide? = nil) -> PinChange {
        guard isScrolling else { return .refused("only a scrolling strip pins columns") }
        guard let side = side ?? focused.flatMap({ pinSide(of: $0) }), let index = pinnedIndex(side) else {
            return .refused(side.map { "nothing is pinned \($0.rawValue)" } ?? "the focused column is not pinned")
        }
        let node = root.children[index], origin = pinOrigins.removeValue(forKey: side) ?? PinOrigin()
        pins[side] = nil
        root.remove(at: index)
        let band = bandRange
        let to = origin.before.flatMap { bandIndex(of: $0) }.map { $0 + 1 }
            ?? origin.after.flatMap { bandIndex(of: $0) }
            ?? (side == .left ? band.lowerBound : band.upperBound)
        root.insert(node, at: min(max(to, band.lowerBound), band.upperBound))
        if let focused { focus(focused) }
        return .changed
    }

    /// Before `id` leaves its column: a pinned column it marked is marked by another of its windows, or, with none
    /// left, unpinned, the column going with it.
    mutating func rekeyPins(leaving id: WindowID) {
        for side in PinSide.allCases where pins[side] == id {
            guard let index = pinnedIndex(side) else { continue }
            if let other = root.children[index].windows.first(where: { $0 != id }) {
                pins[side] = other
            } else {
                pins[side] = nil
                pinOrigins[side] = nil
            }
        }
    }

    /// After an edit: a mark whose window is no longer in its end column is dropped, the columns left where they are; a
    /// column marked for both sides, as the strip's only one, stays pinned left. Only in the scrolling layout.
    mutating func settlePins() {
        guard isScrolling else { return }
        for side in PinSide.allCases where pins[side] != nil && pinnedIndex(side) == nil {
            pins[side] = nil
            pinOrigins[side] = nil
            Self.pinsSettled += 1
        }
        if let left = pinnedIndex(.left), pinnedIndex(.right) == left {
            pins[.right] = nil
            pinOrigins[.right] = nil
        }
        if let bandFocus, bandIndex(of: bandFocus) == nil { self.bandFocus = nil }
    }

    /// The band window focus goes to from the pin on `side`: the one focused last, else the most recent of the band
    /// column nearest the pin. Nil with an empty band.
    func bandReturn(from side: PinSide) -> WindowID? {
        if let bandFocus, bandIndex(of: bandFocus) != nil { return bandFocus }
        let band = bandRange
        guard !band.isEmpty else { return nil }
        let index = side == .left ? band.lowerBound : band.upperBound - 1
        return switch root.children[index] {
        case .window(let id): id
        case .container(let c): c.mostRecentWindow
        }
    }
}
