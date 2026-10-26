import DinkyConfig
import DinkyLayout
import Testing
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

struct ParseTests {
    @Test func workspace() throws {
        #expect(try parse("workspace 3") == .workspace(.number(3)))
        #expect(try parse("workspace prev") == .workspace(.prev))
        #expect(try parse("workspace next") == .workspace(.next))
        #expect(try parse("workspace recent") == .workspace(.recent))
        #expect(try parse("workspace-back-and-forth") == .workspaceBackAndForth)
    }

    @Test func `Move window to workspace`() throws {
        #expect(try parse("move-window-to-workspace 1") == .moveWindowToWorkspace(.number(1), follow: false))
        #expect(try parse("move-window-to-workspace 3 --follow") == .moveWindowToWorkspace(.number(3), follow: true))
        #expect(try parse("move-window-to-workspace --follow next") == .moveWindowToWorkspace(.next, follow: true))
        #expect(try parse("move-window-to-workspace prev") == .moveWindowToWorkspace(.prev, follow: false))
        #expect(try parse("move-window-to-workspace recent --follow") == .moveWindowToWorkspace(.recent, follow: true))
    }

    @Test func `Move window to display`() throws {
        #expect(try parse("move-window-to-display next") == .moveWindowToDisplay(.next, follow: false))
        #expect(try parse("move-window-to-display prev --follow") == .moveWindowToDisplay(.prev, follow: true))
        #expect(try parse("move-window-to-display recent") == .moveWindowToDisplay(.recent, follow: false))
    }

    @Test(arguments: [("left", Direction.left), ("down", .down), ("up", .up), ("right", .right)])
    func directional(word: String, dir: Direction) throws {
        #expect(try parse("focus \(word)") == .focus(dir))
        #expect(try parse("move \(word)") == .move(dir))
        #expect(try parse("join-with \(word)") == .joinWith(dir))
    }

    @Test func `Rotate and mirror`() throws {
        #expect(try parse("rotate 90") == .rotate(.quarter))
        #expect(try parse("rotate 180") == .rotate(.half))
        #expect(try parse("rotate 270") == .rotate(.threeQuarters))
        #expect(try parse("mirror x-axis") == .mirror(.xAxis))
        #expect(try parse("mirror y-axis") == .mirror(.yAxis))
        for bad in ["rotate", "rotate 45", "rotate 90 180", "mirror", "mirror z-axis", "mirror x"] {
            #expect(throws: (any Error).self, "\(bad)") { try parse(bad) }
        }
    }

    @Test func resize() throws {
        #expect(try parse("resize smart -50") == .resize(.smart, by: -50))
        #expect(try parse("resize smart +50") == .resize(.smart, by: 50))
        #expect(try parse("resize width +10") == .resize(.width, by: 10))
        #expect(try parse("resize height -20") == .resize(.height, by: -20))
        #expect(try parse("resize width -10 --floating-only") == .resize(.width, by: -10, floatingOnly: true))
        #expect(try parse("resize --floating-only height +10") == .resize(.height, by: 10, floatingOnly: true))
    }

    @Test func `Move with points and floating-only`() throws {
        #expect(try parse("move left 10") == .move(.left, points: 10))
        #expect(try parse("move up --floating-only") == .move(.up, floatingOnly: true))
        #expect(try parse("move right 25 --floating-only") == .move(.right, points: 25, floatingOnly: true))
        #expect(try parse("move --floating-only down 5") == .move(.down, points: 5, floatingOnly: true))
    }

    @Test(arguments: ["move left 0", "move left -10", "move left +10", "move left 1.5", "move left ten", "move left 10 20",
                      "move 10", "move left --floating-only --floating-only", "resize width +10 --floating",
                      "resize width +10 --floating-only --floating-only"])
    func `Bad move and resize arguments`(input: String) {
        #expect(throws: CommandError.self) { try parse(input) }
    }

    @Test func layout() throws {
        #expect(try parse("layout tiles") == .layout([.tiles]))
        #expect(try parse("layout accordion") == .layout([.accordion]))
        #expect(try parse("layout floating") == .layout([.floating]))
        #expect(try parse("layout tiling") == .layout([.tiling]))
        #expect(try parse("layout floating tiling") == .layout([.floating, .tiling]))
        #expect(try parse("layout accordion tiles") == .layout([.accordion, .tiles]))
        #expect(try parse("layout horizontal vertical") == .layout([.horizontal, .vertical]))
        #expect(try parse("layout auto") == .layout([.auto]))
        #expect(try parse("layout accordion horizontal vertical") == .layout([.accordion, .horizontal, .vertical]))
        #expect(try parse("layout h_tiles v_tiles h_accordion v_accordion") == .layout([.hTiles, .vTiles, .hAccordion, .vAccordion]))
        #expect(try parse("layout floating h_accordion auto") == .layout([.floating, .hAccordion, .auto]))
        #expect(try parse("layout tiles accordion scrolling") == .layout([.tiles, .accordion, .scrolling]))
    }

