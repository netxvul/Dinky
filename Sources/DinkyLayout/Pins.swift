import CoreGraphics

// Pinned columns, after SlideScroll's: a column of the strip held at the left or right side of the screen while the
// rest scroll between, in the band. A pinned column stays in the tree, as the strip's first column (left) or its last
// (right), so stacking, joining, the switchers and drops treat it as any column; the workspace only marks which
// column each side holds, by one of its windows, and the slot rules: a mark whose window has left the end column is
// dropped, the columns never moved for it (`settlePins`). Each side holds one column at most. Pinned, a column keeps
// its share of the area inside the outer gaps, the band never narrower than `minimumBandShare` of it; a band window
// wider than the band hangs past it, under the pins. Unpinned, it goes back between the columns it was pinned from. Outside the scrolling layout
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
        return max((gaps.inset(bounds).width * CGFloat(width(ofColumn: index))).rounded(), (minimum + gap / 2).rounded(.up))
    }

    /// Where the pinned column at `index` goes: from the outer gap on its side, its span less the half gap towards
    /// the band, the strip's height. Its edge towards the band is rounded as the band's edges are, so with an odd gap
    /// it is still one whole gap from them.
    func pinRect(_ index: Int) -> CGRect {
        let inset = gaps.inset(bounds), span = pinSpan(index), half = gaps.horizontal / 2
        let minX: CGFloat, maxX: CGFloat
        if index == 0 && pinnedIndex(.left) == 0 {
            minX = inset.minX.rounded()
            maxX = ((inset.minX + span).rounded() - half).rounded()
        } else {
            maxX = inset.maxX.rounded()
            minX = ((inset.maxX - span).rounded() + half).rounded()
        }
        return CGRect(x: minX, y: inset.minY, width: max(maxX - minX, 0), height: inset.height)
    }

    /// Whether the band keeps room enough: `minimumBandShare` of the area inside the outer gaps. A band window wider
    /// than that, as an app's minimum width makes it, hangs past the band, under the pins.
    var bandHasRoom: Bool {
        stripInset.width >= gaps.inset(bounds).width * CGFloat(Self.minimumBandShare) - 0.5
    }

    /// Whether a width step of the column at `index` is refused for the band's room: only a pinned column's, which narrows
    /// the band, and only one that leaves the band short of room and with less than `roomBefore`, so a pin can always
    /// shrink.
    func narrowsBand(_ index: Int, from roomBefore: CGFloat) -> Bool {
        pinSide(ofColumn: index) != nil && !bandHasRoom && stripInset.width < roomBefore - 0.5
    }

    /// Whether `after`, this tree with a pin slot's holder changed, leaves the band short of room where it had it, or
    /// with less than it had: what a swap through a pin slot is refused for.
    func lacksRoom(after: Workspace) -> Bool {
        !after.bandHasRoom && (bandHasRoom || after.stripInset.width < stripInset.width - 0.5)
    }

    /// Pin the column of `window`, or of the focused window, to `side`, focus left where it is. Pinned there already, it
    /// stays, or with `toggle` is unpinned; pinned to the other side, it moves across. A column already pinned to `side`
    /// goes back to where it was pinned from. With `freeSideOnly`, as a rule pins, a side another column holds is left to
    /// it. Refused outside the scrolling layout, with nothing to pin, or where the band would be left too little room.
    @discardableResult
    public mutating func pin(_ side: PinSide, toggle: Bool = false, freeSideOnly: Bool = false,
                             window: WindowID? = nil) -> PinChange {
        guard isScrolling else { return .refused("only a scrolling strip pins columns") }
        guard let focused = window ?? self.focused, let column = root.path(of: focused)?.first else {
            return .refused("nothing to pin")
        }
        if freeSideOnly {
            // A rule pins only a column in the band, to a free side, and never unpins: rules run again.
            if pinSide(ofColumn: column) != nil { return .unchanged }
            if pinnedIndex(side) != nil { return .refused("the \(side.rawValue) side is pinned already") }
        } else if let pinned = pinSide(ofColumn: column), pinned == side {
            return toggle ? unpin(side) : .unchanged
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
        // The band narrowed under its scroll: it shows the window focus goes back to from the pin, whole.
        if let back = bandFocus, bandIndex(of: back) != nil { reveal(back) }
        if let shown = self.focused { focus(shown) }
        return .changed
    }

    /// Put `node`, a column taken out of the tree, at `side`'s end, pinned by `id`.
    private mutating func place(_ node: Node, pinnedTo side: PinSide, by id: WindowID, origin: PinOrigin) {
        root.insert(node, at: side == .left ? 0 : root.children.count)
        pins[side] = id
        pinOrigins[side] = origin
        lastPinned = side
    }

    /// Unpin the column pinned to `side`, or with nil the focused window's column: it goes back between the columns it
    /// was pinned from, or failing them to the band's end beside where it was pinned. Refused with nothing pinned there.
    @discardableResult
    public mutating func unpin(_ side: PinSide? = nil, window: WindowID? = nil) -> PinChange {
        guard isScrolling else { return .refused("only a scrolling strip pins columns") }
        guard let side = side ?? (window ?? focused).flatMap({ pinSide(of: $0) }), let index = pinnedIndex(side) else {
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

    /// `id` is gone for good, from any layout: a mark of it whose column is not where it is now, as one asleep outside
    /// the scrolling layout, is dropped, and so is its place in a pin's origin, a departed pin's record and the band's
    /// focus. A mark of a column it shares with others is passed on by `rekeyPins` as it leaves.
    public mutating func forgetPinned(_ id: WindowID) {
        for side in PinSide.allCases {
            if pins[side] == id, pinnedIndex(side) == nil {
                pins[side] = nil
                pinOrigins[side] = nil
            }
            if pinOrigins[side]?.before == id { pinOrigins[side]?.before = nil }
            if pinOrigins[side]?.after == id { pinOrigins[side]?.after = nil }
            if departedPins[side] == id { departedPins[side] = nil }
        }
        departedWidths[id] = nil
        departedOrigins[id] = nil
        for (departed, origin) in departedOrigins {
            if origin.before == id { departedOrigins[departed]?.before = nil }
            if origin.after == id { departedOrigins[departed]?.after = nil }
        }
        if bandFocus == id { bandFocus = nil }
    }

    /// After an edit: a mark whose window is no longer in its end column is dropped, the columns left where they are; a
    /// column marked for both sides, as the strip's only one, stays pinned left. Only in the scrolling layout.
    /// Returns how many marks it dropped, which only an edit that moved a pinned column off its end leaves.
    @discardableResult
    mutating func settlePins() -> Int {
        guard isScrolling else { return 0 }
        var dropped = 0
        for side in PinSide.allCases where pins[side] != nil && pinnedIndex(side) == nil {
            pins[side] = nil
            pinOrigins[side] = nil
            dropped += 1
        }
        if let left = pinnedIndex(.left), pinnedIndex(.right) == left {
            pins[.right] = nil
            pinOrigins[.right] = nil
        }
        if let bandFocus, bandIndex(of: bandFocus) == nil { self.bandFocus = nil }
        return dropped
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

extension Workspace {
    /// `remove` for a window going away for a while, minimized, hidden or floated: a pin of its own is remembered, so
    /// it is pinned again as it comes back (`arrive`). So is a mark asleep outside the scrolling layout.
    public mutating func depart(_ id: WindowID) {
        let dormant = isScrolling ? nil : pins.first(where: { $0.value == id })?.key
        let side = pinSide(of: id) ?? dormant
        let lone = dormant != nil
            || side.flatMap { pinnedIndex($0) }.map { root.children[$0].windows.count == 1 } ?? false
        let share = columnWidths[id], origin = side.flatMap { pinOrigins[$0] }
        remove(id)
        if let side, lone {
            departedPins[side] = id
            departedWidths[id] = share
            departedOrigins[id] = origin
        }
    }

    /// `insert` for a window coming back: one that went away pinned is pinned again, to the side it had while that
    /// side is still free and the band keeps room, else it stays in the band.
    public mutating func arrive(_ id: WindowID) {
        insert(id)
        guard let side = departedPins.first(where: { $0.value == id })?.key else { return }
        departedPins[side] = nil
        let share = departedWidths.removeValue(forKey: id), origin = departedOrigins.removeValue(forKey: id)
        // Outside the scrolling layout, a mark asleep till it scrolls again, for a side still free, with the width and
        // the origin it had.
        guard isScrolling else {
            guard pins[side] == nil else { return }
            pins[side] = id
            if let share { columnWidths[id] = share }
            if let origin { pinOrigins[side] = origin }
            return
        }
        guard pinnedIndex(side) == nil, let column = root.path(of: id)?.first else { return }
        // At the width it had, so it fits where it did.
        let old = width(ofColumn: column)
        if let share { setWidth(ofColumn: column, share) }
        if pin(side, window: id) != .changed {
            setWidth(ofColumn: column, old)
        } else if let origin {
            // Unpinned later, it goes back to where it was first pinned from.
            pinOrigins[side] = origin
        }
    }
}

extension Workspace {
    /// After the display or the gaps changed: pins that leave the band too little room now are unpinned, the one
    /// pinned last first, till it has room again.
    public mutating func fitPins() {
        let order = [lastPinned ?? .right, lastPinned == .left ? .right : .left]
        for side in order where !bandHasRoom && pinnedIndex(side) != nil { _ = unpin(side) }
    }
}

extension Workspace {
    /// `focus-pin`: focus the column pinned to `side`, scrolling nothing; with it focused already, the band window
    /// focused last instead. The window focused, nil with nothing pinned there.
    public mutating func focusPin(_ side: PinSide) -> WindowID? {
        guard let index = pinnedIndex(side) else { return nil }
        let target: WindowID?
        if let focused, root.children[index].windows.contains(focused) {
            target = bandReturn(from: side)
        } else {
            target = switch root.children[index] {
            case .window(let id): id
            case .container(let c): c.mostRecentWindow
            }
        }
        guard let target else { return nil }
        focus(target)
        return target
    }
}

extension Workspace {
    /// `drop`'s swap in a strip with a pin: the two trade places, each slot marked by the window that lands in it, and
    /// where a pin's slot changes hands each column keeps its width, so the pin stays a pin's width and the band a band
    /// column's. Refused, nothing changed, where a pin slot changing hands leaves the band short of room (see
    /// `lacksRoom`).
    mutating func swapBesidePins(_ id: WindowID, _ target: WindowID) -> Bool {
        guard id != target, let a = root.path(of: id), let b = root.path(of: target) else { return false }
        var swapped = self
        let shares = (width(ofColumn: a[0]), width(ofColumn: b[0]))
        let slots = (pinSide(ofColumn: a[0]), pinSide(ofColumn: b[0]))
        swapped.root.modify(at: Array(a.dropLast())) { $0.replace(at: a.last!, with: .window(target)) }
        swapped.root.modify(at: Array(b.dropLast())) { $0.replace(at: b.last!, with: .window(id)) }
        for side in PinSide.allCases {
            if pins[side] == id { swapped.pins[side] = target } else if pins[side] == target { swapped.pins[side] = id }
        }
        if slots.0 != slots.1 {
            swapped.setWidth(ofColumn: a[0], shares.0)
            swapped.setWidth(ofColumn: b[0], shares.1)
        }
        swapped.settlePins()
        if let back = swapped.bandFocus, swapped.pinSide(of: back) != nil { swapped.bandFocus = nil }
        guard slots.0 == slots.1 || !lacksRoom(after: swapped) else { return false }
        self = swapped
        focus(id)
        return true
    }
}

extension Workspace {
    /// Where the column pinned to `side` is, nil with none.
    public func pinFrame(_ side: PinSide) -> CGRect? { pinnedIndex(side).map(pinRect) }
}

extension Workspace {
    /// A band left less than `minimumBandShare` of the screen, as once a pin's app turns out to need a wider window,
    /// takes the room from the pins: the one pinned last narrows first, down to what its windows take and the narrowest
    /// column, then the other, till the band has room again. Never unpinned for it. Only with a pin.
    public mutating func fitBand() {
        guard hasPins, !bandHasRoom else { return }
        let inset = gaps.inset(bounds).width, gap = gaps.horizontal
        let order = [lastPinned ?? .right, lastPinned == .left ? .right : .left]
        for side in order {
            guard !bandHasRoom, let index = pinnedIndex(side), inset > 0 else { continue }
            let short = inset * CGFloat(Self.minimumBandShare) - stripInset.width
            let own = root.children[index].minimumExtent(.horizontal, gap: gap, padding: accordionPadding, minimumSizes)
            let floor = max(Self.minimumColumnWidth, Double((own + gap / 2) / inset))
            let share = width(ofColumn: index)
            // Never wider than it was: a minimum that goes again would leave it so.
            setWidth(ofColumn: index, max(share - Double(short / inset), min(share, floor)))
        }
    }
}

/// A window shown on screen, as `pinsToRaise` reads the stacking.
public struct StackedWindow: Equatable, Sendable {
    public var id: WindowID
    public var layer: Int
    public var frame: CGRect
    public var pid: Int32

    public init(id: WindowID, layer: Int, frame: CGRect, pid: Int32) {
        self.id = id
        self.layer = layer
        self.frame = frame
        self.pid = pid
    }
}

extension Workspace {
    /// The pinned windows to raise, back to front, as the layout stacks them, so a pinned accordion's shown window is
    /// last: each pinned column a band window of this tree is in front of where they overlap, or is about to sweep
    /// across (`sweeping`, by pin), or is in front of at all as fingers take hold (`takingHold`), raised whole.
    /// `stack` is the windows shown, front to back; `raising` those the same pass raises, counted as in front of every
    /// pin. A window in `candidates` (focused, or being focused) of an app of a pinned column is raised after it to keep
    /// its app's focus, so it does not count for that column: it would cover it again. A column under a window outside
    /// the tree at its level or lower, a dialog or a floating window in use, is left as it is, whole. None while a
    /// window is fullscreen over the pins. Windows of the apps in `beyondReach`, as the active app's are for a raise
    /// through Accessibility, which cannot put a window in front of them, count for none.
    public func pinsToRaise(stack: [StackedWindow], candidates: [WindowID], raising: Set<WindowID> = [],
                            sweeping: [WindowID: Set<WindowID>] = [:], takingHold: Bool = false,
                            beyondReach: Set<Int32> = []) -> [WindowID] {
        let layout = self.layout()
        // Only a fullscreen window that covers the pins stands in the way: one pushing in the band covers none.
        if let first = layout.order.first, fullscreenWindows.contains(first), !pushesFullscreen || pinSide(of: first) != nil {
            return []
        }
        let position = Dictionary(stack.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = Dictionary(stack.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tree = Set(windows)
        let pins = Array(layout.order.filter { pinSide(of: $0) != nil }.reversed())
        var columnApps: [PinSide: Set<Int32>] = [:]
        for pin in pins {
            if let side = pinSide(of: pin), let pid = shown[pin]?.pid { columnApps[side, default: []].insert(pid) }
        }
        var covered: Set<PinSide> = [], inUse: Set<PinSide> = []
        for pin in pins {
            guard let side = pinSide(of: pin), let at = position[pin], let me = shown[pin] else { continue }
            let own = columnApps[side] ?? []
            let ahead = (stack.prefix(at).map(\.id) + raising.filter { position[$0] != nil }).filter { id in
                id != pin && !(candidates.contains(id) && shown[id].map { own.contains($0.pid) } == true)
                    && !(shown[id].map { beyondReach.contains($0.pid) } == true && tree.contains(id))
            }
            let over = ahead.filter { shown[$0]!.frame.intersects(me.frame) }
            if over.contains(where: { !tree.contains($0) && shown[$0]!.layer <= me.layer }) {
                inUse.insert(side)
                continue
            }
            let band = { (id: WindowID) in tree.contains(id) && pinSide(of: id) == nil }
            if over.contains(where: band)
                || ahead.contains(where: { band($0) && (takingHold || sweeping[pin]?.contains($0) == true) }) {
                covered.insert(side)
            }
        }
        covered.subtract(inUse)
        return pins.filter { id in pinSide(of: id).map(covered.contains) == true && position[id] != nil }
    }
}

extension Workspace {
    /// The pinned windows shown, which get their ring: every window of a pinned stack, the one in front of a pinned
    /// accordion. None outside the scrolling layout, nor while a window fullscreen over the strip covers the pins.
    public var ringedPins: [WindowID] {
        guard hasPins else { return [] }
        let layout = self.layout()
        if let first = layout.order.first, fullscreenWindows.contains(first), !pushesFullscreen || pinSide(of: first) != nil {
            return pinSide(of: first) != nil ? [first] : []
        }
        return PinSide.allCases.compactMap(pinnedIndex).flatMap { index -> [WindowID] in
            switch root.children[index] {
            case .window(let id): return [id]
            case .container(let c) where c.mode == .accordion:
                let windows = Set(Node.container(c).windows)
                return layout.order.first(where: windows.contains).map { [$0] } ?? []
            case .container(let c): return Node.container(c).windows
            }
        }
    }
}
