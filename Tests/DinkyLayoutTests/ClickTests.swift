import CoreGraphics
import Testing
@testable import DinkyLayout

struct ClickTests {
    let video = ScreenWindow(id: 7713, pid: 1, layer: 3, frame: CGRect(x: 400, y: 400, width: 480, height: 270))
    let editor = ScreenWindow(id: 89, pid: 2, layer: 0, frame: CGRect(x: 0, y: 0, width: 1200, height: 800))

    @Test func `A click on a floating window in front`() {
        #expect(windowAt(CGPoint(x: 500, y: 500), in: [video, editor]) == video)
    }

    @Test func `A window in front of the floating one is the one clicked`() {
        #expect(windowAt(CGPoint(x: 500, y: 500), in: [editor, video]) == editor)
    }

    @Test func `The mouse beside the floating window`() {
        #expect(windowAt(CGPoint(x: 100, y: 100), in: [video, editor]) == editor)
        #expect(windowAt(CGPoint(x: 2000, y: 100), in: [video, editor]) == nil)
    }
}
