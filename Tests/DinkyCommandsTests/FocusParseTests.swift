import DinkyLayout
import Testing
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

struct FocusParseTests {
    @Test func `Defaults are workspace and stop`() throws {
        #expect(try parse("focus left") == .focus(.left, boundaries: .workspace, action: .stop))
    }

    @Test func `Boundaries flags in any order`() throws {
        #expect(try parse("focus --boundaries all-monitors-outer-frame left") ==
                .focus(.left, boundaries: .allMonitorsOuterFrame, action: .stop))
        #expect(try parse("focus down --boundaries-action wrap-around-the-workspace") ==
                .focus(.down, boundaries: .workspace, action: .wrapAroundTheWorkspace))
        #expect(try parse("focus --boundaries-action fail --boundaries workspace up") ==
                .focus(.up, boundaries: .workspace, action: .fail))
        #expect(try parse("focus right --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors") ==
                .focus(.right, boundaries: .allMonitorsOuterFrame, action: .wrapAroundAllMonitors))
        #expect(try parse("focus --wrap-around left") == .focus(.left, boundaries: .workspace, action: .wrapAroundTheWorkspace))
    }

    @Test(arguments: ["focus", "focus --boundaries left", "focus left --boundaries screen", "focus left --boundaries-action loop",
                      "focus left right", "focus left --frobnicate"])
    func `Bad focus flags`(s: String) {
        #expect(throws: (any Error).self) { try parse(s) }
    }

    @Test func `Wrap around all monitors needs the outer frame`() {
        let error = #expect(throws: CommandError.self) {
            try parse("focus left --boundaries-action wrap-around-all-monitors")
        }
        #expect(error?.description.contains("all-monitors-outer-frame") == true, "\(error?.description ?? "")")
    }

    @Test func `Focus monitor`() throws {
        for word in ["left", "right", "up", "down", "next", "prev", "recent"] {
            #expect(try parse("focus-monitor \(word)") == .focusMonitor(MonitorTarget(rawValue: word)!))
        }
        #expect(MonitorTarget.up.direction == .up)
        #expect(MonitorTarget.next.direction == nil)
        #expect(MonitorTarget.recent.direction == nil)
        #expect(throws: (any Error).self) { try parse("focus-monitor") }
        #expect(throws: (any Error).self) { try parse("focus-monitor main") }
        #expect(try parse("focus-monitor 2") == .focusMonitorNumber(2))
        #expect(throws: (any Error).self) { try parse("focus-monitor 0") }
    }

    @Test func `Balance sizes`() throws {
        #expect(try parse("balance-sizes") == .balanceSizes)
        #expect(throws: (any Error).self) { try parse("balance-sizes --workspace 2") }
    }
}
