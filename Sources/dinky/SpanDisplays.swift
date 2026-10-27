import AppKit
import DinkyLayout
import DinkyPrivate

// `[scrolling] span-displays`: two displays side by side running one strip across both (see DinkyLayout's Span.swift).
// While the two Spaces they show both lay out as scrolling, they are a pair: the right Space's tree is taken into the
// left one's, which then lays out across both displays, and the right Space's windows belong to it (`treeKey`). The Nth
// user Space of one display is the partner of the Nth of the other: a display switched to a Space, by dinky or a swipe,
// takes the other display to its partner where both scroll (`followSpan`), so the two switch as one. Once the displays
// show no pair, as one shows a Space that does not scroll or a full-screen app's, or the displays change, the strip
// splits again, each window going back to the tree of the Space it is on, and comes together again as they show a pair.
// Nothing changes while a switch is under way: the pair it ends on is taken as it lands. A window the strip takes over the seam is moved to the other display's Space by dinky as most of it crosses
// (`settleSpanSpaces`), rather than left to macOS.

/// Two Spaces showing side by side as one strip, its tree the left one's.
struct SpanPair: Equatable {
    let left: UInt64, right: UInt64
    let leftDisplay: String, rightDisplay: String
}

extension Coordinator {
    /// The tree that holds a Space's windows: for the right Space of a pair running across the displays, the left one's.
    func treeKey(_ space: UInt64) -> UInt64 {
        span.flatMap { $0.right == space ? $0.left : nil } ?? space
    }

    /// The Space window `id` of tree `key` belongs on: in the strip running across two displays, that of the display
    /// its tile is on; else `key`'s own.
    func spaceOf(_ id: WindowID, inTree key: UInt64) -> UInt64 {
        guard let span, span.left == key, let tree = workspaces[key], let frame = tree.layout().frames[id],
              let left = tree.isLeftOfSeam(frame) else { return key }
        return left ? span.left : span.right
    }

    /// With `[scrolling] span-displays` turned off, the windows of each companion Space, an unnumbered Space a strip
    /// across two displays paired with a workspace at the same place on the other display, go to that workspace's
    /// Space: they were its, shown on the other display.
    func returnCompanions() {
        guard let (left, right) = sideBySide() else { return }
        let numbers = AppState.shared.numbers
        for (here, there) in [(left, right), (right, left)] {
            for (i, space) in here.userSpaces.enumerated() where numbers.number(of: space) == nil && i < there.userSpaces.count {
                let home = there.userSpaces[i]
                guard numbers.number(of: home) != nil else { continue }
                var ids = dinky_space_window_ids(space, true).map(\.uint32Value)
                guard !ids.isEmpty, dinky_move_windows_to_space(&ids, Int32(ids.count), home) else { continue }
                print("\(stamp()) span: off, \(ids.count) windows of companion Space \(space) back to Space \(home)")
            }
        }
    }

    /// The display at the end of the strip running across two displays on tree `key`: the right one for its last column
    /// (`last`), else the left one. Nil for any other tree.
    func spanEndDisplay(_ key: UInt64, last: Bool) -> String? {
        guard let span, span.left == key else { return nil }
        return last ? span.rightDisplay : span.leftDisplay
    }

    /// The two displays, left then right, when there are exactly two and they touch side by side, as `walls(of:)`
    /// tells a display beside another.
    func sideBySide() -> (left: Display, right: Display)? {
        let all = displays.displays
        guard all.count == 2 else { return nil }
        let (a, b) = all[0].frame.minX <= all[1].frame.minX ? (all[0], all[1]) : (all[1], all[0])
        guard abs(a.frame.maxX - b.frame.minX) < 1, min(a.frame.maxY, b.frame.maxY) > max(a.frame.minY, b.frame.minY)
        else { return nil }
        return (a, b)
    }

    /// The Space paired with `space`, at the same place among the other display's user Spaces, and that display. Nil
    /// with the option off, without two displays side by side, or with no Space there.
    func partner(of space: UInt64) -> (space: UInt64, display: Display)? {
        guard config.scrolling.spanDisplays, let (left, right) = sideBySide() else { return nil }
        for (here, there) in [(left, right), (right, left)] {
            if let i = here.userSpaces.firstIndex(of: space), i < there.userSpaces.count {
                return (there.userSpaces[i], there)
            }
        }
        return nil
    }

