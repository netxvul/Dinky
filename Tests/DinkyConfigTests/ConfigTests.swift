import Foundation
import Testing
@testable import DinkyConfig

struct ConfigTests {
    @Test func `Default config loads`() throws {
        let config = try Config.parse(Config.defaultTOML)
        #expect(config == Config.default)
        #expect(config.startAtLogin)
        #expect(config.workspaces == 5)
        #expect(config.defaultLayout == .tiles)
        #expect(config.defaultTiling)
        #expect(config.followAppActivation)
        #expect(config.floatWindowsWithoutFullscreen)
        #expect(config.menuBarIcon == .blocks)
        #expect(config.accordion.padding == 30)
        #expect(config.accordion.orientation == .auto)
        #expect(config.gaps == Gaps())
        #expect(config.displays == [])
        #expect(config.borders.enabled)
        #expect(config.borders.width == 4)
        #expect(config.borders.activeColor == Color(red: 0xE1 / 255, green: 0xE3 / 255, blue: 0xE4 / 255))
        #expect(config.hooks == Hooks())
        #expect(config.rules.count == 1)
        #expect(config.rules[0].appId == "com.apple.systempreferences")
        #expect(config.rules[0].run == ["layout floating"])
        #expect(Set(config.modes.keys) == ["main", "service"])
        let main = config.modes["main"]!.bindings
        #expect(try main[KeyCombo("ctrl-left")] == ["workspace prev"])
        #expect(try main[KeyCombo("alt-9")] == ["workspace 9"])
        #expect(try main[KeyCombo("alt-shift-9")] == ["move-window-to-workspace 9"])
        #expect(try main[KeyCombo("alt-k")] == ["focus up"])
        #expect(try main[KeyCombo("alt-shift-l")] == ["move right"])
        #expect(try main[KeyCombo("alt-shift-semicolon")] == ["mode service"])
        #expect(main.count == 37)
        #expect(try config.modes["service"]!.bindings[KeyCombo("esc")] == ["reload-config", "mode main"])
        #expect(try config.modes["service"]!.bindings[KeyCombo("alt-shift-j")] == ["join-with down", "mode main"])
    }

    @Test func `Shipped file is the defaults plus rules and bindings`() throws {
        var shipped = Config.default
        shipped.rules = []
        shipped.modes = [:]
        #expect(shipped == Config(), "a key left out of a user's file must mean what the shipped file says")
    }

    @Test func `Empty config uses defaults`() throws {
        #expect(try Config.parse("") == Config())
    }

    @Test func `Top-level keys`() throws {
        let config = try Config.parse("""
        start-at-login = false
        workspaces = 3
        default-layout = 'accordion'
        follow-app-activation = false
        float-windows-without-fullscreen = false
        menu-bar-icon = 'text'
        """)
        #expect(!config.startAtLogin)
        #expect(config.workspaces == 3)
        #expect(config.defaultLayout == .accordion)
        #expect(!config.followAppActivation)
        #expect(!config.floatWindowsWithoutFullscreen)
        #expect(config.menuBarIcon == .text)
        #expect(try Config.parse("menu-bar-icon = 'none'\n").menuBarIcon == MenuBarIcon.none)
        assertError("menu-bar-icon = 'icon'\n", path: "menu-bar-icon", line: 1, contains: "'blocks', 'text', 'none'")
        assertError("workspaces = 0\n", path: "workspaces", line: 1, contains: "at least 1")
        assertError("default-layout = 'stack'\n", path: "default-layout", line: 1, contains: "'tiles', 'dwindle', 'accordion', 'fixed', 'scrolling'")
    }