    @Test func grid() throws {
        #expect(try parse("grid 1:2:0:0:1:1") == .grid(GridPlacement(rows: 1, columns: 2, x: 0, y: 0, width: 1, height: 1)!))
        #expect(try parse("grid 6:6:1:1:4:4") == .grid(GridPlacement(rows: 6, columns: 6, x: 1, y: 1, width: 4, height: 4)!))
        let half = GridPlacement(rows: 1, columns: 2, x: 0, y: 0, width: 1, height: 1)!
        #expect(try parse("grid --toggle 1:2:0:0:1:1") == .grid(half, toggle: true))
        #expect(try parse("grid 1:2:0:0:1:1 --toggle") == .grid(half, toggle: true))
    }

    @Test(arguments: ["grid", "grid 1:2:0:0:1", "grid 1:2:0:0:1:1:1", "grid 1:2:0:0:1:x", "grid 1:2::0:1:1",
                      "grid 1:2:0:0:1:1 extra", "grid 1x2", "grid --toggle", "grid --toggle --toggle 1:2:0:0:1:1"])
    func `Grid that is not six numbers`(input: String) {
        #expect(throws: CommandError.self) { try parse(input) }
    }

    @Test func `Pins`() throws {
        #expect(try parse("pin left") == .pin(.left))
        #expect(try parse("pin left --toggle") == .pin(.left, toggle: true))
        #expect(try parse("pin --toggle right") == .pin(.right, toggle: true))
        #expect(try parse("unpin") == .unpin(nil))
        #expect(try parse("unpin right") == .unpin(.right))
        #expect(try parse("focus-pin left") == .focusPin(.left))
    }

    @Test(arguments: ["pin", "pin up", "pin --toggle", "pin left right", "pin left --toggle --toggle", "unpin up",
                      "unpin left right", "unpin --toggle", "focus-pin", "focus-pin up", "focus-pin left right"])
    func `Pins on no side`(input: String) {
        #expect(throws: CommandError.self) { try parse(input) }
    }

    @Test func `Cycle size`() throws {
        #expect(try parse("cycle-size 50% 30% 60%") == .cycleSize([50, 30, 60]))
        #expect(try parse("cycle-size 50 100") == .cycleSize([50, 100]))
    }

    @Test(arguments: ["cycle-size", "cycle-size 0%", "cycle-size 101%", "cycle-size 50% x", "cycle-size 50.5%", "cycle-size %"])
    func `Cycle size that is not percentages`(input: String) {
        #expect(throws: CommandError.self) { try parse(input) }
    }

    @Test func `Grid span past its cells names the problem`() {
        do {
            _ = try parse("grid 2:2:1:0:2:1")
            Issue.record("parsed")
        } catch {
            #expect("\(error)".contains("must fit"))
        }
    }

    @Test func `Several layouts cycle from the last that describes the window`() {
        let cycle: [LayoutName] = [.tiles, .accordion, .scrolling]
        #expect(LayoutName.next(in: cycle, current: [.tiling, .tiles, .horizontal, .hTiles]) == .accordion)
        #expect(LayoutName.next(in: cycle, current: [.tiling, .accordion, .horizontal, .hAccordion]) == .scrolling)
        #expect(LayoutName.next(in: cycle, current: [.tiling, .scrolling]) == .tiles)
        #expect(LayoutName.next(in: cycle, current: [.floating]) == .tiles, "none describes it")
        #expect(LayoutName.next(in: [.floating, .tiling], current: [.tiling, .tiles]) == .floating)
        #expect(LayoutName.next(in: [.floating, .tiling], current: [.floating]) == .tiling)
        #expect(LayoutName.next(in: [.accordion], current: [.tiling, .accordion]) == .accordion)
    }

    @Test func `Layout names set mode, orientation or both`() {
        #expect(LayoutName.hAccordion.mode == .accordion)
        #expect(LayoutName.hAccordion.orientation == .horizontal)
        #expect(LayoutName.vertical.mode == nil)
        #expect(LayoutName.auto.orientation == .auto)
        #expect(LayoutName.tiles.orientation == nil)
    }

    @Test func `Layout states describe the resolved axis`() {
        #expect(LayoutName.describing(.accordion, axis: .vertical, auto: true) == [.accordion, .vertical, .vAccordion, .auto])
        #expect(LayoutName.describing(.tiles, axis: .horizontal, auto: false) == [.tiles, .horizontal, .hTiles])
    }

    @Test func `Simple commands`() throws {
        #expect(try parse("fullscreen") == .fullscreen)
        #expect(try parse("flatten-workspace-tree") == .flattenWorkspaceTree)
        #expect(try parse("mode service") == .mode("service"))
        #expect(try parse("reload-config") == .reloadConfig)
        #expect(try parse("enable on") == .enable(.on))
        #expect(try parse("enable off") == .enable(.off))
        #expect(try parse("enable toggle") == .enable(.toggle))
        #expect(try parse("retile") == .retile)
        #expect(try parse("window-switcher") == .windowSwitcher)
        #expect(try parse("workspace-switcher") == .workspaceSwitcher)
        #expect(throws: (any Error).self) { try parse("workspace-switcher next") }
        #expect(try parse("clear-minimum-sizes") == .clearMinimumSizes)
        #expect(try parse("exec-and-forget sketchybar --trigger 'a b'") == .execAndForget("sketchybar --trigger 'a b'"))
        #expect(try parse("  exec-and-forget   echo  hi") == .execAndForget("echo  hi"))
    }

