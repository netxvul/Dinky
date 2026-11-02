import CoreGraphics

/// Moving a window the window switcher's row shows to another place among a strip's columns, as dragging its card
/// or Shift with h or l asks: the window goes into a column of its own at `slot`, a gap between the row's groups (0
/// before the first, `groups.count` after the last), as `Workspace.drop` beside a neighbour's column puts it. A
/// column of its own moves whole, at its width; one of a stack leaves the stack for a column of its own there.
public struct SwitcherReorder: Equatable, Sendable {
    /// The window whose column the moving one goes beside.
    public let target: WindowID
    /// Whether it goes after `target`'s column rather than before it.
    public let after: Bool

    public init(target: WindowID, after: Bool) {
        self.target = target
        self.after = after
    }

    /// The drop that puts `id`, in one of `groups`, the row's columns left to right, in a column of its own at `slot`.
    /// Nil where that is where it is already, as a lone column dropped either side of itself, or for a window none of
    /// the groups holds.
    public init?(moving id: WindowID, in groups: [[WindowID]], to slot: Int) {
        guard let from = groups.firstIndex(where: { $0.contains(id) }) else { return nil }
        let slot = min(max(slot, 0), groups.count)
        let alone = groups[from].count == 1
        if alone, slot == from || slot == from + 1 { return nil }
        // Beside the column at `slot`, or after the last; its own column's other window where that is the one.
        let column = slot < groups.count ? slot : groups.count - 1
        guard let target = groups[column].first(where: { $0 != id }) else { return nil }
        self.init(target: target, after: slot == groups.count)
    }

    /// The gap a pointer at `x`, in the row's coordinates, aims at: before the first of `spans`, each a group's extent
    /// across, that it is left of the middle of, kept within `allowed`.
    public static func slot(at x: CGFloat, spans: [ClosedRange<CGFloat>], allowed: ClosedRange<Int>) -> Int {
        let slot = spans.firstIndex { x < ($0.lowerBound + $0.upperBound) / 2 } ?? spans.count
        return min(max(slot, allowed.lowerBound), allowed.upperBound)
    }

    /// The gap a key's step moves `id` to: a lone column one column over, a window of a stack out into a column of its
    /// own just before or after it, as `move` left and right do. Nil where it cannot go that way within `allowed`.
    public static func step(_ id: WindowID, in groups: [[WindowID]], forward: Bool, allowed: ClosedRange<Int>) -> Int? {
        guard let from = groups.firstIndex(where: { $0.contains(id) }) else { return nil }
        let alone = groups[from].count == 1
        let slot = forward ? from + (alone ? 2 : 1) : from - (alone ? 1 : 0)
        guard allowed.contains(slot), SwitcherReorder(moving: id, in: groups, to: slot) != nil else { return nil }
        return slot
    }

    /// The gaps a window can go to among `groups`, those for which `fixed` is false: between and either side of
    /// them, so never past a pinned column. Nil with none.
    public static func allowed(_ groups: [[WindowID]], fixed: (Int) -> Bool) -> ClosedRange<Int>? {
        guard let first = groups.indices.first(where: { !fixed($0) }),
              let last = groups.indices.last(where: { !fixed($0) }) else { return nil }
        return first...(last + 1)
    }

    /// Where the line marking `slot` goes among `spans`, `gap` apart, the middle of the gap or that far past an end, in
    /// the row's coordinates across.
    public static func markerX(_ slot: Int, spans: [ClosedRange<CGFloat>], gap: CGFloat) -> CGFloat? {
        guard let first = spans.first, let last = spans.last else { return nil }
        if slot <= 0 { return first.lowerBound - gap / 2 }
        if slot >= spans.count { return last.upperBound + gap / 2 }
        return (spans[slot - 1].upperBound + spans[slot].lowerBound) / 2
    }
}
