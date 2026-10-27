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
        #expect(config.borders.activeColor == .color(Color(red: 0xE1 / 255, green: 0xE3 / 255, blue: 0xE4 / 255)))
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
        hide-menu-bar-icon = 'single-display'
        scripting-addition = false
        """)
        #expect(!config.startAtLogin)
        #expect(config.workspaces == 3)
        #expect(config.defaultLayout == .accordion)
        #expect(!config.followAppActivation)
        #expect(!config.floatWindowsWithoutFullscreen)
        #expect(config.menuBarIcon == .text)
        #expect(config.hideMenuBarIcon == .singleDisplay)
        #expect(!config.scriptingAddition)
        #expect(Config.default.hideMenuBarIcon == .never && Config.default.scriptingAddition)
        assertError("hide-menu-bar-icon = 'auto'\n", path: "hide-menu-bar-icon", line: 1, contains: "'never', 'always', 'single-display'")
        #expect(try Config.parse("menu-bar-icon = 'none'\n").menuBarIcon == MenuBarIcon.none)
        assertError("menu-bar-icon = 'icon'\n", path: "menu-bar-icon", line: 1, contains: "'blocks', 'text', 'none'")
        assertError("workspaces = 0\n", path: "workspaces", line: 1, contains: "at least 1")
        assertError("default-layout = 'stack'\n", path: "default-layout", line: 1, contains: "'tiles', 'dwindle', 'accordion', 'fixed', 'scrolling', 'free'")
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
        layout = 'free'
        """)
        #expect(!config.settings(forWorkspace: 1).tiling)
        #expect(!config.settings(forWorkspace: 1).isFree)
        #expect(config.settings(forWorkspace: 4).isFree)
        #expect(try Config.parse("default-layout = 'free'\n").settings(forWorkspace: 2).isFree)
        assertError("[workspace.2]\nfloat = true\n", path: "workspace.2.float", line: 2, contains: "layout = 'free'")
        assertError("[workspace.2]\nlayout = 'free'\ncolumns = 2\n", path: "workspace.2.columns", line: 3, contains: "only valid")
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
        #expect(Config().fullscreen.scrolling == .push)
        #expect(try Config.parse("[fullscreen]\nscrolling = 'over'\n").fullscreen.scrolling == .over)
        assertError("[fullscreen]\nscrolling = 'cover'\n", path: "fullscreen.scrolling", line: 2, contains: "'push', 'over'")
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
        #expect(Config().scrolling.centerFocusedColumn == .never)
        #expect(try Config.parse("[scrolling]\ncenter-focused-column = 'always'\n").scrolling.centerFocusedColumn == .always)
        #expect(try Config.parse("[scrolling]\ncenter-focused-column = 'always-fill'\n").scrolling.centerFocusedColumn == .alwaysFill)
        #expect(try Config.parse("[scrolling]\ncenter-focused-column = 'on-overflow'\n").scrolling.centerFocusedColumn == .onOverflow)
        assertError("[scrolling]\ncenter-focused-column = 'yes'\n", path: "scrolling.center-focused-column", line: 2,
                    contains: "'never', 'always', 'always-fill', 'on-overflow'")
        // `glide` is gone: an old config that sets it, to anything, still loads.
        #expect(!Config().scrolling.retiredGlide)
        #expect(try Config.parse("[scrolling]\nglide = 'snapshots'\n").scrolling.retiredGlide)
        #expect(try Config.parse("[scrolling]\nglide = 'fast'\n").scrolling.retiredGlide)
    }

    @Test func `Window switcher`() throws {
        let defaults = Config().windowSwitcher
        #expect(defaults.enabled)
        #expect(defaults.modifier == .none)
        #expect(defaults.delayMs == 200)
        #expect(defaults.layouts == [.scrolling, .tiles])
        #expect(defaults.cornerRadius == 52)
        #expect(defaults.tilesStyle == .map)
        #expect(defaults.showSingle)
        #expect(defaults.showTitles)
        #expect(defaults.position == .auto)
        let switcher = try Config.parse("""
            [window-switcher]
            enabled = false
            modifier = 'alt'
            delay-ms = 0
            layouts = ['tiles', 'fixed']
            corner-radius = 12
            tiles-style = 'row'
            show-single = false
            show-titles = false
            position = 'bottom'
            """).windowSwitcher
        #expect(!switcher.enabled)
        #expect(switcher.modifier == .alt)
        #expect(switcher.delayMs == 0)
        #expect(switcher.layouts == [.tiles, .fixed])
        #expect(switcher.cornerRadius == 12)
        #expect(switcher.tilesStyle == .row)
        #expect(!switcher.showSingle)
        #expect(!switcher.showTitles)
        #expect(switcher.position == .bottom)
        assertError("[window-switcher]\nposition = 'left'\n", path: "window-switcher.position", line: 2, contains: "'auto', 'center', 'top', 'bottom', 'mouse'")
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
        #expect(defaults.enabled)
        #expect(defaults.delayMs == 200)
        #expect(defaults.cornerRadius == 52)
        #expect(defaults.position == .auto)
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
            position = 'center'
            """).workspaceSwitcher
        #expect(switcher.modifier == .ctrl)
        #expect(switcher.delayMs == 300)
        #expect(switcher.displays == .pointer)
        #expect(!switcher.showEmpty)
        #expect(switcher.exclude == [3, 5])
        #expect(switcher.cardHeight == 100)
        #expect(switcher.thumbnails == .icons)
        #expect(switcher.cornerRadius == 18)
        #expect(switcher.position == .center)
        assertError("[window-switcher]\nmodifier = 'alt'\n[workspace-switcher]\nmodifier = 'alt'\n",
                    path: "workspace-switcher.modifier", line: 4, contains: "[window-switcher]")
        assertError("[switcher]\ntrigger = 'double-tap'\n[window-switcher]\nmodifier = 'hyper'\n[workspace-switcher]\nmodifier = 'hyper'\n",
                    path: "workspace-switcher.modifier", line: 6, contains: "another modifier or trigger")
        // One modifier, held for one and double-tapped for the other.
        let shared = try Config.parse("[window-switcher]\nmodifier = 'hyper'\n[workspace-switcher]\nmodifier = 'hyper'\ntrigger = 'double-tap'\n")
        #expect(shared.windowSwitcher.trigger == .hold)
        #expect(shared.workspaceSwitcher.modifier == .hyper)
        #expect(try Config.parse("[workspace-switcher]\nthumbnails = 'schematic'\n").workspaceSwitcher.thumbnails == .schematic)
        assertError("[workspace-switcher]\ndisplays = 'main'\n", path: "workspace-switcher.displays", line: 2, contains: "'all', 'pointer'")
        assertError("[workspace-switcher]\nexclude = ['3']\n", path: "workspace-switcher.exclude", line: 2, contains: "integers")
        assertError("[workspace-switcher]\nexclude = [0]\n", path: "workspace-switcher.exclude", line: 2, contains: "start at 1")
        assertError("[workspace-switcher]\ncard-height = 20\n", path: "workspace-switcher.card-height", line: 2, contains: "60 to 200")
        assertError("[workspace-switcher]\ncorner-radius = 81\n", path: "workspace-switcher.corner-radius", line: 2, contains: "0 to 80")
    }

    @Test func `Highlight colour, each table's own first`() throws {
        let purple = try Color(hex: "#59168b")
        let defaults = Config()
        #expect(defaults.highlightColor == nil)
        #expect(defaults.switcher.highlightColor == nil)
        #expect(defaults.windowSwitcher.highlightColor == .accent)
        #expect(defaults.workspaceSwitcher.highlightColor == .accent)
        #expect(defaults.borders.activeColor == .color(try Color(hex: "#e1e3e4")))
        // Set at the top, everything left unset takes it.
        let global = try Config.parse("highlight-color = '#59168b'\n")
        #expect(global.highlightColor == .color(purple))
        #expect(global.windowSwitcher.highlightColor == .color(purple))
        #expect(global.workspaceSwitcher.highlightColor == .color(purple))
        #expect(global.borders.activeColor == .color(purple))
        #expect(global.drag.previewBorderColor == .color(purple))
        #expect(global.borders.noopFlashColor == .color(purple))
        #expect(defaults.drag.previewBorderColor == nil)
        #expect(defaults.borders.noopFlashColor == .color(try Color(hex: "#d97757")))
        // A switcher's own over [switcher]'s over the top-level one; 'accent' stops the chain.
        let layered = try Config.parse("""
            highlight-color = '#59168b'

            [switcher]
            highlight-color = '#ff000080'

            [workspace-switcher]
            highlight-color = 'accent'

            [borders]
            active-color = '#00ff00'
            """)
        #expect(layered.windowSwitcher.highlightColor == .color(try Color(hex: "#ff000080")))
        #expect(layered.workspaceSwitcher.highlightColor == .accent)
        #expect(layered.borders.activeColor == .color(try Color(hex: "#00ff00")))
        #expect(try Config.parse("highlight-color = '#59168b'\n[borders]\nnoop-flash-color = 'accent'\n").borders.noopFlashColor == .accent)
        #expect(try Config.parse("highlight-color = '#59168b'\n[drag]\npreview-border-color = 'accent'\n").drag.previewBorderColor == .accent)
        #expect(try Config.parse("[borders]\nactive-color = 'accent'\n").borders.activeColor == .accent)
        #expect(try Config.parse("highlight-color = 'accent'\n").borders.activeColor == .accent)
        assertError("highlight-color = 'purple'\n", path: "highlight-color", line: 1, contains: "'#rrggbb', '#rrggbbaa' or 'accent'")
        assertError("[switcher]\nhighlight-color = '#123'\n", path: "switcher.highlight-color", line: 2, contains: "'accent'")
        assertError("[window-switcher]\nhighlight-color = 3\n", path: "window-switcher.highlight-color", line: 2, contains: "a string")
    }

    @Test func `Switcher keys both switchers share`() throws {
        #expect(Config().switcher == SwitcherDefaults())
        let shared = try Config.parse("""
            [switcher]
            enabled = false
            delay-ms = 50
            corner-radius = 18
            position = 'center'
            """)
        #expect(!shared.windowSwitcher.enabled && !shared.workspaceSwitcher.enabled)
        #expect(shared.windowSwitcher.delayMs == 50 && shared.workspaceSwitcher.delayMs == 50)
        #expect(shared.windowSwitcher.cornerRadius == 18 && shared.workspaceSwitcher.cornerRadius == 18)
        #expect(shared.windowSwitcher.position == .center && shared.workspaceSwitcher.position == .center)
        #expect(Config().workspaceSwitcher.showTitles)
        #expect(Config().windowSwitcher.letterKeys && Config().workspaceSwitcher.letterKeys)
        #expect(Config().windowSwitcher.letters == Array("asdfgqwertyuiopzxcvbnm"))
        let letters = try Config.parse("""
            [switcher]
            letter-keys = false
            letters = 'qwe'
            [window-switcher]
            letter-keys = true
            """)
        #expect(letters.windowSwitcher.letterKeys && !letters.workspaceSwitcher.letterKeys)
        #expect(letters.windowSwitcher.letters == ["q", "w", "e"] && letters.workspaceSwitcher.letters == ["q", "w", "e"])
        assertError("[switcher]\nletters = 'asdh'\n", path: "switcher.letters", line: 2, contains: "leave out h, j, k and l")
        assertError("[window-switcher]\nletters = 'asa'\n", path: "window-switcher.letters", line: 2, contains: "twice")
        assertError("[workspace-switcher]\nletters = 'aB'\n", path: "workspace-switcher.letters", line: 2, contains: "lowercase")
        assertError("[switcher]\nletters = ''\n", path: "switcher.letters", line: 2, contains: "at least")
        let titles = try Config.parse("[switcher]\nshow-titles = false\n[workspace-switcher]\nshow-titles = true\n")
        #expect(!titles.windowSwitcher.showTitles && titles.workspaceSwitcher.showTitles)
        // A switcher's own key wins over [switcher]'s, whichever comes first in the file.
        let own = try Config.parse("""
            [workspace-switcher]
            enabled = true
            position = 'mouse'

            [switcher]
            enabled = false
            delay-ms = 50
            position = 'top'

            [window-switcher]
            delay-ms = 300
            """)
        #expect(!own.windowSwitcher.enabled)
        #expect(own.windowSwitcher.delayMs == 300)
        #expect(own.windowSwitcher.position == .top)
        #expect(own.workspaceSwitcher.enabled)
        #expect(own.workspaceSwitcher.delayMs == 50)
        #expect(own.workspaceSwitcher.position == .mouse)
        assertError("[switcher]\ndelay-ms = 5000\n", path: "switcher.delay-ms", line: 2, contains: "0 to 2000")
        assertError("[switcher]\ncorner-radius = 90\n", path: "switcher.corner-radius", line: 2, contains: "0 to 80")
        assertError("[switcher]\nposition = 'left'\n", path: "switcher.position", line: 2, contains: "'auto'")
        // Each switcher needs a modifier of its own.
        assertError("[switcher]\nmodifier = 'alt'\n", path: "switcher.modifier", line: 2, contains: "unknown key")
    }

    @Test func `Switcher double tap`() throws {
        #expect(Config().windowSwitcher.trigger == .hold && Config().workspaceSwitcher.trigger == .hold)
        #expect(Config().switcher.doubleTapMs == 300)
        let config = try Config.parse("""
            [switcher]
            trigger = 'double-tap'
            double-tap-ms = 250

            [workspace-switcher]
            trigger = 'hold'
            """)
        #expect(config.windowSwitcher.trigger == .doubleTap && config.windowSwitcher.doubleTapMs == 250)
        #expect(config.workspaceSwitcher.trigger == .hold && config.workspaceSwitcher.doubleTapMs == 250)
        assertError("[switcher]\ntrigger = 'triple'\n", path: "switcher.trigger", line: 2, contains: "'double-tap'")
        assertError("[window-switcher]\ndouble-tap-ms = 50\n", path: "window-switcher.double-tap-ms", line: 2,
                    contains: "100 to 1000")
    }

    @Test func `Gestures`() throws {
        let defaults = Config().gestures.trackpad
        #expect(defaults.enabled)
        #expect(defaults.fingers == 3)
        #expect(defaults.distance == 15)
        #expect(defaults.step == 12)
        #expect(defaults.swipes.isEmpty)
        let config = try Config.parse("""
            [gestures.trackpad]
            fingers = 4
            distance = 20
            step = 20
            swipe-right = 'window-switcher'
            swipe-left = ['workspace-switcher', 'focus left']
            """)
        #expect(config.gestures.trackpad.fingers == 4)
        #expect(config.gestures.trackpad.distance == 20)
        #expect(config.gestures.trackpad.step == 20)
        #expect(config.gestures.trackpad.swipes == [.swipeRight: ["window-switcher"], .swipeLeft: ["workspace-switcher", "focus left"]])
        #expect(config.binds("workspace-switcher"))
        #expect(!config.binds("layout"))
        let off = try Config.parse("[gestures.trackpad]\nenabled = false\nswipe-right = 'window-switcher'\n")
        #expect(off.gestures.trackpadSwipes.isEmpty)
        #expect(!off.binds("window-switcher"))
        assertError("[gestures.trackpad]\nfingers = 1\n", path: "gestures.trackpad.fingers", line: 2, contains: "2 to 5")
        assertError("[gestures.trackpad]\ndistance = 2\n", path: "gestures.trackpad.distance", line: 2, contains: "6 to 40")
        assertError("[gestures.trackpad]\nstep = 2\n", path: "gestures.trackpad.step", line: 2, contains: "4 to 50")
        assertError("[gestures.trackpad]\no = 'workspace 1'\n", path: "gestures.trackpad.o", line: 2, contains: "'swipe-left'")
        assertError("[gestures.trackpad]\nswipe-up = []\n", path: "gestures.trackpad.swipe-up", line: 2, contains: "can't be empty")
        assertError("[gestures]\nfingers = 3\n", path: "gestures.fingers", line: 2, contains: "[gestures.trackpad]")
        assertError("[gestures]\nswipe-left = 'focus left'\n", path: "gestures.swipe-left", line: 2, contains: "[gestures.trackpad]")
        assertError("[gestures]\no = 1\n", path: "gestures.o", line: 2, contains: "'trackpad'")
    }

    @Test func `Mouse gestures`() throws {
        let defaults = Config().gestures.mouse
        #expect(!defaults.enabled)
        #expect(defaults.fingers == 2)
        #expect(defaults.distance == 8)
        #expect(defaults.step == 4)
        #expect(defaults.swipes == nil)
        let config = try Config.parse("""
            [gestures.trackpad]
            swipe-right = 'window-switcher'
            [gestures.mouse]
            enabled = true
            fingers = 4
            distance = 10
            step = 5
            swipe-up = 'layout tiles'
            """)
        #expect(config.gestures.trackpad.swipes == [.swipeRight: ["window-switcher"]])
        #expect(config.gestures.mouseSwipes == [.swipeUp: ["layout tiles"]])
        #expect(config.gestures.mouse.enabled)
        #expect(config.gestures.mouse.fingers == 4)
        #expect(config.gestures.mouse.distance == 10)
        #expect(config.gestures.mouse.step == 5)
        #expect(config.gestures.mouse.swipes == [.swipeUp: ["layout tiles"]])
        #expect(config.binds("layout"))
        assertError("[gestures.mouse]\nfingers = 5\n", path: "gestures.mouse.fingers", line: 2, contains: "2 to 4")
        assertError("[gestures.mouse]\ndistance = 1\n", path: "gestures.mouse.distance", line: 2, contains: "3 to 30")
        assertError("[gestures.mouse]\nstep = 40\n", path: "gestures.mouse.step", line: 2, contains: "2 to 30")
        assertError("[gestures.mouse]\no = 'workspace 1'\n", path: "gestures.mouse.o", line: 2, contains: "'swipe-left'")
    }

    @Test func `Scroll gesture`() throws {
        let defaults = Config().gestures.scroll
        #expect(!defaults.enabled)
        #expect(defaults.fingers == 4)
        #expect(defaults.speed == 1.5)
        #expect(defaults.showSwitcher)
        #expect(defaults.edgeFlash)
        #expect(defaults.haptic)
        #expect(defaults.hapticStrength == .medium && defaults.hapticStrength.actuation == 4)
        #expect(defaults.switcherMs == 1000)
        let config = try Config.parse("""
            [gestures.trackpad]
            fingers = 4
            swipe-up = 'window-switcher'
            [gestures.scroll]
            enabled = true
            speed = 2
            show-switcher = false
            switcher-ms = 600
            edge-flash = false
            haptic = false
            haptic-strength = 'strong'
            """)
        #expect(config.gestures.scroll.enabled)
        #expect(config.gestures.scroll.fingers == 4)
        #expect(config.gestures.scroll.speed == 2)
        #expect(!config.gestures.scroll.showSwitcher)
        #expect(config.gestures.scroll.switcherMs == 600)
        #expect(!config.gestures.scroll.edgeFlash)
        #expect(!config.gestures.scroll.haptic)
        #expect(config.gestures.scroll.hapticStrength == .strong && config.gestures.scroll.hapticStrength.actuation == 6)
        assertError("[gestures.scroll]\nhaptic-strength = 'loud'\n", path: "gestures.scroll.haptic-strength", line: 2, contains: "'light'")
        assertError("[gestures.scroll]\nfingers = 2\n", path: "gestures.scroll.fingers", line: 2, contains: "3 to 5")
        assertError("[gestures.scroll]\nspeed = 0\n", path: "gestures.scroll.speed", line: 2, contains: "0.25 to 5")
        assertError("[gestures.scroll]\nswitcher-ms = 0\n", path: "gestures.scroll.switcher-ms", line: 2, contains: "100 to 5000")
        assertError("[gestures.scroll]\nnatural = false\n", path: "gestures.scroll.natural", line: 2, contains: "unknown key")
        assertError("[gestures.trackpad]\nfingers = 4\nswipe-left = 'focus left'\n[gestures.scroll]\nenabled = true\n",
                    path: "gestures.scroll.fingers", line: 4, contains: "'swipe-left'")
        #expect(throws: Never.self) {
            try Config.parse("[gestures.trackpad]\nfingers = 4\nswipe-left = 'focus left'\n[gestures.scroll]\nfingers = 4\n")
        }
        #expect(throws: Never.self) {
            try Config.parse("[gestures.trackpad]\nswipe-left = 'focus left'\n[gestures.scroll]\nenabled = true\n")
        }
    }

    @Test func `Mouse scroll`() throws {
        let defaults = Config().gestures.mouseScroll
        #expect(!defaults.enabled)
        #expect(defaults.modifier == [.ctrl, .alt])
        #expect(defaults.drag && defaults.wheel && defaults.cursor)
        #expect(defaults.speed == 1)
        #expect(defaults.showSwitcher && defaults.switcherMs == 1000 && defaults.edgeFlash)
        let inherits = try Config.parse("""
            [gestures.scroll]
            show-switcher = false
            switcher-ms = 600
            edge-flash = false
            [gestures.mouse-scroll]
            enabled = true
            modifier = 'cmd-alt'
            drag = false
            cursor = false
            speed = 2
            """).gestures.mouseScroll
        #expect(inherits.enabled && !inherits.drag && inherits.wheel && !inherits.cursor, "cursor without drag, no error")
        #expect(inherits.modifier == [.cmd, .alt])
        #expect(inherits.speed == 2)
        #expect(!inherits.showSwitcher && inherits.switcherMs == 600 && !inherits.edgeFlash, "unset, the fingers' own")
        let own = try Config.parse("""
            [gestures.scroll]
            show-switcher = false
            [gestures.mouse-scroll]
            show-switcher = true
            switcher-ms = 300
            edge-flash = false
            """).gestures.mouseScroll
        #expect(own.showSwitcher && own.switcherMs == 300 && !own.edgeFlash)
        assertError("[gestures.mouse-scroll]\nmodifier = 'none'\n", path: "gestures.mouse-scroll.modifier", line: 2, contains: "is not modifiers")
        assertError("[gestures.mouse-scroll]\nmodifier = 'ctrl-h'\n", path: "gestures.mouse-scroll.modifier", line: 2, contains: "is not modifiers")
        assertError("[gestures.mouse-scroll]\nspeed = 9\n", path: "gestures.mouse-scroll.speed", line: 2, contains: "0.25 to 5")
        assertError("[gestures.mouse-scroll]\nswitcher-ms = 50\n", path: "gestures.mouse-scroll.switcher-ms", line: 2, contains: "100 to 5000")
        assertError("[gestures.mouse-scroll]\nhaptic = true\n", path: "gestures.mouse-scroll.haptic", line: 2, contains: "unknown key")
    }

    @Test func `Either scroll can glance at a strip`() throws {
        #expect(!Config().gestures.stripGlances, "both off")
        #expect(try Config.parse("[gestures.scroll]\nenabled = true\n").gestures.stripGlances)
        #expect(try Config.parse("[gestures.mouse-scroll]\nenabled = true\n").gestures.stripGlances)
        #expect(try !Config.parse("[gestures.mouse-scroll]\nenabled = true\nshow-switcher = false\n").gestures.stripGlances)
        #expect(try !Config.parse("[gestures.mouse-scroll]\nenabled = true\ndrag = false\nwheel = false\n").gestures.stripGlances)
        #expect(try !Config.parse("[gestures.scroll]\nshow-switcher = false\n[gestures.mouse-scroll]\nenabled = true\n").gestures.stripGlances,
                "the mouse's show-switcher is the fingers' unless set")
    }

    @Test func `Mouse scroll's modifier is its own`() throws {
        assertError("[drag]\nmouse-modifier = 'ctrl-alt'\n[gestures.mouse-scroll]\nenabled = true\n",
                    path: "gestures.mouse-scroll.modifier", contains: "[drag] mouse-modifier already uses 'alt-ctrl'")
        assertError("[window-switcher]\nmodifier = 'cmd'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'cmd'\n",
                    path: "gestures.mouse-scroll.modifier", contains: "[window-switcher] already uses 'cmd'")
        // A switcher that double-taps it can share it: held to scroll, it is no tap.
        #expect(throws: Never.self) {
            try Config.parse("[window-switcher]\nmodifier = 'alt'\ntrigger = 'double-tap'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'alt'\n")
        }
        #expect(throws: Never.self) {
            try Config.parse("[workspace-switcher]\nmodifier = 'cmd'\ntrigger = 'double-tap'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'cmd'\n")
        }
        #expect(throws: Never.self) {
            try Config.parse("[switcher]\ntrigger = 'double-tap'\n[workspace-switcher]\nmodifier = 'hyper'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'alt-ctrl-cmd-shift'\n")
        }
        assertError("[window-switcher]\nmodifier = 'alt'\ntrigger = 'hold'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'alt'\n",
                    path: "gestures.mouse-scroll.modifier", contains: "[window-switcher] already uses 'alt'")
        assertError("[workspace-switcher]\nmodifier = 'ctrl'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'ctrl'\n",
                    path: "gestures.mouse-scroll.modifier", contains: "[workspace-switcher] already uses 'ctrl'")
        assertError("[workspace-switcher]\nmodifier = 'hyper'\n[gestures.mouse-scroll]\nenabled = true\nmodifier = 'alt-ctrl-cmd-shift'\n",
                    path: "gestures.mouse-scroll.modifier", contains: "[workspace-switcher] already uses 'hyper'")
        // Off, or with no drag to share a press with, nothing to clash.
        #expect(throws: Never.self) { try Config.parse("[drag]\nmouse-modifier = 'ctrl-alt'\n[gestures.mouse-scroll]\nmodifier = 'ctrl-alt'\n") }
        #expect(throws: Never.self) {
            try Config.parse("[drag]\nmouse-modifier = 'ctrl-alt'\n[gestures.mouse-scroll]\nenabled = true\ndrag = false\n")
        }
        #expect(throws: Never.self) { try Config.parse("[window-switcher]\nmodifier = 'alt'\n[gestures.mouse-scroll]\nenabled = true\n") }
    }

    @Test func `Strip scrolls clash with macOS's own swipes across`() {
        #expect(ScrollGesture.clashes(fingers: 4, three: 0, four: 0, drag: false) == [])
        #expect(ScrollGesture.clashes(fingers: 4, three: 0, four: 2, drag: false) == ["switch Spaces"])
        #expect(ScrollGesture.clashes(fingers: 4, three: 2, four: 0, drag: false) == ["switch Spaces"],
                "three fingers between Spaces takes four too")
        #expect(ScrollGesture.clashes(fingers: 4, three: 1, four: 0, drag: true) == [])
        #expect(ScrollGesture.clashes(fingers: 3, three: 1, four: 2, drag: false) == ["swipe between pages"])
        #expect(ScrollGesture.clashes(fingers: 3, three: 2, four: 0, drag: true) == ["switch Spaces", "drag"])
        #expect(ScrollGesture.clashes(fingers: 5, three: 2, four: 2, drag: true) == [])
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

    @Test func `Noop flash`() throws {
        let defaults = Borders()
        #expect(defaults.noopFlash)
        #expect(defaults.noopFlashColor == .color(try Color(hex: "#d97757")))
        #expect(defaults.noopFlashWidth == 2)
        #expect(defaults.noopFlashSpread == 100)
        #expect(defaults.noopFlashOpacity == 0.6)
        let borders = try Config.parse("""
        [borders]
        noop-flash = false
        noop-flash-color = 'accent'
        noop-flash-width = 0
        noop-flash-spread = 8
        noop-flash-opacity = 0
        """).borders
        #expect(!borders.noopFlash)
        #expect(borders.noopFlashColor == .accent)
        #expect(borders.noopFlashWidth == 0)
        #expect(borders.noopFlashSpread == 8)
        #expect(borders.noopFlashOpacity == 0)
        #expect(try Config.parse("[hud]\non-noop = true\n").hud.onNoop)

        assertError("[borders]\nnoop-flash-width = -1\n", path: "borders.noop-flash-width", line: 2, contains: "0 to 8")
        assertError("[borders]\nnoop-flash-width = 8.5\n", path: "borders.noop-flash-width", line: 2, contains: "0 to 8")
        assertError("[borders]\nnoop-flash-spread = 7\n", path: "borders.noop-flash-spread", line: 2, contains: "8 to 160")
        assertError("[borders]\nnoop-flash-spread = 160.5\n", path: "borders.noop-flash-spread", line: 2, contains: "8 to 160")
        assertError("[borders]\nnoop-flash-opacity = -0.1\n", path: "borders.noop-flash-opacity", line: 2, contains: "0 to 1")
        assertError("[borders]\nnoop-flash-opacity = 1.5\n", path: "borders.noop-flash-opacity", line: 2, contains: "0 to 1")
        assertError("[borders]\nnoop-flash-color = 'pink'\n", path: "borders.noop-flash-color", line: 2, contains: "'pink' is not a colour")
        // Gone with the glow that held at full between breaths, and with the one that breathed more than once.
        assertError("[borders]\nnoop-flash-ms = 80\n", path: "borders.noop-flash-ms", line: 2, contains: "unknown key")
        assertError("[borders]\nnoop-flash-count = 2\n", path: "borders.noop-flash-count", line: 2, contains: "unknown key")
    }

    @Test func `Pinned windows' ring`() throws {
        let defaults = Borders()
        #expect(defaults.pinned)
        #expect(defaults.pinnedColor == .color(try Color(hex: "#d97757")))
        #expect(defaults.pinnedWidth == 2)
        let borders = try Config.parse("""
        [borders]
        enabled = false
        pinned = false
        pinned-color = 'accent'
        pinned-width = 0
        """).borders
        #expect(!borders.pinned)
        #expect(borders.pinnedColor == .accent)
        #expect(borders.pinnedWidth == 0)
        let highlighted = try Config.parse("highlight-color = '#00ff00'\n").borders
        #expect(highlighted.pinnedColor == .color(try Color(hex: "#00ff00")), "takes the top-level highlight-color")
        assertError("[borders]\npinned-width = -1\n", path: "borders.pinned-width", line: 2, contains: "0 to 8")
        assertError("[borders]\npinned-width = 8.5\n", path: "borders.pinned-width", line: 2, contains: "0 to 8")
        assertError("[borders]\npinned-color = 'pink'\n", path: "borders.pinned-color", line: 2, contains: "'pink' is not a colour")
    }

    @Test func `Haptics: one global setting, each table's own winning`() throws {
        let defaults = try Config.parse("")
        #expect(defaults.haptic && defaults.hapticStrength == .medium)
        for (on, strength) in [(defaults.gestures.scroll.haptic, defaults.gestures.scroll.hapticStrength),
                               (defaults.gestures.trackpad.haptic, defaults.gestures.trackpad.hapticStrength),
                               (defaults.windowSwitcher.haptic, defaults.windowSwitcher.hapticStrength),
                               (defaults.workspaceSwitcher.haptic, defaults.workspaceSwitcher.hapticStrength)] {
            #expect(on && strength == .medium, "medium everywhere with nothing set")
        }
        let global = try Config.parse("""
            haptic-strength = 'strong'
            [gestures.trackpad]
            haptic = false
            [switcher]
            haptic-strength = 'light'
            [workspace-switcher]
            haptic-strength = 'medium'
            """)
        #expect(global.gestures.scroll.haptic && global.gestures.scroll.hapticStrength == .strong, "inherits")
        #expect(!global.gestures.trackpad.haptic && global.gestures.trackpad.hapticStrength == .strong)
        #expect(global.windowSwitcher.hapticStrength == .light, "[switcher]'s own")
        #expect(global.workspaceSwitcher.hapticStrength == .medium, "its own table's, over [switcher]'s")
        let off = try Config.parse("haptic = false\n[gestures.scroll]\nhaptic = true\n")
        #expect(off.gestures.scroll.haptic && !off.gestures.trackpad.haptic && !off.windowSwitcher.haptic)
        let strong = try Config.parse("haptic-strength = 'strong'\n")
        #expect(strong.windowSwitcher.hapticStrength == .strong && strong.workspaceSwitcher.hapticStrength == .strong)
        let mixed = try Config.parse("haptic = false\n[switcher]\nhaptic = true\n[workspace-switcher]\nhaptic = false\n")
        #expect(mixed.windowSwitcher.haptic && !mixed.workspaceSwitcher.haptic)
        #expect(!mixed.gestures.trackpad.haptic && !mixed.gestures.scroll.haptic)
        let trackpad = try Config.parse("haptic-strength = 'strong'\n[gestures.trackpad]\nhaptic-strength = 'light'\n")
        #expect(trackpad.gestures.trackpad.hapticStrength == .light && trackpad.gestures.scroll.hapticStrength == .strong)
        let quiet = try Config.parse("haptic = false\n[gestures.scroll]\nhaptic-strength = 'strong'\n")
        #expect(!quiet.gestures.scroll.haptic && quiet.gestures.scroll.hapticStrength == .strong)
        assertError("haptic-strength = 'loud'\n", path: "haptic-strength", line: 1, contains: "'light'")
        assertError("haptic = 1\n", path: "haptic", line: 1, contains: "true or false")
        assertError("[gestures.trackpad]\nhaptic-strength = 'max'\n", path: "gestures.trackpad.haptic-strength", line: 2, contains: "'medium'")
        assertError("[switcher]\nhaptic-strength = 'max'\n", path: "switcher.haptic-strength", line: 2, contains: "'strong'")
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
        assertError("[mode.main]\nalt-super-a = 'x'\n", path: "mode.main.alt-super-a", line: 2, contains: "'alt-super-a'")
        assertError("[mode.main]\nalt-shift-a = 'x'\nshift-alt-a = 'y'\n", path: "mode.main.shift-alt-a", line: 3, contains: "bound twice")
        assertError("[mode.main]\nhyper-a = 'x'\nctrl-alt-cmd-shift-a = 'y'\n", path: "mode.main.ctrl-alt-cmd-shift-a", line: 3, contains: "bound twice")
        assertError("[mode.main.binding]\nalt-a = 'x'\n", path: "mode.main.binding", line: 1, contains: "'binding' is not a layout")
        assertError("[mode.main.floating]\nalt-a = 'x'\n", path: "mode.main.floating", line: 1, contains: "'free'")
        assertError("[mode.main.free.tiles]\nalt-a = 'x'\n", path: "mode.main.free.tiles", line: 1, contains: "can't hold tables")
        // Either table can come first.
        let twice = #expect(throws: ConfigError.self) { try Config.parse("[mode.main.tiles]\nalt-a = 'x'\n[mode.main.dwindle]\nalt-b = 'y'\n") }
        #expect(twice?.description.contains("same layout") == true)
    }

    @Test func `Bindings by layout`() throws {
        let main = try Config.parse("""
        [mode.main]
        alt-a = 'workspace 1'
        alt-b = 'workspace 2'
        [mode.main.free]
        alt-a = 'grid 1:2:0:0:1:1'
        alt-c = 'fullscreen'
        [mode.main.dwindle]
        alt-b = 'balance-sizes'
        """).modes["main"]!
        let a = KeyCombo(modifiers: .alt, key: "a"), b = KeyCombo(modifiers: .alt, key: "b"), c = KeyCombo(modifiers: .alt, key: "c")
        #expect(main.bindings[a] == ["workspace 1"] && main.bindings[c] == nil, "a layout's table leaves the mode's own alone")
        #expect(main.commands(for: a, on: .free) == ["grid 1:2:0:0:1:1"])
        #expect(main.commands(for: b, on: .free) == ["workspace 2"], "keys a layout leaves out fall through to the mode")
        #expect(main.commands(for: c, on: .free) == ["fullscreen"])
        #expect(main.commands(for: c, on: .scrolling) == nil)
        #expect(main.commands(for: a, on: nil) == ["workspace 1"])
        #expect(main.commands(for: b, on: .tiles) == ["balance-sizes"], "dwindle and tiles are one layout")
        #expect(main.commands(for: b, on: .dwindle) == ["balance-sizes"])
        #expect(main.commands(for: a, on: .floating) == ["grid 1:2:0:0:1:1"], "floating is the old name for free")
        #expect(main.allCommands.count == 5)
        #expect(main.bindings(on: .free) == [a: ["grid 1:2:0:0:1:1"], b: ["workspace 2"], c: ["fullscreen"]])
        #expect(main.bindings(on: .scrolling) == main.bindings)
    }

    @Test func `Rules on the window's workspace`() throws {
        let rules = try Config.parse("""
        [[rules]]
        workspace-layout = 'scrolling'
        run = 'cycle-size 70%'

        [[rules]]
        workspace-layout = ['dwindle', 'fixed']
        workspace = [1, 4]
        run = 'cycle-size 60%'

        [[rules]]
        workspace = 3
        run = 'layout floating'
        """).rules
        #expect(rules[0].workspaceLayouts == [.scrolling] && rules[0].workspaces == nil && rules[0].asksWorkspace)
        #expect(rules[0].matches(layout: .scrolling, workspace: 2))
        #expect(!rules[0].matches(layout: .tiles, workspace: 2))
        // dwindle and tiles are one layout; both conditions must hold.
        #expect(rules[1].matches(layout: .tiles, workspace: 1))
        #expect(rules[1].matches(layout: .fixed, workspace: 4))
        #expect(!rules[1].matches(layout: .tiles, workspace: 2))
        #expect(!rules[1].matches(layout: .scrolling, workspace: 1))
        #expect(!rules[1].matches(layout: .tiles, workspace: nil), "an unnumbered workspace is none of the numbers")
        #expect(rules[2].workspaces == [3] && rules[2].workspaceLayouts == nil)
        #expect(rules[2].matches(layout: .free, workspace: 3))
        #expect(!rules[0].matches(layout: .free, workspace: 2))
        var old = WindowRule()
        old.workspaceLayouts = [.floating]
        #expect(old.matches(layout: .free, workspace: nil), "floating is the old name for free")
        assertError("[[rules]]\nworkspace-layout = 'grid'\nrun = 'x'\n", path: "rules[0].workspace-layout", line: 2, contains: "'scrolling', 'tiles'")
        assertError("[[rules]]\nworkspace-layout = []\nrun = 'x'\n", path: "rules[0].workspace-layout", line: 2, contains: "empty")
        assertError("[[rules]]\nworkspace = 0\nrun = 'x'\n", path: "rules[0].workspace", line: 2, contains: "from 1")
        assertError("[[rules]]\nworkspace = 'two'\nrun = 'x'\n", path: "rules[0].workspace", line: 2, contains: "integer")
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

        [[rules]]
        disk-image = true
        run = 'layout floating'
        """)
        var expected = WindowRule()
        expected.appId = "com.apple.finder"
        expected.appName = "find"
        expected.title = "^Copy"
        expected.kind = .dialog
        expected.run = ["layout floating", "move-window-to-workspace 2"]
        var second = WindowRule()
        second.run = ["layout tiling"]
        var third = WindowRule()
        third.diskImage = true
        third.run = ["layout floating"]
        #expect(config.rules == [expected, second, third])

        #expect(expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .dialog))
        #expect(!expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Copy 3 items", kind: .normal))
        #expect(!expected.matches(appId: "com.apple.finder", appName: "Finder", title: "Desktop", kind: .dialog))
        #expect(!expected.matches(appId: "com.apple.Safari", appName: "Finder", title: "Copy", kind: .dialog))
        #expect(second.matches(appId: nil, appName: nil, title: "", kind: .normal), "a rule with no conditions matches everything")
        #expect(!second.asksWorkspace)
        #expect(second.matches(layout: .floating, workspace: nil))

        #expect(third.matches(appId: "com.apple.finder", appName: "Finder", title: "Docker", kind: .normal) { true })
        #expect(!third.matches(appId: "com.apple.finder", appName: "Finder", title: "Docker", kind: .normal) { false })
        var notImage = third
        notImage.diskImage = false
        #expect(notImage.matches(appId: nil, appName: nil, title: "", kind: .normal) { false })
        #expect(second.matches(appId: nil, appName: nil, title: "", kind: .normal) { Issue.record("asked without the condition"); return true })
        assertError("[[rules]]\ndisk-image = 'yes'\nrun = 'x'\n", path: "rules[0].disk-image", line: 2, contains: "true or false")
    }

    @Test func `Window rule matches the bundle ID by regex`() throws {
        let config = try Config.parse("""
        [[rules]]
        app-id-regex = '^co\\.ensili\\.'
        run = 'layout floating'

        [[rules]]
        app-id = 'co.ensili.Scrivener'
        app-id-regex = 'scrivener$'
        run = 'layout floating'
        """)
        var expected = WindowRule()
        expected.appIdRegex = "^co\\.ensili\\."
        expected.run = ["layout floating"]
        #expect(config.rules.first == expected)

        let prefix = config.rules[0], both = config.rules[1]
        #expect(prefix.matches(appId: "co.ensili.Scrivener", appName: "Scrivener", title: "", kind: .normal))
        #expect(prefix.matches(appId: "CO.Ensili.Other", appName: nil, title: "", kind: .normal), "case-insensitive")
        #expect(!prefix.matches(appId: "uk.co.ensili.x", appName: nil, title: "", kind: .normal), "anchored by the pattern")
        #expect(!prefix.matches(appId: nil, appName: "Scrivener", title: "", kind: .normal), "no bundle ID never matches")
        #expect(both.matches(appId: "co.ensili.Scrivener", appName: nil, title: "", kind: .normal))
        #expect(!both.matches(appId: "co.ensili.scrivener", appName: nil, title: "", kind: .normal), "app-id stays exact")
    }

    @Test func `Bad window rules fail`() {
        assertError("[[rules]]\napp-id = 'x'\n", path: "rules[0].run", line: 1, contains: "every rule needs 'run'")
        assertError("[[rules]]\ntitle = '('\nrun = 'x'\n", path: "rules[0].title", line: 2, contains: "not a valid regex")
        assertError("[[rules]]\napp-id-regex = '['\nrun = 'x'\n", path: "rules[0].app-id-regex", line: 2, contains: "not a valid regex")
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
        display-changed = 'layout accordion'
        """).hooks
        #expect(hooks.startup == ["exec-and-forget brew services restart sketchybar"])
        #expect(hooks.workspaceChanging == ["exec-and-forget sketchybar --trigger workspace_changing"])
        #expect(hooks.workspaceChanged == ["exec-and-forget sketchybar --trigger workspace_change"])
        #expect(hooks.focusChanged == [])
        #expect(hooks.modeChanged == ["exec-and-forget sketchybar --trigger mode_changed", "retile"])
        #expect(hooks.displayChanged == ["layout accordion"])
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
        #expect(Animations().durationMs == 363)
        #expect(Animations().damping == 1)
        #expect(try Config.parse("[animations]\ndamping = 0.9\n").animations.damping == 0.9)
        assertError("[animations]\ndamping = 0.2\n", path: "animations.damping", line: 2, contains: "0.5 to 1")
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
        #expect(!defaults.onNoop)
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
        #expect(drag.previewBorderColor == .color(Color(red: 1, green: 0, blue: 0)))
        #expect(drag.previewFillColor == Color(red: 0, green: 1, blue: 0, alpha: 128 / 255))
        #expect(drag.previewBorderWidth == 1.5)
        assertError("[drag]\npreview-border-color = 'blue'\n", path: "drag.preview-border-color", line: 2, contains: "'blue' is not a colour")
        assertError("[drag]\npreview-border-width = 21\n", path: "drag.preview-border-width", line: 2, contains: "0 to 20")
        assertError("[drag]\npreview-border-width = -1\n", path: "drag.preview-border-width", line: 2, contains: "0 to 20")
    }

    @Test func `Drag mouse modifier`() throws {
        #expect(Config.default.drag.mouseModifier == [])
        #expect(try Config.parse("[drag]\nmouse-modifier = 'none'\n").drag.mouseModifier == [])
        #expect(try Config.parse("[drag]\nmouse-modifier = 'alt'\n").drag.mouseModifier == .alt)
        let both = try Config.parse("[drag]\nmouse-modifier = 'cmd-ctrl'\n").drag.mouseModifier
        #expect(both == [.ctrl, .cmd])
        #expect(both.name == "ctrl-cmd")
        #expect(KeyCombo.Modifiers().name == "none")
        for bad in ["super", "alt-", "none-alt", "alt-h", ""] {
            assertError("[drag]\nmouse-modifier = '\(bad)'\n", path: "drag.mouse-modifier", line: 2, contains: "'\(bad)' is not 'none' or modifiers")
        }
        assertError("[drag]\nmouse-modifier = true\n", path: "drag.mouse-modifier", line: 2, contains: "a string")
        // A switcher's modifier held alone shows its capsule before the press.
        assertError("[window-switcher]\nmodifier = 'alt'\n[drag]\nmouse-modifier = 'alt'\n",
                    path: "drag.mouse-modifier", line: 4, contains: "[window-switcher] already uses 'alt'")
        assertError("[drag]\nmouse-modifier = 'cmd'\n[workspace-switcher]\nmodifier = 'cmd'\n",
                    path: "drag.mouse-modifier", line: 2, contains: "[workspace-switcher] already uses 'cmd'")
        let config = try Config.parse("[window-switcher]\nmodifier = 'alt'\n[drag]\nmouse-modifier = 'ctrl-alt'\n")
        #expect(config.drag.mouseModifier == [.ctrl, .alt])
        // Hyper conflicts by the modifiers it holds.
        assertError("[window-switcher]\nmodifier = 'hyper'\n[modifiers]\nhyper = 'ctrl-alt'\n[drag]\nmouse-modifier = 'alt-ctrl'\n",
                    path: "drag.mouse-modifier", line: 6, contains: "[window-switcher] already uses 'hyper'")
        let hyper = try Config.parse("[workspace-switcher]\nmodifier = 'hyper'\n[drag]\nmouse-modifier = 'ctrl-alt'\n")
        #expect(hyper.workspaceSwitcher.modifier == .hyper)
    }

    @Test func `Modifier sides`() throws {
        #expect(Config.default.modifiers == ModifierSides())
        let config = try Config.parse("[modifiers]\nalt = 'left'\nshift = 'right'\n")
        #expect(config.modifiers.alt == .left)
        #expect(config.modifiers.ctrl == .both)
        #expect(config.modifiers.shift == .right)
        assertError("[modifiers]\nalt = 'up'\n", path: "modifiers.alt", line: 2, contains: "'both', 'left', 'right'")
        assertError("[modifiers]\nfn = 'left'\n", path: "modifiers.fn", line: 2, contains: "unknown key")
        #expect(Config.default.modifiers.hyper == [.alt, .ctrl, .cmd, .shift])
        #expect(try Config.parse("[modifiers]\nhyper = 'cmd-ctrl'\n").modifiers.hyper == [.ctrl, .cmd])
        for bad in ["alt", "alt-alt", "hyper", "alt-fn", "none"] {
            assertError("[modifiers]\nhyper = '\(bad)'\n", path: "modifiers.hyper", line: 2, contains: "two or more")
        }
    }

    @Test func `Load from missing file fails`() {
        let error = #expect(throws: ConfigError.self) {
            try Config.load(from: URL(fileURLWithPath: "/nonexistent/dinky.toml"))
        }
        if let error { #expect("\(error)".contains("/nonexistent/dinky.toml")) }
    }
}
