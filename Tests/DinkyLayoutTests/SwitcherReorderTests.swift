import CoreGraphics
import Testing
@testable import DinkyLayout

struct SwitcherReorderTests {
    /// `ws` with `id` dropped where `slot` among its columns asks, as the switcher drops it.
    private func reordered(_ ws: Workspace, moving id: WindowID, to slot: Int) -> String? {
        let groups = ws.root.children.map(\.windows)
        guard let move = SwitcherReorder(moving: id, in: groups, to: slot) else { return nil }
        var ws = ws
        guard ws.drop(id, onto: move.target, .split(move.after ? .right : .left)) else { return "refused" }
        return shape(ws.root)
    }

    @Test func `A lone column moves whole to the gap it is dropped in`() {
        let ws = workspace(4, algorithm: .scrolling)
        #expect(reordered(ws, moving: 1, to: 3) == "h[2 3 1 4]")
        #expect(reordered(ws, moving: 1, to: 4) == "h[2 3 4 1]")
        #expect(reordered(ws, moving: 4, to: 0) == "h[4 1 2 3]")
        #expect(reordered(ws, moving: 3, to: 1) == "h[1 3 2 4]")
    }

    @Test func `Dropped either side of itself, a lone column stays where it is`() {
        let groups: [[WindowID]] = [[1], [2], [3]]
        #expect(SwitcherReorder(moving: 2, in: groups, to: 1) == nil)
        #expect(SwitcherReorder(moving: 2, in: groups, to: 2) == nil)
        #expect(SwitcherReorder(moving: 3, in: groups, to: 3) == nil)
        #expect(SwitcherReorder(moving: 9, in: groups, to: 0) == nil)
    }

    @Test func `A window of a stack leaves it for a column of its own, before or after it as well`() {
        var ws = workspace(3, algorithm: .scrolling)
        ws.drop(3, onto: 2, .split(.down))
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(reordered(ws, moving: 3, to: 0) == "h[3 1 2]")
        #expect(reordered(ws, moving: 3, to: 1) == "h[1 3 2]")
        #expect(reordered(ws, moving: 3, to: 2) == "h[1 2 3]")
        #expect(reordered(ws, moving: 2, to: 2) == "h[1 3 2]")
    }

    @Test func `The pointer aims at the gap before the first group it is left of the middle of`() {
        let spans: [ClosedRange<CGFloat>] = [10...110, 122...222, 234...334]
        #expect(SwitcherReorder.slot(at: 0, spans: spans, allowed: 0...3) == 0)
        #expect(SwitcherReorder.slot(at: 59, spans: spans, allowed: 0...3) == 0)
        #expect(SwitcherReorder.slot(at: 61, spans: spans, allowed: 0...3) == 1)
        #expect(SwitcherReorder.slot(at: 200, spans: spans, allowed: 0...3) == 2)
        #expect(SwitcherReorder.slot(at: 400, spans: spans, allowed: 0...3) == 3)
        // Never past a pinned column at either end.
        #expect(SwitcherReorder.slot(at: 0, spans: spans, allowed: 1...2) == 1)
        #expect(SwitcherReorder.slot(at: 400, spans: spans, allowed: 1...2) == 2)
    }

    @Test func `The gaps allowed leave out pinned columns at the ends`() {
        let groups: [[WindowID]] = [[1], [2], [3], [4]]
        #expect(SwitcherReorder.allowed(groups) { _ in false } == 0...4)
        #expect(SwitcherReorder.allowed(groups) { $0 == 0 } == 1...4)
        #expect(SwitcherReorder.allowed(groups) { $0 == 0 || $0 == 3 } == 1...3)
        #expect(SwitcherReorder.allowed(groups) { _ in true } == nil)
    }

    @Test func `A key's step moves a column one over, or a stacked window out beside its stack`() {
        let groups: [[WindowID]] = [[1], [2, 3], [4]]
        #expect(SwitcherReorder.step(1, in: groups, forward: true, allowed: 0...3) == 2)
        #expect(SwitcherReorder.step(1, in: groups, forward: false, allowed: 0...3) == nil)
        #expect(SwitcherReorder.step(4, in: groups, forward: true, allowed: 0...3) == nil)
        #expect(SwitcherReorder.step(4, in: groups, forward: false, allowed: 0...3) == 1)
        #expect(SwitcherReorder.step(3, in: groups, forward: false, allowed: 0...3) == 1)
        #expect(SwitcherReorder.step(3, in: groups, forward: true, allowed: 0...3) == 2)
        // Not past a pin.
        #expect(SwitcherReorder.step(4, in: groups, forward: false, allowed: 1...3) == 1)
        #expect(SwitcherReorder.step(2, in: [[1], [2]], forward: false, allowed: 1...2) == nil)
    }

    @Test func `The marker sits in the middle of a gap, or past an end`() {
        let spans: [ClosedRange<CGFloat>] = [10...110, 122...222]
        #expect(SwitcherReorder.markerX(0, spans: spans, gap: 12) == 4)
        #expect(SwitcherReorder.markerX(1, spans: spans, gap: 12) == 116)
        #expect(SwitcherReorder.markerX(2, spans: spans, gap: 12) == 228)
        #expect(SwitcherReorder.markerX(0, spans: [], gap: 12) == nil)
    }
}
