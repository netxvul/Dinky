import CoreGraphics
import Foundation
import Testing
@testable import DinkyLayout

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

    @Test func `It survives being written out`() throws {
        var source = strip([1, 2, 3])
        source.focus(3)
        let joined = source.join(.left)
        #expect(joined)
        let saved = source.stripMemory!
        let read = try JSONDecoder().decode(StripMemory.self, from: JSONEncoder().encode(saved))
        #expect(read == saved)
    }
}