    @Test func `Workspace layouts`() throws {
        let config = try Config.parse("""
        default-tiling = false
        [workspace.2]
        tiling = true
        layout = 'fixed'
        columns = 2
        rows = 3
        expand = 'accordion'
        [workspace.3]
        layout = 'accordion'
        [workspace.4]
        float = true
        """)
        #expect(!config.settings(forWorkspace: 1).tiling)
        #expect(!config.settings(forWorkspace: 1).float)
        #expect(config.settings(forWorkspace: 4).float)
        assertError("[workspace.2]\nfloat = 'yes'\n", path: "workspace.2.float", line: 2, contains: "expected true or false")
        let fixed = config.settings(forWorkspace: 2)
        #expect(fixed.tiling)
        #expect(fixed.layout == .fixed)
        #expect(fixed.columns == 2)
        #expect(fixed.rows == 3)
        #expect(fixed.expand == .accordion)
        let accordion = config.settings(forWorkspace: 3)
        #expect(!accordion.tiling, "omitted keys inherit the top-level settings")
        #expect(accordion.layout == .accordion)
        #expect(accordion.rows == 1)
        #expect(accordion.columns == 1)
        #expect(accordion.expand == .columns)
        #expect(config.settings(forWorkspace: nil) == WorkspaceSettings(tiling: false, layout: .tiles),
                "an unnumbered workspace gets the top-level settings")
        assertError("[workspace.0]\nlayout = 'fixed'\n", path: "workspace.0", line: 1, contains: "positive workspace number")
        assertError("[workspace.2]\nlayout = 'fixed'\ncolumns = 0\n", path: "workspace.2.columns", line: 3, contains: "at least 1")
        assertError("[workspace.2]\nlayout = 'fixed'\nrows = 0\n", path: "workspace.2.rows", line: 3, contains: "at least 1")
        assertError("[workspace.2]\nlayout = 'dwindle'\ncolumns = 2\n", path: "workspace.2.columns", line: 3, contains: "only valid")
        assertError("[workspace.2]\ncolumns = 2\n", path: "workspace.2.columns", line: 2, contains: "only valid")
        let inherited = try Config.parse("default-layout = 'fixed'\n[workspace.2]\ncolumns = 3\n")
        #expect(inherited.settings(forWorkspace: 2).columns == 3)
        #expect(inherited.settings(forWorkspace: 2).rows == 1)
        let oneByOne = try Config.parse("[workspace.2]\nlayout = 'fixed'\n")
        #expect(oneByOne.settings(forWorkspace: 2).columns == 1)
        #expect(oneByOne.settings(forWorkspace: 2).rows == 1)
        assertError("[workspace.2]\nlayout = 'fixed'\nexpand = 'diagonal'\n", path: "workspace.2.expand", line: 3, contains: "'rows', 'columns', 'accordion'")
    }

    @Test func `Unknown top-level key fails`() {
        assertError("workspaces = 3\ngap = 8\n", path: "gap", line: 2, contains: "unknown key")
        assertError("config-version = 1\n", path: "config-version", line: 1, contains: "unknown key")
        assertError("auto-reload-config = true\n", path: "auto-reload-config", line: 1, contains: "unknown key")
    }

    @Test func `Unknown key in table fails`() {
        assertError("[gaps]\ninner = 8\n\n[borders]\nwidht = 4\n", path: "borders.widht", line: 5, contains: "unknown key")
        assertError("[gaps]\nouter = { top = 8, tpo = 8 }\n", path: "gaps.outer.tpo", line: 2, contains: "unknown key")
        assertError("[[rules]]\napp-idd = 'x'\nrun = 'y'\n", path: "rules[0].app-idd", line: 2, contains: "unknown key")
        assertError("[switching]\nfollow-app-activation = true\n", path: "switching", line: 1, contains: "unknown key")
        assertError("[layout]\ndefault = 'tiles'\n", path: "layout", line: 1, contains: "unknown key")
        assertError("[borders]\nonly-apps = []\n", path: "borders.only-apps", line: 2, contains: "unknown key")
    }

    @Test func `Bad type fails`() {
        assertError("[gaps]\ninner = 'wide'\n", path: "gaps.inner", line: 2, contains: "expected an integer")
        assertError("workspaces = true\n", path: "workspaces", line: 1, contains: "expected an integer")
        assertError("gaps = 8\n", path: "gaps", line: 1, contains: "expected a table")
        assertError("[accordion]\norientation = 'sideways'\n", path: "accordion.orientation", line: 2, contains: "'auto', 'keep'")
    }

    @Test func accordion() throws {
        let accordion = try Config.parse("[accordion]\npadding = 12\norientation = 'keep'\n").accordion
        #expect(accordion.padding == 12)
        #expect(accordion.orientation == .keep)
    }

    @Test func fullscreen() throws {
        #expect(Config().fullscreen.focusChange == .exit)
        #expect(Config.default.fullscreen == Fullscreen())
        #expect(try Config.parse("[fullscreen]\nfocus-change = 'follow'\n").fullscreen.focusChange == .follow)
        #expect(try Config.parse("[fullscreen]\nfocus-change = 'keep'\n").fullscreen.focusChange == .keep)
        assertError("[fullscreen]\nfocus-change = 'both'\n", path: "fullscreen.focus-change", line: 2, contains: "'exit', 'follow', 'keep'")
        #expect(Config().fullscreen.followDelayMs == 0)
        #expect(try Config.parse("[fullscreen]\nfollow-delay-ms = 200\n").fullscreen.followDelayMs == 200)
        assertError("[fullscreen]\nfollow-delay-ms = -1\n", path: "fullscreen.follow-delay-ms", line: 2, contains: "0 to 5000")
    }

    @Test func floating() throws {
        #expect(Config().floating.moveStep == 50)
        #expect(try Config.parse("[floating]\nmove-step = 20\n").floating.moveStep == 20)
        assertError("[floating]\nmove-step = 0\n", path: "floating.move-step", line: 2, contains: "1 to 1000")
        #expect(Config().floating.resizeAnchor == .center)
        #expect(try Config.parse("[floating]\nresize-anchor = 'top-left'\n").floating.resizeAnchor == .topLeft)
        assertError("[floating]\nresize-anchor = 'corner'\n", path: "floating.resize-anchor", line: 2, contains: "'center', 'top-left'")
    }

    @Test func scrolling() throws {
        #expect(Config().scrolling.columnWidth == 0.49)
        #expect(try Config.parse("[scrolling]\ncolumn-width = 0.5\n").scrolling.columnWidth == 0.5)
        #expect(try Config.parse("default-layout = 'scrolling'\n").defaultLayout == .scrolling)
        assertError("[scrolling]\ncolumn-width = 1.5\n", path: "scrolling.column-width", line: 2, contains: "0.1 to 1")
    }

    @Test func `Window switcher`() throws {
        let defaults = Config().windowSwitcher
        #expect(defaults.modifier == .none)
        #expect(defaults.delayMs == 200)
        #expect(defaults.layouts == [.scrolling, .tiles])
        #expect(defaults.cornerRadius == 52)
        #expect(defaults.tilesStyle == .map)
        let switcher = try Config.parse("""
            [window-switcher]
            modifier = 'alt'
            delay-ms = 0
            layouts = ['tiles', 'fixed']
            corner-radius = 12
            tiles-style = 'row'
            """).windowSwitcher
        #expect(switcher.modifier == .alt)
        #expect(switcher.delayMs == 0)
        #expect(switcher.layouts == [.tiles, .fixed])
        #expect(switcher.cornerRadius == 12)
        #expect(switcher.tilesStyle == .row)
        assertError("[window-switcher]\ntiles-style = 'grid'\n", path: "window-switcher.tiles-style", line: 2, contains: "'map', 'row'")
        assertError("[window-switcher]\nmodifier = 'fn'\n", path: "window-switcher.modifier", line: 2, contains: "'alt'")
        assertError("[window-switcher]\ndelay-ms = 5000\n", path: "window-switcher.delay-ms", line: 2, contains: "0 to 2000")
        assertError("[window-switcher]\nlayouts = ['grid']\n", path: "window-switcher.layouts", line: 2, contains: "'scrolling', 'tiles'")
        assertError("[window-switcher]\ncorner-radius = 90\n", path: "window-switcher.corner-radius", line: 2, contains: "0 to 80")
    }

    @Test func `Workspace switcher`() throws {
        let defaults = Config().workspaceSwitcher
        #expect(defaults.modifier == .none)
        #expect(defaults.displays == .all)
        #expect(defaults.showEmpty)
        #expect(defaults.exclude.isEmpty)
        #expect(defaults.cardHeight == 85)
        #expect(defaults.thumbnails == .windows)
        #expect(defaults.cornerRadius == nil)
        let switcher = try Config.parse("""
            [workspace-switcher]
            modifier = 'ctrl'
            delay-ms = 300
            displays = 'pointer'
            show-empty = false
            exclude = [3, 5]
            card-height = 100
            thumbnails = 'icons'
            corner-radius = 18
            """).workspaceSwitcher
        #expect(switcher.modifier == .ctrl)
        #expect(switcher.delayMs == 300)
        #expect(switcher.displays == .pointer)
        #expect(!switcher.showEmpty)
        #expect(switcher.exclude == [3, 5])
        #expect(switcher.cardHeight == 100)
        #expect(switcher.thumbnails == .icons)
        #expect(switcher.cornerRadius == 18)
        assertError("[window-switcher]\nmodifier = 'alt'\n[workspace-switcher]\nmodifier = 'alt'\n",
                    path: "workspace-switcher.modifier", line: 4, contains: "[window-switcher]")
        #expect(try Config.parse("[workspace-switcher]\nthumbnails = 'schematic'\n").workspaceSwitcher.thumbnails == .schematic)
        assertError("[workspace-switcher]\ndisplays = 'main'\n", path: "workspace-switcher.displays", line: 2, contains: "'all', 'pointer'")
        assertError("[workspace-switcher]\nexclude = ['3']\n", path: "workspace-switcher.exclude", line: 2, contains: "integers")
        assertError("[workspace-switcher]\nexclude = [0]\n", path: "workspace-switcher.exclude", line: 2, contains: "start at 1")
        assertError("[workspace-switcher]\ncard-height = 20\n", path: "workspace-switcher.card-height", line: 2, contains: "60 to 200")
        assertError("[workspace-switcher]\ncorner-radius = 81\n", path: "workspace-switcher.corner-radius", line: 2, contains: "0 to 80")
    }

    @Test func `Syntax error has line`() {
        let error = #expect(throws: ConfigError.self) {
            try Config.parse("workspaces = 5\n[gaps\n")
        }
        if let error { #expect("\(error)".contains("Line 2"), "\(error)") }
    }

    @Test func colours() throws {
        #expect(try Color(hex: "#ff000080") == Color(red: 1, green: 0, blue: 0, alpha: 128 / 255))
        #expect(try Color(hex: "#00FF00") == Color(red: 0, green: 1, blue: 0))
        for bad in ["e1e3e4", "#e1e3", "#e1e3e4g", "#+1e3e4", "0xff0000", "0x80ff0000"] {
            #expect(throws: ConfigError.self, "\(bad)") { try Color(hex: bad) }
        }
        assertError("[borders]\nactive-color = 'red'\n", path: "borders.active-color", line: 2, contains: "'red' is not a colour")
    }

    @Test func borders() throws {
        #expect(Config().borders.order == .below)
        let borders = try Config.parse("""
        [borders]
        order = 'above'
        width = 2.5
        exclude-apps = ['com.apple.finder', 'com.apple.Terminal']
        """).borders
        #expect(borders.order == .above)
        #expect(borders.width == 2.5)
        #expect(borders.excludeApps == ["com.apple.finder", "com.apple.Terminal"])
        #expect(!borders.decorates(bundleID: "com.apple.finder"))
        #expect(borders.decorates(bundleID: "com.apple.TextEdit"))
        #expect(borders.decorates(bundleID: nil))

        assertError("[borders]\norder = 'over'\n", path: "borders.order", line: 2, contains: "'below', 'above'")
        assertError("[borders]\nexclude-apps = 'com.apple.finder'\n", path: "borders.exclude-apps", line: 2, contains: "list of strings")
    }

    @Test func `Binding values`() throws {
        let config = try Config.parse("""
        [mode.main]
        alt-a = 'workspace 1'
        alt-b = ['layout floating', 'mode main']

        [mode.resize]
        minus = 'resize smart -50'
        """)
        let bindings = config.modes["main"]!.bindings
        #expect(bindings[KeyCombo(modifiers: .alt, key: "a")] == ["workspace 1"])
        #expect(bindings[KeyCombo(modifiers: .alt, key: "b")] == ["layout floating", "mode main"])
        #expect(config.modes["resize"]!.bindings[KeyCombo(key: "minus")] == ["resize smart -50"])
    }

    @Test func `Bad binding values fail`() {
        assertError("[mode.main]\nalt-a = ''\n", path: "mode.main.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main]\nalt-a = []\n", path: "mode.main.alt-a", line: 2, contains: "can't be empty")
        assertError("[mode.main]\nalt-a = 3\n", path: "mode.main.alt-a", line: 2, contains: "command string")
        assertError("[mode.main]\nalt-a = ['x', 3]\n", path: "mode.main.alt-a", line: 2, contains: "command string")
        assertError("[mode.main]\nalt-hyper-a = 'x'\n", path: "mode.main.alt-hyper-a", line: 2, contains: "'alt-hyper-a'")
        assertError("[mode.main]\nalt-shift-a = 'x'\nshift-alt-a = 'y'\n", path: "mode.main.shift-alt-a", line: 3, contains: "bound twice")
        assertError("[mode.main.binding]\nalt-a = 'x'\n", path: "mode.main.binding", line: 1, contains: "unknown key 'binding'")
    }

    @Test func `Window rule round-trips`() throws {
        let config = try Config.parse("""
        [[rules]]
        app-id = 'com.apple.finder'
        app-name = 'find'
        title = '^Copy'
        kind = 'dialog'
        run = ['layout floating', 'move-window-to-workspace 2']

        [[rules]]
        run = 'layout tiling'
        """)
        var expected = WindowRule()
        expected.appId = "com.apple.finder"
        expected.appName = "find"
        expected.title = "^Copy"
        expected.kind = .dialog
        expected.run = ["layout floating", "move-window-to-workspace 2"]
        var second = WindowRule()
        second.run = ["layout tiling"]
        #expect(config.rules == [expected, second])

        #expect(expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .dialog))
        #expect(!expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .normal))
        #expect(!expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Desktop", kind: .dialog))
        #expect(!expected.matches(appId: "com.apple.Safari", appName: "Finder", title: "Copy", kind: .dialog))
        #expect(second.matches(appId: nil, appName: nil, title: "", kind: .normal), "a rule with no conditions matches everything")
    }

    @Test func `Bad window rules fail`() {
        assertError("[[rules]]\napp-id = 'x'\n", path: "rules[0].run", line: 1, contains: "every rule needs 'run'")
        assertError("[[rules]]\ntitle = '('\nrun = 'x'\n", path: "rules[0].title", line: 2, contains: "not a valid regex")
        assertError("[[rules]]\nkind = 'popup'\nrun = 'x'\n", path: "rules[0].kind", line: 2, contains: "'normal', 'dialog', 'sheet', 'panel'")
        assertError("[[rules]]\nif.app-id = 'x'\nrun = 'y'\n", path: "rules[0].if", line: 2, contains: "unknown key")
    }

    @Test func hooks() throws {
        #expect(Config.default.hooks == Hooks())
        let hooks = try Config.parse("""
        [hooks]
        startup = 'exec-and-forget brew services restart sketchybar'
        workspace-changing = 'exec-and-forget sketchybar --trigger workspace_changing'
        workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
        focus-changed = []
        mode-changed = ['exec-and-forget sketchybar --trigger mode_changed', 'retile']
        """).hooks
        #expect(hooks.startup == ["exec-and-forget brew services restart sketchybar"])
        #expect(hooks.workspaceChanging == ["exec-and-forget sketchybar --trigger workspace_changing"])
        #expect(hooks.workspaceChanged == ["exec-and-forget sketchybar --trigger workspace_change"])
        #expect(hooks.focusChanged == [])
        #expect(hooks.modeChanged == ["exec-and-forget sketchybar --trigger mode_changed", "retile"])
        assertError("[hooks]\nmode-changed = [1]\n", path: "hooks.mode-changed", line: 2, contains: "command string")
        assertError("[hooks]\nstartup = ['']\n", path: "hooks.startup", line: 2, contains: "can't be empty")
        assertError("[hooks]\non-startup = 'x'\n", path: "hooks.on-startup", line: 2, contains: "unknown key")
        assertError("after-startup-command = ['x']\n", path: "after-startup-command", line: 1, contains: "unknown key")
    }

    @Test func `Focus follows mouse`() throws {
        let defaults = Config.default.focusFollowsMouse
        #expect(defaults == FocusFollowsMouse())
        #expect(!defaults.enabled)
        #expect(defaults.delayMs == 100)
        #expect(defaults.accordionEdges)
        let ffm = try Config.parse("""
        [focus-follows-mouse]
        enabled = true
        delay-ms = 0
        accordion-edges = false
        """).focusFollowsMouse
        #expect(ffm.enabled)
        #expect(ffm.delayMs == 0)
        #expect(!ffm.accordionEdges)
        assertError("[focus-follows-mouse]\ndelay-ms = -1\n", path: "focus-follows-mouse.delay-ms", line: 2, contains: "0 or more")
        assertError("[focus-follows-mouse]\naccordion = true\n", path: "focus-follows-mouse.accordion", line: 2, contains: "unknown key")
    }

    @Test func `Animations and drag`() throws {
        #expect(Config.default.animations == Animations())
        #expect(Config.default.drag == Drag())
        let config = try Config.parse("""
        [animations]
        enabled = false
        duration-ms = 300
        curve = 'ease-out-cubic'
        [drag]
        placeholders = false
        """)
        #expect(!config.animations.enabled)
        #expect(config.animations.durationMs == 300)
        #expect(config.animations.curve == .easeOutCubic)
        #expect(Animations().curve == .spring)
        assertError("[animations]\ncurve = 'bounce'\n", path: "animations.curve", line: 2, contains: "'ease-out-cubic'")
        #expect(!config.drag.placeholders)
        assertError("[animations]\nduration-ms = -1\n", path: "animations.duration-ms", line: 2, contains: "0 to 1000")
        assertError("[drag]\nghost = true\n", path: "drag.ghost", line: 2, contains: "unknown key")
    }

    @Test func `HUD`() throws {
        #expect(Config.default.hud == Hud())
        let defaults = Hud()
        #expect(defaults.enabled)
        #expect(defaults.position == .bottom)
        #expect(defaults.durationMs == 1200)
        #expect(defaults.offset == 16)
        #expect(defaults.onLayoutChange && defaults.onModeChange && defaults.onWorkspaceChange)
        #expect(try !Config.parse("[hud]\non-workspace-change = false\n").hud.onWorkspaceChange)
        let hud = try Config.parse("[hud]\nposition = 'top'\nduration-ms = 3000\noffset = 4.5\non-mode-change = false\n").hud
        #expect(hud.position == .top)
        #expect(hud.durationMs == 3000)
        #expect(hud.offset == 4.5)
        #expect(hud.onLayoutChange)
        #expect(!hud.onModeChange)
        assertError("[hud]\nposition = 'middle'\n", path: "hud.position", line: 2, contains: "'bottom'")
        assertError("[hud]\nduration-ms = 50\n", path: "hud.duration-ms", line: 2, contains: "100 to 10000")
        assertError("[hud]\noffset = -1\n", path: "hud.offset", line: 2, contains: "0 to 200")
        assertError("[hud]\nseconds = 2\n", path: "hud.seconds", line: 2, contains: "unknown key")
    }

    @Test func `Drag preview style`() throws {
        let defaults = Config.default.drag
        #expect(defaults.previewBorderColor == nil)
        #expect(defaults.previewFillColor == nil)
        #expect(defaults.previewBorderWidth == 3)
        #expect(defaults.homeOutline)
        #expect(try !Config.parse("[drag]\nhome-outline = false\n").drag.homeOutline)
        assertError("[drag]\nhome-outline = 'no'\n", path: "drag.home-outline", line: 2, contains: "true or false")
        let drag = try Config.parse("[drag]\npreview-border-color = '#ff0000'\npreview-fill-color = '#00ff0080'\npreview-border-width = 1.5\n").drag
        #expect(drag.previewBorderColor == Color(red: 1, green: 0, blue: 0))
        #expect(drag.previewFillColor == Color(red: 0, green: 1, blue: 0, alpha: 128 / 255))
        #expect(drag.previewBorderWidth == 1.5)
        assertError("[drag]\npreview-border-color = 'blue'\n", path: "drag.preview-border-color", line: 2, contains: "'blue' is not a colour")
        assertError("[drag]\npreview-border-width = 21\n", path: "drag.preview-border-width", line: 2, contains: "0 to 20")
        assertError("[drag]\npreview-border-width = -1\n", path: "drag.preview-border-width", line: 2, contains: "0 to 20")
    }

    @Test func `Modifier sides`() throws {
        #expect(Config.default.modifiers == ModifierSides())
        let config = try Config.parse("[modifiers]\nalt = 'left'\nshift = 'right'\n")
        #expect(config.modifiers.alt == .left)
        #expect(config.modifiers.ctrl == .both)
        #expect(config.modifiers.shift == .right)
        assertError("[modifiers]\nalt = 'up'\n", path: "modifiers.alt", line: 2, contains: "'both', 'left', 'right'")
        assertError("[modifiers]\nfn = 'left'\n", path: "modifiers.fn", line: 2, contains: "unknown key")
    }

    @Test func `Load from missing file fails`() {
        let error = #expect(throws: ConfigError.self) {
            try Config.load(from: URL(fileURLWithPath: "/nonexistent/dinky.toml"))
        }
        if let error { #expect("\(error)".contains("/nonexistent/dinky.toml")) }
    }
}