    /// The Space a display switched to `space` takes the other display to: its partner, where both scroll.
    func spanFollower(of space: UInt64) -> (space: UInt64, display: Display)? {
        guard scrolls(space), let (partner, other) = partner(of: space), scrolls(partner) else { return nil }
        return (partner, other)
    }

    /// Whether a Space lays out as a scrolling strip: by a `layout` command its tree took, else by its settings.
    private func scrolls(_ space: UInt64) -> Bool {
        let settings = settings(for: space)
        guard settings.tiling, !settings.isFree else { return false }
        return (workspaces[space]?.chosenAlgorithm ?? algorithm(settings)) == .scrolling
    }

    /// The pair that should run across the displays now: two displays side by side, each showing a user Space that
    /// scrolls.
    private func wantedSpan() -> SpanPair? {
        guard enabled, config.scrolling.spanDisplays, let (left, right) = sideBySide(),
              left.userSpaces.contains(left.currentSpaceID), right.userSpaces.contains(right.currentSpaceID),
              scrolls(left.currentSpaceID), scrolls(right.currentSpaceID) else { return nil }
        return SpanPair(left: left.currentSpaceID, right: right.currentSpaceID, leftDisplay: left.uuid,
                        rightDisplay: right.uuid)
    }

    /// Runs a strip across the displays, or splits the one that does, as the displays, their Spaces and their layouts
    /// have it now, and fits the one running across them to where the displays are. Not while fingers, the mouse or a
    /// drag hold a strip, nor while a display switches Space: once they let go, or it lands.
    func updateSpan() {
        guard !holdsStrip, drag == nil, !SpaceSwitcher.shared.switching else {
            fitSpan()
            // Looked at again once the switch has landed, which may come with no pass of its own.
            if config.scrolling.spanDisplays, !spanRetryPending {
                spanRetryPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.spanRetryPending = false
                    self?.flush()
                }
            }
            return
        }
        if alignCompanion() { return }
        let wanted = wantedSpan()
        if let span, span != wanted { unspan(span) }
        if let wanted, span != wanted { spanUp(wanted) }
        fitSpan()
    }

    /// A display showing a companion Space other than the partner of the scrolling workspace the other display shows,
    /// as after launch, or after the option is turned on, switched to that partner, so the two run one strip: true when
    /// that switch is under way. Once only, so a companion the user swipes to stays. A display showing a workspace of
    /// its own is left alone.
    private func alignCompanion() -> Bool {
        guard !spanAligned, config.scrolling.spanDisplays, let (left, right) = sideBySide() else { return false }
        let numbers = AppState.shared.numbers
        // Had its look once the workspaces are numbered and a display shows one; till then, as at launch, it waits.
        guard [left, right].contains(where: { numbers.number(of: $0.currentSpaceID) != nil }) else { return false }
        for (here, there) in [(left, right), (right, left)] {
            guard numbers.number(of: here.currentSpaceID) != nil, numbers.number(of: there.currentSpaceID) == nil,
                  there.userSpaces.contains(there.currentSpaceID),
                  let (partner, other) = spanFollower(of: here.currentSpaceID), other.uuid == there.uuid else { continue }
            spanAligned = true
            guard there.currentSpaceID != partner, targetSpaceID(on: there) != partner else { return false }
            print("\(stamp()) span: display \(there.id) shows companion Space \(there.currentSpaceID), not \(partner): switched")
            return switchSpace(toSpaceID: partner, on: there)
        }
        // A scrolling workspace with no companion yet, which the arrangement makes: the look waits for it.
        if !([left, right].contains { spanFollower(of: $0.currentSpaceID) == nil && scrolls($0.currentSpaceID) }) {
            spanAligned = true
        }
        return false
    }

    private func display(_ uuid: String) -> Display? { displays.displays.first { $0.uuid == uuid } }

    /// The strip running across the displays fitted to where they are, their gaps the left one's.
    private func fitSpan() {
        guard let span, let left = display(span.leftDisplay), let right = display(span.rightDisplay),
              var tree = workspaces[span.left] else { return }
        let seam = Seam(left: left.visibleArea, right: right.visibleArea)
        guard tree.seam != seam || tree.gaps != gaps(on: left) || !tree.walls.isEmpty
                || tree.spanPeeks != config.scrolling.spanPeek else { return }
        tree.gaps = gaps(on: left)
        // Two displays and no more: nothing beyond the outer edges.
        tree.walls = []
        tree.spanPeeks = config.scrolling.spanPeek
        tree.setSeam(seam)
        tree.alignToWalls()
        setWorkspace(span.left, tree)
        dirty.insert(span.left)
    }

    /// The right Space's tree taken into the left one's, which runs across both displays from now on.
    private func spanUp(_ pair: SpanPair) {
        guard let left = display(pair.leftDisplay), let right = display(pair.rightDisplay) else { return }
        makeWorkspace(pair.left, on: left)
        var tree = workspaces[pair.left]!
        tree.walls = []
        tree.spanPeeks = config.scrolling.spanPeek
        tree.setSeam(Seam(left: left.visibleArea, right: right.visibleArea))
        if let other = takeWorkspace(pair.right) { tree.takeColumns(of: other) }
        setWorkspace(pair.left, tree)
        for (id, placement) in placements where placement.space == pair.right { placements[id]!.space = pair.left }
        span = pair
        dirty.insert(pair.left)
        print("\(stamp()) span: Spaces \(pair.left) and \(pair.right) run one strip across both displays, "
              + "\(tree.windows.count) windows")
    }

    /// The strip running across the displays split again, each window back in the tree of the Space it is on, each tree
    /// back on its display. A side whose layout was changed by a command keeps it; the other goes on scrolling, as a
    /// command changes only the workspace it runs on. With the right display or its Space gone, every window stays in
    /// the left tree, in strip order, on the display left.
    func unspan(_ pair: SpanPair) {
        span = nil
        guard var tree = workspaces[pair.left] else { return }
        tree.setSeam(nil)
        defer { dirty.formUnion([pair.left, pair.right]) }
        guard let left = displays.display(containingSpace: pair.left), let right = display(pair.rightDisplay),
              right.userSpaces.contains(pair.right) else {
            setWorkspace(pair.left, tree)
            print("\(stamp()) span: the right display or its Space went, the strip stays whole on Space \(pair.left)")
            return
        }
        let all = tree.windows
        let goes = Set(all.filter { dinky_window_space_id($0) == pair.right })
        var other = tree
        for id in all {
            if goes.contains(id) { tree.remove(id) } else { other.remove(id) }
        }
        // The side without the window a `layout` command ran on goes back to scrolling.
        if !tree.isScrolling, let focused = tree.focused ?? other.focused {
            var plain = goes.contains(focused) ? tree : other
            plain.chosenAlgorithm = algorithm(settings(for: goes.contains(focused) ? pair.left : pair.right)) == .scrolling
                ? nil : .scrolling
            plain.setAlgorithm(.scrolling)
            if goes.contains(focused) { tree = plain } else { other = plain }
        }
        (tree.bounds, tree.gaps, tree.walls) = (left.visibleArea, gaps(on: left), walls(of: left))
        (other.bounds, other.gaps, other.walls) = (right.visibleArea, gaps(on: right), walls(of: right))
        tree.alignToWalls()
        other.alignToWalls()
        setWorkspace(pair.left, tree)
        setWorkspace(pair.right, other)
        for id in goes where placements[id]?.space == pair.left { placements[id]!.space = pair.right }
        print("\(stamp()) span: Spaces \(pair.left) and \(pair.right) split, \(goes.count) windows back on the right")
    }

    /// A display come to a Space of a pair takes the other display to its partner, as a workspace of a pair switched to
    /// switches both. A Space with no partner, or whose partner does not scroll, leaves the other display alone. Called
    /// as the displays change.
    func followSpan() {
        guard enabled, config.scrolling.spanDisplays, let (left, right) = sideBySide() else {
            spanShown = [:]
            return
        }
        let before = spanShown
        spanShown = [left.uuid: left.currentSpaceID, right.uuid: right.currentSpaceID]
        for display in [left, right] {
            let now = display.currentSpaceID
            guard let was = before[display.uuid], was != now, let (partner, other) = spanFollower(of: now),
                  targetSpaceID(on: other) != partner else { continue }
            print("\(stamp()) span: display \(display.id) came to Space \(now), display \(other.id) follows to \(partner)")
            switchSpace(toSpaceID: partner, on: other)
        }
    }

    /// Moves each window of the strip running across the displays that most of shows on the other display than its
    /// Space's to that display's Space, rather than waiting on macOS to move it by its centre. Windows parked off an
    /// outer edge stay with the display there.
    func settleSpanSpaces() {
        guard let span, let tree = workspaces[span.left], tree.spansDisplays else { return }
        var moves: [UInt64: [UInt32]] = [:]
        for id in tree.windows { noteSpanSpace(id) }
        for id in tree.windows where id != dragging {
            guard let frame = serverFrame(id) ?? model.windows[id]?.frame, let left = tree.isLeftOfSeam(frame) else { continue }
            let want = left ? span.left : span.right, now = dinky_window_space_id(id)
            guard now == span.left || now == span.right, now != want else { continue }
            moves[want, default: []].append(id)
        }
        for (space, ids) in moves {
            var ids = ids
            if dinky_move_windows_to_space(&ids, Int32(ids.count), space) {
                print("\(stamp()) span: \(ids.sorted()) crossed the seam, moved to Space \(space)")
            }
        }
        // Another window of the focused one's app moved: macOS would give it the app's focus.
        let windows = model.windows
        if let focused = tree.focused, let pid = windows[focused]?.pid,
           moves.values.joined().contains(where: { $0 != focused && windows[$0]?.pid == pid }) {
            keepFocus(on: focused)
        }
    }

    /// Notes the Space window `id` is on now, and when it changed: for `spanCarried`.
    func noteSpanSpace(_ id: WindowID) {
        let now = dinky_window_space_id(id)
        guard now != 0 else { return }
        if let was = spanSpaces[id], was != now { spanCrossedAt[id] = CACurrentMediaTime() }
        spanSpaces[id] = now
    }

    /// For window `id` read as focused: the window the strip across two displays has focused instead, of the same app,
    /// where `id` is one the strip is carrying over the seam rather than one the user brought forward: while fingers or
    /// the mouse hold the strip, either glides, or `id` changed Space within the last second. Not with a click under
    /// way outside a hold. Nil otherwise.
    func spanCarried(_ id: WindowID) -> WindowID? {
        guard let span, id != 0, placements[id]?.space == span.left, let tree = workspaces[span.left],
              let want = tree.focused, want != id, let pid = model.windows[want]?.pid, model.windows[id]?.pid == pid
        else { return nil }
        noteSpanSpace(id)
        let crossed = spanCrossedAt[id].map { CACurrentMediaTime() - $0 < 1 } ?? false
        let moving = holdsStrip || isAnimating(id) || isAnimating(want)
        guard crossed || moving, holdsStrip || !clickUnderWay(within: 0.3) else { return nil }
        return want
    }

    /// `settleSpanSpaces` once the events in hand are taken in, and once more as a pass's glide is done.
    func settleSpanSpacesSoon(after delay: Double = 0) {
        guard span != nil else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.settleSpanSpaces() }
            return
        }
        guard !spanSettlePending else { return }
        spanSettlePending = true
        DispatchQueue.main.async { [weak self] in
            self?.spanSettlePending = false
            self?.settleSpanSpaces()
        }
    }

    /// The screen a strip lays out on, for its peeks: both displays for one running across them.
    func spanScreen(_ key: UInt64) -> CGRect? {
        guard let span, span.left == key, let left = display(span.leftDisplay), let right = display(span.rightDisplay)
        else { return nil }
        return left.frame.union(right.frame)
    }
}
