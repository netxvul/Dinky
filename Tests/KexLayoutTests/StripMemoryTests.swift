import CoreGraphics
import Foundation
import Testing
@testable import KexLayout

struct StripMemoryTests {
    private func strip(_ ids: [WindowID] = []) -> Workspace {
        var ws = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), algorithm: .scrolling)
        for id in ids { ws.insert(id) }
        return ws
    }

    private func columns(_ ws: Workspace) -> [[WindowID]] { ws.root.children.map(\.windows) }

    private func memory(_ columns: [[WindowID]], focused: WindowID? = nil, scrollOffset: CGFloat = 0) -> StripMemory {
        StripMemory(columns: columns.map { .init(windows: $0, width: 0.5) }, departedWidths: [:], focused: focused,
                    scrollOffset: scrollOffset)
    }

    @Test(arguments: [[1, 2, 3, 4], [4, 3, 2, 1], [3, 1, 4, 2], [2, 4, 1, 3]] as [[WindowID]])
    func `Windows go back to their order, whichever order they arrive in`(arrivals: [WindowID]) {
        let saved = memory([[1], [2], [3], [4]])
        var ws = strip()
        for id in arrivals { ws.arrive(id, remembering: saved) }
        #expect(columns(ws) == [[1], [2], [3], [4]])
    }

    @Test func `A column's stack goes back together, in its order`() {
        var source = strip([1, 2, 3])
        source.focus(3)
        let joined = source.join(.left)
        #expect(joined)
        let saved = source.stripMemory!
        var ws = strip()
        for id in [3, 1, 2] as [WindowID] { ws.arrive(id, remembering: saved) }
        #expect(columns(ws) == columns(source))
        #expect(ws.stripMemory!.columns == saved.columns)
    }

    @Test func `Each column gets its width back`() {
        var saved = memory([[1], [2]])
        saved.columns[1].width = 0.8
        var ws = strip()
        for id in [2, 1] as [WindowID] { ws.arrive(id, remembering: saved) }
        #expect(ws.width(ofColumn: 0) == 0.5)
        #expect(ws.width(ofColumn: 1) == 0.8)
    }

    @Test func `A window arriving late goes back beside its neighbours, keeping what was done meanwhile`() {
        let saved = memory([[1], [2], [3], [4]])
        var ws = strip()
        for id in [1, 2, 4] as [WindowID] { ws.arrive(id, remembering: saved) }
        ws.insert(9)
        ws.arrive(3, remembering: saved)
        #expect(columns(ws) == [[1], [9], [2], [3], [4]])
        #expect(ws.focused == 9)
    }

    @Test func `Focus goes to the window that had it, and the strip scrolls as it was`() {
        let saved = memory([[1], [2], [3], [4]], focused: 3, scrollOffset: 250)
        var ws = strip()
        for id in [1, 3, 2, 4] as [WindowID] { ws.arrive(id, remembering: saved) }
        #expect(ws.focused == 3)
        #expect(ws.scrollOffset == 250)
    }

    @Test func `A window coming in unasked leaves focus and what shows as they were`() {
        var ws = strip([1, 2, 3, 4])
        ws.focus(3)
        let x = ws.layout().frames[3]!.minX
        let saved = memory([[9], [1], [2], [3], [4]], focused: 9, scrollOffset: 0)
        ws.arrive(9, remembering: saved)
        #expect(columns(ws) == [[9], [1], [2], [3], [4]])
        ws.refocus(3, standingAt: x)
        #expect(ws.focused == 3)
        #expect(ws.layout().frames[3]!.minX == x)
    }

    @Test func `A window it does not remember comes as any new one`() {
        var ws = strip([1, 2])
        ws.focus(1)
        ws.arrive(9, remembering: memory([[5]]))
        #expect(columns(ws) == [[1], [9], [2]])
        #expect(ws.focused == 9)
    }

    @Test func `A window away from the strip takes its width back as it comes`() {
        var saved = memory([[1]])
        saved.departedWidths[2] = 0.7
        var ws = strip()
        ws.arrive(1, remembering: saved)
        ws.arrive(2, remembering: saved)
        #expect(ws.width(ofColumn: ws.root.path(of: 2)![0]) == 0.7)
    }

    @Test func `Windows gone are left out`() {
        var saved = memory([[1, 2], [3]], focused: 3)
        saved.departedWidths = [4: 0.7, 5: 0.6]
        let kept = saved.keeping([2, 5])
        #expect(kept.columns.map(\.windows) == [[2]])
        #expect(kept.departedWidths == [5: 0.6])
        #expect(kept.focused == nil)
        #expect(kept.windows == [2, 5])
    }

    /// A strip of `ids` with `pinned`'s column pinned to `side`, in a workspace of real width for the band's room.
    private func pinnedStrip(_ ids: [WindowID], _ pinned: WindowID, _ side: PinSide) -> Workspace {
        var ws = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), algorithm: .scrolling)
        ws.columnWidth = 0.3
        for id in ids { ws.insert(id) }
        ws.focus(pinned)
        let change = ws.pin(side)
        #expect(change == .changed)
        return ws
    }

    @Test(arguments: [[1, 2, 3, 4], [4, 3, 2, 1], [3, 1, 4, 2], [2, 4, 1, 3]] as [[WindowID]])
    func `A pinned column is pinned again, whichever order the windows arrive in`(arrivals: [WindowID]) {
        let source = pinnedStrip([1, 2, 3, 4], 2, .left)
        let saved = source.stripMemory!
        #expect(saved.pins == [.init(side: .left, window: 2, before: 1, after: 3)])
        var ws = Workspace(bounds: source.bounds, algorithm: .scrolling)
        for id in arrivals { ws.arrive(id, remembering: saved) }
        #expect(ws.pins == [.left: 2])
        #expect(columns(ws) == columns(source))
        // Unpinned, it goes back between the columns it was pinned from.
        let unpinned = ws.unpin(.left)
        #expect(unpinned == .changed)
        #expect(columns(ws) == [[1], [2], [3], [4]])
    }

    @Test func `A right pin comes back too, and a pinned stack together`() {
        var source = pinnedStrip([1, 2, 3, 4], 4, .right)
        source.focus(4)
        source.insert(5)
        source.focus(5)
        let joined = source.join(.right)
        #expect(joined)
        #expect(source.pinSide(of: 5) == .right)
        let saved = source.stripMemory!
        var ws = Workspace(bounds: source.bounds, algorithm: .scrolling)
        for id in [5, 1, 4, 3, 2] as [WindowID] { ws.arrive(id, remembering: saved) }
        #expect(ws.pinSide(of: 4) == .right)
        #expect(ws.pinSide(of: 5) == .right)
        #expect(columns(ws) == columns(source))
    }

    @Test func `A pin whose side is taken by then, or whose windows are gone, is dropped`() {
        let saved = pinnedStrip([1, 2, 3], 1, .left).stripMemory!
        // Gone: nothing to pin.
        #expect(saved.keeping([2, 3]).pins == [])
        var ws = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), algorithm: .scrolling)
        ws.columnWidth = 0.3
        ws.insert(9)
        let change = ws.pin(.left)
        #expect(change == .changed)
        for id in [1, 2, 3] as [WindowID] { ws.arrive(id, remembering: saved) }
        #expect(ws.pins == [.left: 9])
        #expect(ws.pinSide(of: 1) == nil)
    }

    @Test func `A session written before pins were kept still reads`() throws {
        var written = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(memory([[1]]))) as? [String: Any])
        written["pins"] = nil
        let old = try JSONSerialization.data(withJSONObject: written)
        let read = try JSONDecoder().decode(StripMemory.self, from: old)
        #expect(read.pins == nil)
        #expect(read.columns.map(\.windows) == [[1]])
    }

    @Test func `It survives being written out`() throws {
        var source = strip([1, 2, 3])
        source.focus(3)
        let joined = source.join(.left)
        #expect(joined)
        let saved = source.stripMemory!
        let read = try JSONDecoder().decode(StripMemory.self, from: JSONEncoder().encode(saved))
        #expect(read == saved)
        let pinned = pinnedStrip([1, 2, 3], 1, .left).stripMemory!
        #expect(try JSONDecoder().decode(StripMemory.self, from: JSONEncoder().encode(pinned)) == pinned)
    }
}
