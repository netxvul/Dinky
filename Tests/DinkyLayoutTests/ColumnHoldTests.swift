import CoreGraphics
import Testing
@testable import DinkyLayout

struct ColumnHoldTests {
    // A strip scrolling left: the column of 1 over 2 is on its way in from the right edge.
    let frames: [WindowID: CGRect] = [1: rect(600, 0, 400, 300), 2: rect(600, 300, 400, 300), 3: rect(100, 0, 400, 600)]

    @Test func `A quick window keeps with the slow one over it as it shows`() {
        let shown: [WindowID: CGRect] = [1: rect(1475, 0, 400, 300), 2: rect(620, 300, 400, 300)]
        let result = ColumnHold.held(frames, columns: [[3], [1, 2]], slow: [1], shown: { shown[$0] })
        #expect(result.frames[1] == rect(600, 0, 400, 300))
        #expect(result.frames[2] == rect(1475, 300, 400, 300))
        #expect(result.frames[3] == rect(100, 0, 400, 600))
        #expect(result.held == [2])
    }

    @Test func `A slow window where the glide has it holds nothing back`() {
        let shown: [WindowID: CGRect] = [1: rect(600.5, 0, 400, 300)]
        let result = ColumnHold.held(frames, columns: [[3], [1, 2]], slow: [1], shown: { shown[$0] })
        #expect(result.frames == frames)
        #expect(result.held.isEmpty)
    }

    @Test func `A column all of quick or all of slow windows glides as it is`() {
        let shown: [WindowID: CGRect] = [1: rect(1475, 0, 400, 300), 2: rect(900, 300, 400, 300)]
        var reads = 0
        let quick = ColumnHold.held(frames, columns: [[1, 2]], slow: [], shown: { reads += 1; return shown[$0] })
        #expect(quick.frames == frames)
        #expect(quick.held.isEmpty)
        #expect(reads == 0)
        #expect(ColumnHold.held(frames, columns: [[1, 2]], slow: [1, 2], shown: { shown[$0] }).frames == frames)
    }

    @Test func `A lone window is no column to hold`() {
        let shown: [WindowID: CGRect] = [3: rect(900, 0, 400, 600)]
        #expect(ColumnHold.held(frames, columns: [[3]], slow: [3], shown: { shown[$0] }).frames == frames)
    }

    @Test func `The quick ones keep with the slow window furthest behind`() {
        let frames = self.frames.merging([4: rect(600, 200, 400, 100)]) { $1 }
        let shown: [WindowID: CGRect] = [1: rect(700, 0, 400, 300), 4: rect(1000, 200, 400, 100)]
        let result = ColumnHold.held(frames, columns: [[1, 4, 2]], slow: [1, 4], shown: { shown[$0] })
        #expect(result.frames[2] == rect(1000, 300, 400, 300))
        #expect(result.frames[1] == frames[1])
        #expect(result.frames[4] == frames[4])
    }

    @Test func `A slow window with nothing shown holds nothing back`() {
        let result = ColumnHold.held(frames, columns: [[1, 2]], slow: [1], shown: { _ in nil })
        #expect(result.frames == frames)
    }

    @Test func `The strip's columns are its windows column by column`() {
        var ws = workspace(3, algorithm: .scrolling)
        ws.focus(2)
        let joined = ws.join(.left)
        #expect(joined)
        #expect(ws.stripColumns == [[1, 2], [3]])
        #expect(workspace(2).stripColumns.isEmpty)
    }
}
