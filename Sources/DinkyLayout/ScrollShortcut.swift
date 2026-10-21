import CoreGraphics

// A long scroll of the strip, one that takes every column in view out of it, passes no column on the way: the columns
// in view slide out and the columns coming into view slide in right behind them, a gap apart, as if nothing lay
// between, so the strip glides about a screen's width however far it goes. Gliding the whole way, the columns between
// would cross the screen in a few frames each, too fast to follow, and an app slow to move its window would show it at
// only one or two places on the way. Those columns go straight to where the scroll leaves them instead, out of view at
// both ends. A column showing only a sliver at an edge counts as out of view.
//
// Any glide, long or not, also sends straight to its target a window out of view at both ends that would cross the
// screen on the way, as the columns between do when a long scroll is turned back part way.

extension Workspace {
    /// How much of a window has to be on screen for it to count as in view: more than the sliver a column shows beside
    /// the parked ones, or at the end of the strip.
    static let inView: CGFloat = 3 * peek

    /// The starts and targets to glide the strip's windows between instead of `starts` and `targets`, in strip
    /// coordinates, before parking. Nil when the glide is fine as it is. Windows in view at either end only shortcut
    /// a scroll where none of them changes size or height.
    public func scrollShortcut(from starts: [WindowID: CGRect], to targets: [WindowID: CGRect])
        -> (starts: [WindowID: CGRect], targets: [WindowID: CGRect])? {
        guard isScrolling else { return nil }
        let screen = bounds, columns = root.children.map { $0.windows.filter { starts[$0] != nil && targets[$0] != nil } }
        func shows(_ r: CGRect) -> Bool { min(r.maxX, screen.maxX) - max(r.minX, screen.minX) > Self.inView }
        var starts = starts, targets = targets, changed = false
        var before: [Int] = [], after: [Int] = []
        for (index, ids) in columns.enumerated() {
            if ids.contains(where: { shows(starts[$0]!) }) { before.append(index) }
            if ids.contains(where: { shows(targets[$0]!) }) { after.append(index) }
        }
        // Out of view at both ends, but on opposite sides: it would only flash across.
        for (index, ids) in columns.enumerated() where !before.contains(index) && !after.contains(index) {
            for id in ids where (starts[id]!.midX < screen.midX) != (targets[id]!.midX < screen.midX) {
                starts[id] = targets[id]
                changed = true
            }
        }
        let unchanged = changed ? (starts, targets) : nil
        guard let firstBefore = before.first, let lastBefore = before.last, let firstAfter = after.first,
              let lastAfter = after.last, Set(before).isDisjoint(with: after) else { return unchanged }
        // Whether the strip scrolls on to columns right of those in view, its windows moving left.
        let forward: Bool
        if lastBefore < firstAfter {
            forward = true
        } else if lastAfter < firstBefore {
            forward = false
        } else {
            return unchanged
        }
        let out = before.flatMap { columns[$0] }, into = after.flatMap { columns[$0] }
        guard (out + into).allSatisfy({ id in
            let start = starts[id]!, target = targets[id]!
            return abs(start.width - target.width) <= 1 && abs(start.height - target.height) <= 1
                && abs(start.minY - target.minY) <= 1
        }) else { return unchanged }
        // Those coming in start a gap behind those going out, and further still where either would otherwise be on
        // screen at the end it is out of view at.
        let gap = gaps.horizontal, shift: CGFloat
        if forward {
            let outEdge = out.map { starts[$0]!.maxX }.max()!, inEdge = into.map { targets[$0]!.minX }.min()!
            shift = min(inEdge - outEdge - gap, screen.minX - outEdge, inEdge - screen.maxX)
        } else {
            let outEdge = out.map { starts[$0]!.minX }.min()!, inEdge = into.map { targets[$0]!.maxX }.max()!
            shift = max(inEdge + gap - outEdge, screen.maxX - outEdge, inEdge - screen.minX)
        }
        // Only where every one of them would otherwise go further, the same way.
        guard (out + into).allSatisfy({ id in
            let moved = targets[id]!.minX - starts[id]!.minX
            return moved * shift > 0 && abs(moved) > abs(shift) + 1
        }) else { return unchanged }
        for id in out { targets[id] = starts[id]!.offsetBy(dx: shift, dy: 0) }
        for id in into { starts[id] = targets[id]!.offsetBy(dx: -shift, dy: 0) }
        return (starts, targets)
    }
}
