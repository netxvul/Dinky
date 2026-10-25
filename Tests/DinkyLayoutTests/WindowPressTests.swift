import CoreGraphics
import Testing
@testable import DinkyLayout

struct WindowPressTests {
    /// A window half on screen at the right edge as it was pressed, and its tile once focusing it centred its column.
    let pressed = rect(1339, 47, 863, 1050)
    let centred = rect(468, 47, 863, 1050)

    @Test func `A window told of moving where it was pressed is a click, wherever its tile went`() {
        let press = WindowPress.of(5200, at: 10, from: pressed, known: nil)
        #expect(press.frame == pressed)
        #expect(press.after(pressed, tile: centred) == press)
    }

    @Test func `A hand drifting a point as it presses is still a click`() {
        let press = WindowPress.of(5461, at: 10, from: rect(1057, 47, 867, 1050), known: nil)
        #expect(press.after(rect(1057, 46, 867, 1050), tile: rect(925, 47, 867, 1050)) == press)
    }

    @Test func `A window taken off where it was pressed is dragged from there`() {
        let press = WindowPress.of(251, at: 10, from: pressed, known: nil)
        #expect(press.after(pressed.offsetBy(dx: -6, dy: 3), tile: centred) == nil)
        #expect(press.after(rect(1339, 47, 900, 1050), tile: centred) == nil, "resized by its edge")
    }

    @Test func `Drift adds up from where the window was pressed, not from its last change`() {
        var press = WindowPress.of(251, at: 10, from: pressed, known: nil)
        for dx in [1, 2] as [CGFloat] {
            press = WindowPress.of(251, at: 10.001, from: pressed.offsetBy(dx: dx - 1, dy: 0), known: press)
            #expect(press.frame == pressed)
            #expect(press.after(pressed.offsetBy(dx: dx, dy: 0), tile: centred) == press)
        }
        let next = WindowPress.of(251, at: 10.002, from: pressed.offsetBy(dx: 2, dy: 0), known: press)
        #expect(next.after(pressed.offsetBy(dx: 3, dy: 0), tile: centred) == nil)
    }

    @Test func `A window put in its tile under the press is not dragged there, and the press goes on from there`() {
        let press = WindowPress.of(4885, at: 10, from: pressed, known: nil)
        let placed = press.after(centred, tile: centred)
        #expect(placed == WindowPress(id: 4885, frame: centred, at: 10))
        #expect(placed?.after(centred.offsetBy(dx: 0, dy: 1), tile: centred) == placed)
        #expect(placed?.after(centred.offsetBy(dx: 30, dy: 0), tile: centred) == nil)
    }

    @Test func `Without a tile only where it was pressed counts`() {
        let press = WindowPress.of(5200, at: 10, from: pressed, known: nil)
        #expect(press.after(pressed.offsetBy(dx: 0, dy: 1), tile: nil) == press)
        #expect(press.after(centred, tile: nil) == nil)
    }

    @Test func `Another press, or a press on another window, starts from where the window is`() {
        let press = WindowPress.of(5200, at: 10, from: pressed, known: nil)
        let again = WindowPress.of(5200, at: 12, from: centred, known: press)
        #expect(again == WindowPress(id: 5200, frame: centred, at: 12))
        let other = WindowPress.of(251, at: 10, from: centred, known: press)
        #expect(other == WindowPress(id: 251, frame: centred, at: 10))
    }

    @Test func `Readings of one press a moment apart are the same press`() {
        let press = WindowPress.of(5200, at: 10, from: pressed, known: nil)
        #expect(WindowPress.of(5200, at: 10.005, from: centred, known: press) == press)
        #expect(WindowPress.of(5200, at: 9.995, from: centred, known: press) == press)
    }

    @Test func `Focusing a half-shown column centres its tile at once, and a press on it stays a click`() {
        var ws = Workspace(bounds: rect(-Workspace.peek, 0, 1000 + 2 * Workspace.peek, 600), gaps: .zero,
                           algorithm: .scrolling)
        ws.columnWidth = 0.5
        ws.columnCentring = .always
        for id in 1...4 { ws.insert(WindowID(id)) }
        ws.focus(3)
        let shown = ws.layout().frames[4]!
        ws.focus(4)
        let tile = ws.layout().frames[4]!
        #expect(!tile.isClose(to: shown, within: WindowPress.slack), "the tile went with the strip, the window did not")
        let press = WindowPress.of(4, at: 1, from: shown, known: nil)
        #expect(press.after(shown, tile: tile) == press)
        #expect(press.after(shown.offsetBy(dx: 0, dy: -1), tile: tile) == press)
    }
}
