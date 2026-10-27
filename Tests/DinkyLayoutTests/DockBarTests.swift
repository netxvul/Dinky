import CoreGraphics
import Testing
@testable import DinkyLayout

struct DockBarTests {
    let main = rect(0, 0, 1800, 1169)
    let secondary = rect(-1441, -1200, 1920, 1200)

    @Test func `A bar a little above the bottom edge is shown`() {
        #expect(dockBarShown(rect(163, 1101, 1474, 58), on: [main, secondary]))
    }

    @Test func `A bar along the left or right edge is shown`() {
        #expect(dockBarShown(rect(4, 300, 58, 500), on: [main]))
        #expect(dockBarShown(rect(1738, 300, 58, 500), on: [main]))
    }

    @Test func `A bar on another display is shown there`() {
        #expect(dockBarShown(rect(-1000, -68, 1000, 58), on: [main, secondary]))
    }

    @Test func `A bar off its edge, past it or at the top is not shown`() {
        #expect(!dockBarShown(rect(163, 1040, 1474, 58), on: [main]))
        #expect(!dockBarShown(rect(163, 1150, 1474, 58), on: [main]))
        #expect(!dockBarShown(rect(163, 4, 1474, 58), on: [main]))
        #expect(!dockBarShown(rect(163, 1101, 1474, 58), on: [secondary]))
    }
}