    @Test func `Extra whitespace is ignored`() throws {
        #expect(try parse("  workspace   2 \n") == .workspace(.number(2)))
    }

    private static let defaultBindings = Config.default.modes.values.flatMap { $0.bindings.values.flatMap { $0 } }

    @Test func `Default config has bindings`() {
        #expect(!Self.defaultBindings.isEmpty)
    }

    @Test(arguments: defaultBindings + Config.default.rules.flatMap(\.run))
    func `Every default binding parses`(command: String) {
        #expect(throws: Never.self) { try parse(command) }
    }

    @Test func `Documented names are unique`() {
        #expect(Set(Command.all.map(\.name)).count == Command.all.count)
    }

    /// One line that parses, per documented command.
    private static let knownGood = [
        "workspace 1", "workspace-back-and-forth", "move-window-to-workspace 2 --follow", "move-window-to-display next",
        "focus left", "focus-monitor next", "move left", "join-with left", "resize smart +10", "layout tiles",
        "fullscreen", "grid 1:2:0:0:1:1", "cycle-size 50% 30% 60%", "pin left --toggle", "unpin", "focus-pin right", "flatten-workspace-tree", "balance-sizes", "rotate 90", "mirror y-axis", "retile", "window-switcher", "workspace-switcher", "clear-minimum-sizes", "mode main", "reload-config", "enable on",
        "list-workspaces", "list-windows", "list-monitors", "list-displays", "list-modes", "debug-state", "exec-and-forget true",
    ]

    @Test func `Known-good lines cover exactly the documented names`() {
        let names = Self.knownGood.map { String($0.prefix { $0 != " " }) }
        #expect(names.count == Self.knownGood.count, "a name has two known-good lines")
        #expect(Set(names) == Set(Command.all.map(\.name)))
    }

    @Test(arguments: Command.all.map(\.name))
    func `Every documented name parses`(name: String) throws {
        let line = try #require(Self.knownGood.first { $0.hasPrefix(name + " ") || $0 == name }, "no known-good line")
        #expect(Command.words(line).first == name)
        #expect(throws: Never.self) { try parse(line) }
    }

    @Test(arguments: Command.all.map(\.name).filter { $0 != "exec-and-forget" })
    func `Every documented name rejects extra words`(name: String) {
        #expect(throws: (any Error).self) { try parse("\(name) bogus extra words") }
    }
}

struct ParseErrorTests {
    private func message(_ s: String) -> String {
        do {
            _ = try Command.parse(s)
            return "parsed"
        } catch {
            #expect(error.input == s)
            return error.description
        }
    }

    @Test func `Unknown command names string and commands`() {
        let m = message("frobnicate 3")
        #expect(m.contains("'frobnicate 3'"), "\(m)")
        #expect(m.contains("workspace-back-and-forth"), "\(m)")
    }

    @Test func `Bad arguments name string and syntax`() {
        let m = message("workspace zero")
        #expect(m.contains("'workspace zero'"), "\(m)")
        #expect(m.contains("workspace <number|prev|next|recent>"), "\(m)")
    }

    @Test(arguments: ["", "   ", "workspace", "workspace 0", "workspace -1", "workspace 1 2", "focus sideways",
                      "resize smart 50", "resize diagonal +50", "resize smart +x", "layout", "layout grid",
                      "layout tiles grid", "layout accordion h_list", "layout horizontal sideways", "layout auto_tiles", "move-window-to-display 2", "move-window-to-workspace --follow",
                      "mode", "mode a b", "enable maybe", "fullscreen now", "Workspace 1", "exec-and-forget", "exec-and-forget  "])
    func `Bad strings`(s: String) {
        #expect(message(s) != "parsed")
    }

    @Test func empty() {
        #expect(message("") == "empty command")
    }
}

struct QuotingTests {
    @Test func `Words keep quoted spaces`() {
        #expect(Command.words(#"list-windows --format '%{app-name} | %{window-title}'"#) ==
                ["list-windows", "--format", "%{app-name} | %{window-title}"])
        #expect(Command.words(#"a "b 'c'" '' d"#) == ["a", "b 'c'", "", "d"])
    }

    @Test func `Line round-trips through words`() {
        let args = ["list-windows", "--format", "%{window-id} | %{app-name}", "--workspace", "1", "it's"]
        #expect(Command.words(Command.line(args)) == args)
        #expect(Command.line(["workspace", "3"]) == "workspace 3")
    }

    @Test func `Exec-and-forget line is passed as written`() {
        #expect(Command.line(["exec-and-forget", "echo 'a b'", "> /tmp/x"]) == "exec-and-forget echo 'a b' > /tmp/x")
    }
}
