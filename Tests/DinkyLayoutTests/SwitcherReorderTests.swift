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

    @Test func `A floating window tiles in a column of its own at the gap it is dropped in`() {
        var ws = workspace(3, algorithm: .scrolling)
        ws.drop(3, onto: 2, .split(.down))
        let groups = ws.root.children.map(\.windows)
        ws.insert(9)
        func tiled(at slot: Int) -> String? {
            guard let move = SwitcherReorder(inserting: 9, among: groups, at: slot) else { return nil }
            var ws = ws
            guard ws.drop(9, onto: move.target, .split(move.after ? .right : .left)) else { return "refused" }
            return shape(ws.root)
        }
        #expect(tiled(at: 0) == "h[9 1 v[2 3]]")
        #expect(tiled(at: 1) == "h[1 9 v[2 3]]")
        #expect(tiled(at: 2) == "h[1 v[2 3] 9]")
        #expect(tiled(at: 7) == "h[1 v[2 3] 9]")
    }

    @Test func `Only a window none of the groups holds inserts, and only with a group to go beside`() {
        #expect(SwitcherReorder(inserting: 9, among: [], at: 0) == nil)
        #expect(SwitcherReorder(inserting: 1, among: [[1], [2]], at: 1) == nil)
        #expect(SwitcherReorder(inserting: 9, among: [[1], [2]], at: 1) == SwitcherReorder(target: 2, after: false))
        #expect(SwitcherReorder(inserting: 9, among: [[1], [2]], at: 2) == SwitcherReorder(target: 2, after: true))
    }

    @Test func `Past the line the pointer aims among the floating windows, before it at a gap`() {
        let spans: [ClosedRange<CGFloat>] = [10...110, 122...222]
        #expect(SwitcherReorder.target(at: 239, spans: spans, allowed: 0...2, divider: 240) == .column(2))
        #expect(SwitcherReorder.target(at: 240, spans: spans, allowed: 0...2, divider: 240) == .float)
        #expect(SwitcherReorder.target(at: 500, spans: spans, allowed: 0...2, divider: 240) == .float)
        #expect(SwitcherReorder.target(at: 0, spans: spans, allowed: 1...2, divider: 240) == .column(1))
        // No line, no floating windows to go among.
        #expect(SwitcherReorder.target(at: 500, spans: spans, allowed: 0...2, divider: nil) == .column(2))
    }

    @Test func `Over a tree the pointer aims at the nearest card's zone`() {
        let cards: [(id: WindowID, frame: CGRect)] = [(1, rect(10, 10, 100, 100)), (2, rect(122, 10, 100, 100))]
        func aim(_ x: CGFloat, _ y: CGFloat, swaps: Bool = true, divider: CGFloat? = 240) -> SwitcherDropTarget? {
            SwitcherReorder.target(at: CGPoint(x: x, y: y), cards: cards, swaps: swaps, divider: divider)
        }
        #expect(aim(20, 60) == .card(1, .split(.left)))
        #expect(aim(100, 60) == .card(1, .split(.right)))
        #expect(aim(60, 15) == .card(1, .split(.up)))
        #expect(aim(60, 105) == .card(1, .split(.down)))
        #expect(aim(61, 60) == .card(1, .swap))
        // A floating window has no place to swap into: the middle goes to a side.
        #expect(aim(61, 60, swaps: false) == .card(1, .split(.right)))
        // Off the cards, the nearest; past the line, the floating windows; with none, still the nearest.
        #expect(aim(118, 60) == .card(2, .split(.left)))
        #expect(aim(240, 60) == .float)
        #expect(aim(400, 60, divider: nil) == .card(2, .split(.right)))
        #expect(SwitcherReorder.target(at: .zero, cards: [], swaps: true, divider: nil) == nil)
    }

    @Test func `Over a strip's card its bands stack, its middle swaps, and its sides are the gaps`() {
        let cards: [(id: WindowID, frame: CGRect)] = [(1, rect(10, 10, 100, 100)), (2, rect(122, 10, 100, 100))]
        let spans: [ClosedRange<CGFloat>] = [10...110, 122...222]
        func aim(_ x: CGFloat, _ y: CGFloat, on: [(id: WindowID, frame: CGRect)]? = nil, allowed: ClosedRange<Int> = 0...2) -> SwitcherDropTarget {
            SwitcherReorder.target(at: CGPoint(x: x, y: y), cards: on ?? cards, spans: spans, allowed: allowed, divider: 240)
        }
        #expect(aim(60, 15) == .card(1, .split(.up)))
        #expect(aim(60, 105) == .card(1, .split(.down)))
        #expect(aim(60, 60) == .card(1, .swap))
        #expect(aim(20, 60) == .column(0))
        #expect(aim(100, 60) == .column(1))
        #expect(aim(116, 60) == .column(1))
        #expect(aim(240, 60) == .float)
        // A card it cannot go onto, as a pinned one's, is only ever beside.
        #expect(aim(60, 15, on: [cards[1]], allowed: 1...2) == .column(1))
    }

    @Test func `A card's marked part is the half a drop takes, or all of it for a swap`() {
        let card = rect(10, 20, 100, 60)
        #expect(SwitcherReorder.marked(card, .split(.left)) == rect(10, 20, 50, 60))
        #expect(SwitcherReorder.marked(card, .split(.right)) == rect(60, 20, 50, 60))
        #expect(SwitcherReorder.marked(card, .split(.up)) == rect(10, 20, 100, 30))
        #expect(SwitcherReorder.marked(card, .split(.down)) == rect(10, 50, 100, 30))
        #expect(SwitcherReorder.marked(card, .swap) == card)
    }

    @Test func `A drop changes a tree unless the window is just there already`() {
        var strip = workspace(3, algorithm: .scrolling)
        #expect(SwitcherReorder.changes(strip, moving: 1, onto: 2, .split(.down)))
        #expect(SwitcherReorder.changes(strip, moving: 1, onto: 2, .swap))
        strip.drop(3, onto: 2, .split(.down))
        #expect(!SwitcherReorder.changes(strip, moving: 3, onto: 2, .split(.down)))
        #expect(SwitcherReorder.changes(strip, moving: 3, onto: 2, .split(.up)))
        let tiles = workspace(2, algorithm: .dwindle(.tiles))
        #expect(SwitcherReorder.changes(tiles, moving: 1, onto: 2, .swap))
    }

    @Test func `Dropped on a side of a tile, a window of a tree splits it`() {
        var ws = workspace(2, algorithm: .dwindle(.tiles))
        ws.insert(9)
        #expect(ws.windows.count == 3)
        let dropped = ws.drop(9, onto: 2, .split(.down))
        #expect(dropped)
        #expect(ws.root.path(of: 9) != nil)
        let frames = ws.layout().frames
        #expect(frames[9]?.minX == frames[2]?.minX)
        #expect(frames[9]!.minY > frames[2]!.minY)
    }

    @Test func `The marker sits in the middle of a gap, or past an end`() {
        let spans: [ClosedRange<CGFloat>] = [10...110, 122...222]
        #expect(SwitcherReorder.markerX(0, spans: spans, gap: 12) == 4)
        #expect(SwitcherReorder.markerX(1, spans: spans, gap: 12) == 116)
        #expect(SwitcherReorder.markerX(2, spans: spans, gap: 12) == 228)
        #expect(SwitcherReorder.markerX(0, spans: [], gap: 12) == nil)
    }
}
