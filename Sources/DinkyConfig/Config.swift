import Foundation
import TOMLDecoder

// Config types and TOML loading. No AppKit here; Carbon.HIToolbox for the key codes only.
// TOML keys are kebab-case, Swift properties camelCase. Every key is optional; the defaults are the
// property initial values, and the shipped file (DefaultConfig.swift) spells out the same values.

public struct Config: Equatable {
    public var startAtLogin = true
    /// Workspaces across all displays, numbered from 1. Each is one native Space.
    public var workspaces = 5
    /// `[workspace-to-display]`: by workspace number, the display patterns it lives on, the first that matches
    /// a connected display winning. Other workspaces, and these when no pattern matches, live on the main display.
    public var workspaceDisplays: [Int: [MonitorPattern]] = [:]
    /// Workspace layout, with 'tiles' retained as the old name for dwindle.
    public var defaultLayout = LayoutKind.tiles
    /// Whether dinky tiles numbered workspaces unless overridden.
    public var defaultTiling = true
    /// Workspace numbers (1-based) with their own tiling settings, resolved against the top-level defaults.
    public var workspaceLayouts: [Int: WorkspaceSettings] = [:]
    /// Cmd-Tab and Dock clicks go through the fast switch.
    public var followAppActivation = true
    /// Float standard windows whose fullscreen button is missing or disabled, as AeroSpace does.
    public var floatWindowsWithoutFullscreen = true
    /// What the menu bar item shows.
    public var menuBarIcon = MenuBarIcon.blocks
    /// When dinky hides its menu bar item: never, always, or while only one display is connected.
    public var hideMenuBarIcon = MenuBarIconHiding.never
    /// Whether dinky may use its Dock scripting addition, which needs SIP off. Off, it never probes or injects it,
    /// even with SIP off and the addition installed, and a scrolling strip moves its windows frame by frame instead.
    public var scriptingAddition = true
    /// What every highlight a table leaves unset takes: the switchers' pick, the focused window's border, the noop glow
    /// and a drag's preview. Nil leaves each its own default.
    public var highlightColor: Highlight?
    public var accordion = Accordion()
    public var scrolling = Scrolling()
    public var floating = Floating()
    public var fullscreen = Fullscreen()
    public var gaps = Gaps()
    /// `[display.<pattern>]` overrides, in file order.
    public var displays: [DisplayOverride] = []
    public var borders = Borders()
    public var focusFollowsMouse = FocusFollowsMouse()
    public var animations = Animations()
    public var drag = Drag()
    public var hud = Hud()
    /// `[switcher]` as the file sets it, already taken by the two switchers below where their own tables leave a key out.
    public var switcher = SwitcherDefaults()
    public var windowSwitcher = Switcher()
    public var workspaceSwitcher = WorkspaceSwitcher()
    public var gestures = Gestures()
    public var modifiers = ModifierSides()
    public var hooks = Hooks()
    /// `[[rules]]`, in file order.
    public var rules: [WindowRule] = []
    /// Keyed by mode name, e.g. `main`, `service`.
    public var modes: [String: Mode] = [:]

    public init() {}

    /// `~/.config/dinky/dinky.toml`
    public static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/dinky/dinky.toml")
    }

    /// The config shipped with dinky, used when the user has none.
    public static let `default` = try! parse(defaultTOML)

    public static func load(from url: URL) throws(ConfigError) -> Config {
        let toml: String
        do {
            toml = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError("can't read \(url.path): \(error.localizedDescription)")
        }
        return try parse(toml)
    }

    public static func parse(_ toml: String) throws(ConfigError) -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: toml)
        } catch {
            // Syntax errors; TOMLDecoder's text already carries the line.
            throw ConfigError("\(error)")
        }
        do {
            return try Config(Table(root))
        } catch let error as ConfigError {
            var error = error
            error.line = error.line ?? lineNumber(of: error.path, in: toml)
            throw error
        } catch {
            throw ConfigError("\(error)")
        }
    }

    init(_ t: Table) throws {
        startAtLogin = try t.bool("start-at-login") ?? startAtLogin
        workspaces = try t.int("workspaces") ?? workspaces
        guard workspaces >= 1 else { throw ConfigError(path: "workspaces", "must be at least 1") }
        if let assignments = try t.table("workspace-to-display") {
            for key in assignments.keys {
                guard let n = Int(key), (1...workspaces).contains(n) else {
                    throw ConfigError(path: assignments.path(key), "'\(key)' is not a workspace number from 1 to \(workspaces)")
                }
                let patterns = try assignments.stringOrStrings(key)!
                guard !patterns.isEmpty, !patterns.contains("") else {
                    throw ConfigError(path: assignments.path(key), "a display pattern can't be empty")
                }
                workspaceDisplays[n] = patterns.map(MonitorPattern.init)
            }
            try assignments.done()
        }
        defaultLayout = try t.choice("default-layout") ?? defaultLayout
        defaultTiling = try t.bool("default-tiling") ?? defaultTiling
        if let workspacesTable = try t.table("workspace") {
            for number in workspacesTable.keys {
                guard let index = Int(number), index > 0, String(index) == number else {
                    throw ConfigError(path: workspacesTable.path(number), "expected a positive workspace number")
                }
                workspaceLayouts[index] = try WorkspaceSettings(workspacesTable.table(number)!,
                                                                tiling: defaultTiling, layout: defaultLayout)
            }
        }
        followAppActivation = try t.bool("follow-app-activation") ?? followAppActivation
        floatWindowsWithoutFullscreen = try t.bool("float-windows-without-fullscreen") ?? floatWindowsWithoutFullscreen
        menuBarIcon = try t.choice("menu-bar-icon") ?? menuBarIcon
        hideMenuBarIcon = try t.choice("hide-menu-bar-icon") ?? hideMenuBarIcon
        scriptingAddition = try t.bool("scripting-addition") ?? scriptingAddition
        highlightColor = try t.highlight("highlight-color") ?? highlightColor
        accordion = try t.table("accordion").map(Accordion.init) ?? accordion
        scrolling = try t.table("scrolling").map(Scrolling.init) ?? scrolling
        floating = try t.table("floating").map(Floating.init) ?? floating
        fullscreen = try t.table("fullscreen").map(Fullscreen.init) ?? fullscreen
        gaps = try t.table("gaps").map { try gaps.applying(GapsPatch($0)) } ?? gaps
        if let displayTable = try t.table("display") {
            for pattern in displayTable.keys {
                displays.append(try DisplayOverride(pattern, displayTable.table(pattern)!))
            }
        }
        borders = try Borders(t.table("borders"), highlight: highlightColor)
        focusFollowsMouse = try t.table("focus-follows-mouse").map(FocusFollowsMouse.init) ?? focusFollowsMouse
        animations = try t.table("animations").map(Animations.init) ?? animations
        drag = try t.table("drag").map(Drag.init) ?? drag
        drag.previewBorderColor = drag.previewBorderColor ?? highlightColor
        hud = try t.table("hud").map(Hud.init) ?? hud
        switcher = try t.table("switcher").map(SwitcherDefaults.init) ?? switcher
        var shared = switcher
        shared.highlightColor = shared.highlightColor ?? highlightColor
        windowSwitcher = try Switcher(t.table("window-switcher"), defaults: shared)
        workspaceSwitcher = try WorkspaceSwitcher(t.table("workspace-switcher"), defaults: shared)
        modifiers = try t.table("modifiers").map(ModifierSides.init) ?? modifiers
        // One modifier can serve both when one holds and the other double-taps.
        if workspaceSwitcher.modifier != .none, workspaceSwitcher.modifier == windowSwitcher.modifier,
           workspaceSwitcher.trigger == windowSwitcher.trigger {
            throw ConfigError(path: "workspace-switcher.modifier",
                              "[window-switcher] already uses '\(windowSwitcher.modifier.rawValue)' with trigger '\(windowSwitcher.trigger.rawValue)'; use another modifier or trigger")
        }
        // Held alone, a switcher's modifier shows its capsule before the press that would drag.
        for (table, modifier) in [("window-switcher", windowSwitcher.modifier), ("workspace-switcher", workspaceSwitcher.modifier)]
        where modifier != .none
            && (modifier == .hyper ? modifiers.hyper : KeyCombo.Modifiers(names: modifier.rawValue)) == drag.mouseModifier {
            throw ConfigError(path: "drag.mouse-modifier", "[\(table)] already uses '\(modifier.rawValue)'")
        }
        gestures = try t.table("gestures").map(Gestures.init) ?? gestures
        hooks = try t.table("hooks").map(Hooks.init) ?? hooks
        rules = try t.tables("rules")?.map(WindowRule.init) ?? []
        if let modeTable = try t.table("mode") {
            for name in modeTable.keys {
                modes[name] = try Mode(modeTable.table(name)!)
            }
        }
        try t.done()
    }
}

/// A workspace's layout. `free` lays out nothing: every window on the workspace floats where it stands, as on a
/// desktop without dinky, and tiles again once it is on a workspace with another layout.
public enum LayoutKind: String, CaseIterable {
    case tiles, dwindle, accordion, fixed, scrolling, free
}

public enum ExpansionKind: String, CaseIterable {
    case rows, columns, accordion
}

/// A workspace's tiling settings: a `[workspace.N]` table with omitted keys taken from the top-level settings.
public struct WorkspaceSettings: Equatable {
    public var tiling: Bool
    public var layout: LayoutKind
    public var rows = 1
    public var columns = 1
    public var expand = ExpansionKind.columns

    public init(tiling: Bool, layout: LayoutKind) {
        self.tiling = tiling
        self.layout = layout
    }

    /// Every window on the workspace floats, whatever `tiling` says.
    public var isFree: Bool { layout == .free }

    init(_ t: Table, tiling: Bool, layout: LayoutKind) throws {
        self.tiling = try t.bool("tiling") ?? tiling
        if t.keys.contains("float") {
            throw ConfigError(path: t.path("float"), "a workspace whose windows all float has layout = 'free' now")
        }
        self.layout = try t.choice("layout") ?? layout
        let columns: Int? = try t.int("columns")
        let rows: Int? = try t.int("rows")
        let expand: ExpansionKind? = try t.choice("expand")
        if let columns, columns < 1 { throw ConfigError(path: t.path("columns"), "must be at least 1") }
        if let rows, rows < 1 { throw ConfigError(path: t.path("rows"), "must be at least 1") }
        try t.done()
        if self.layout != .fixed, let key = columns != nil ? "columns" : rows != nil ? "rows" : expand != nil ? "expand" : nil {
            throw ConfigError(path: t.path(key), "only valid for a fixed layout")
        }
        self.rows = rows ?? self.rows
        self.columns = columns ?? self.columns
        self.expand = expand ?? self.expand
    }
}

extension Config {
    /// Whether a key binding in any mode or a trackpad or mouse gesture runs `command`, a command name such as
    /// `workspace-switcher`.
    public func binds(_ command: String) -> Bool {
        let lists = modes.values.flatMap(\.allCommands) + gestures.trackpadSwipes.values + gestures.mouseSwipes.values
        return lists.contains { $0.contains { $0.split(separator: " ").first.map(String.init) == command } }
    }

    /// The settings of the workspace with this number, the top-level ones for an unnumbered workspace.
    public func settings(forWorkspace number: Int?) -> WorkspaceSettings {
        number.flatMap { workspaceLayouts[$0] } ?? WorkspaceSettings(tiling: defaultTiling, layout: defaultLayout)
    }
}

/// What a container's orientation becomes when it switches to accordion: `auto`, following its longer side,
/// or `keep`, the orientation it had. An orientation chosen with a `layout` command is always kept.
public enum AccordionOrientation: String, CaseIterable {
    case auto, keep
}

public struct Accordion: Equatable {
    /// Points by which neighbouring windows peek out.
    public var padding = 30
    public var orientation = AccordionOrientation.auto

    public init() {}

    init(_ t: Table) throws {
        padding = try t.int("padding") ?? padding
        orientation = try t.choice("orientation") ?? orientation
        try t.done()
    }
}

/// `[scrolling]`: the scrolling layout's columns.
public struct Scrolling: Equatable {
    /// A new column's width, as a share of the display's width inside the outer gaps. Omarchy's 0.49 fits two
    /// columns side by side with a sliver of margin; a lone column always fills the display.
    public var columnWidth = 0.49
    /// Where focusing a column scrolls it, as niri's `center-focused-column`.
    public var centerFocusedColumn = CenterFocusedColumn.never
    /// Whether the file still sets `glide`, which no longer does anything: the strip scrolls through the Dock
    /// scripting addition when top-level `scripting-addition` allows it and the addition answers, and moves its windows
    /// frame by frame otherwise. `dinky doctor` says the key can go.
    public var retiredGlide = false

    public init() {}

    init(_ t: Table) throws {
        columnWidth = try t.double("column-width") ?? columnWidth
        guard (0.1...1).contains(columnWidth) else { throw ConfigError(path: t.path("column-width"), "must be 0.1 to 1") }
        centerFocusedColumn = try t.choice("center-focused-column") ?? centerFocusedColumn
        retiredGlide = t.retired("glide")
        try t.done()
    }
}

/// The modifier that shows the switcher, its side as `[modifiers]` says; `none` turns the switcher off. `hyper` is
/// `[modifiers] hyper`'s modifiers held together, from either side.
public enum SwitcherModifier: String, CaseIterable {
    case none, alt, ctrl, cmd, shift, hyper
}

/// A layout the switcher shows for: `tiles` is dwindle, `accordion` a dwindle accordion root, `free` a workspace dinky
/// does not tile (`layout = 'free'` or `tiling = false`).
public enum SwitcherLayoutKind: String, CaseIterable {
    case scrolling, tiles, accordion, fixed, free
}

/// How the modifier shows the switcher: held on its own, or tapped twice on its own.
public enum SwitcherTrigger: String, CaseIterable {
    case hold
    case doubleTap = "double-tap"
}

/// How the switcher shows a tiles or fixed workspace: a map of its tiles, or a row like a strip's.
public enum SwitcherTilesStyle: String, CaseIterable {
    case map, row
}

/// Where a switcher's capsule shows, on the display under the pointer.
public enum SwitcherPosition: String, CaseIterable {
    /// Over the pointer when the modifier is held or a swipe shows it, in the middle from a key binding.
    case auto
    /// In the middle of the display.
    case center
    /// Below the menu bar, across the middle.
    case top
    /// Above the Dock, across the middle.
    case bottom
    /// Over the pointer, from a key binding too.
    case mouse
}

/// `[switcher]`: what the window and workspace switchers share, each key what both take where their own table leaves
/// it out.
public struct SwitcherDefaults: Equatable {
    /// Whether the switcher shows at all, its modifier held, a binding pressed or a swipe made.
    public var enabled = true
    /// How long the modifier is held alone before the capsule shows.
    public var delayMs = 200
    public var trigger = SwitcherTrigger.hold
    /// With `double-tap`, how long each tap and the gap between them may last.
    public var doubleTapMs = 300
    /// Points; at half the capsule's height or more its ends are round.
    public var cornerRadius = 52.0
    public var position = SwitcherPosition.auto
    /// Whether each window shows its title: under its card in the window switcher, on a band along its foot in a
    /// workspace card.
    public var showTitles = true
    /// Whether each window gets a letter of `letters`, drawn as a key beside its title, whose key jumps to it.
    public var letterKeys = true
    /// The letters handed out, in order, to the windows as they read left to right: a to z, each once, but h, j, k
    /// and l, which move the pick.
    public var letters = SwitcherDefaults.defaultLetters
    /// The pick's ring and glow; nil takes the top-level `highlight-color`.
    public var highlightColor: Highlight?

    /// The home row first, then the rows above and below.
    public static let defaultLetters = Array("asdfgqwertyuiopzxcvbnm")

    public init() {}

    init(_ t: Table) throws {
        try read(t)
        try t.done()
    }

    /// Takes the shared keys `t` sets over these: `[switcher]`'s, or a switcher's own.
    mutating func read(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        delayMs = try t.int("delay-ms") ?? delayMs
        guard (0...2000).contains(delayMs) else { throw ConfigError(path: t.path("delay-ms"), "must be 0 to 2000") }
        trigger = try t.choice("trigger") ?? trigger
        doubleTapMs = try t.int("double-tap-ms") ?? doubleTapMs
        guard (100...1000).contains(doubleTapMs) else {
            throw ConfigError(path: t.path("double-tap-ms"), "must be 100 to 1000")
        }
        cornerRadius = try t.double("corner-radius") ?? cornerRadius
        guard (0...80).contains(cornerRadius) else { throw ConfigError(path: t.path("corner-radius"), "must be 0 to 80") }
        position = try t.choice("position") ?? position
        showTitles = try t.bool("show-titles") ?? showTitles
        letterKeys = try t.bool("letter-keys") ?? letterKeys
        if let string = try t.string("letters") {
            let letters = Array(string)
            guard !letters.isEmpty else { throw ConfigError(path: t.path("letters"), "must have a letter at least") }
            for letter in letters {
                guard ("a"..."z").contains(letter), letter.isASCII else {
                    throw ConfigError(path: t.path("letters"), "'\(letter)' is not a lowercase letter, a to z")
                }
                guard !"hjkl".contains(letter) else {
                    throw ConfigError(path: t.path("letters"), "'\(letter)' moves the pick; leave out h, j, k and l")
                }
            }
            if let twice = letters.first(where: { l in letters.filter { $0 == l }.count > 1 }) {
                throw ConfigError(path: t.path("letters"), "'\(twice)' is there twice")
            }
            self.letters = letters
        }
        highlightColor = try t.highlight("highlight-color") ?? highlightColor
    }
}

/// `[window-switcher]`: hold the modifier on its own over a workspace laid out by one of `layouts` and a capsule of its
/// windows shows at the pointer; release to focus the one picked. `enabled`, `delay-ms`, `corner-radius`, `position`,
/// `show-titles`, `letter-keys`, `letters` and `highlight-color` left out are `[switcher]`'s.
public struct Switcher: Equatable {
    public var enabled = true
    public var modifier = SwitcherModifier.none
    /// How long the modifier is held alone before the capsule shows.
    public var delayMs = 200
    public var trigger = SwitcherTrigger.hold
    /// With `double-tap`, how long each tap and the gap between them may last.
    public var doubleTapMs = 300
    public var layouts: [SwitcherLayoutKind] = [.scrolling, .tiles]
    /// Points; at half the capsule's height or more its ends are round.
    public var cornerRadius = 52.0
    public var tilesStyle = SwitcherTilesStyle.map
    /// Whether the capsule shows for a workspace with a lone tiled window (on a free workspace, a lone window), the
    /// modifier held or the binding pressed.
    public var showSingle = true
    /// Whether each window's title shows under its card, or along its foot where another card sits below it.
    public var showTitles = true
    /// Whether each window has a letter key beside its title that jumps to it, and the letters, in reading order.
    public var letterKeys = true
    public var letters = SwitcherDefaults.defaultLetters
    public var position = SwitcherPosition.auto
    /// The pick's ring and glow.
    public var highlightColor = Highlight.accent

    public init() {}

    init(_ t: Table?, defaults: SwitcherDefaults) throws {
        var shared = defaults
        if let t { try shared.read(t) }
        enabled = shared.enabled
        delayMs = shared.delayMs
        trigger = shared.trigger
        doubleTapMs = shared.doubleTapMs
        cornerRadius = shared.cornerRadius
        position = shared.position
        showTitles = shared.showTitles
        letterKeys = shared.letterKeys
        letters = shared.letters
        highlightColor = shared.highlightColor ?? .accent
        guard let t else { return }
        modifier = try t.choice("modifier") ?? modifier
        if let names = try t.strings("layouts") {
            layouts = try names.map { name in
                guard let kind = SwitcherLayoutKind(rawValue: name) else {
                    let choices = SwitcherLayoutKind.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
                    throw ConfigError(path: t.path("layouts"), "'\(name)' is not one of \(choices)")
                }
                return kind
            }
        }
        tilesStyle = try t.choice("tiles-style") ?? tilesStyle
        showSingle = try t.bool("show-single") ?? showSingle
        try t.done()
    }
}

/// A swipe on the trackpad or mouse that `[gestures]` can bind, by the way the fingers move.
public enum GestureSwipe: String, CaseIterable {
    case swipeLeft = "swipe-left", swipeRight = "swipe-right", swipeUp = "swipe-up", swipeDown = "swipe-down"
}

/// `[gestures]`: swipes on the trackpad in `[gestures.trackpad]` and on a Magic Mouse in `[gestures.mouse]`, each
/// running commands as a key binding does, and fingers on the trackpad scrolling a strip in `[gestures.scroll]`.
public struct Gestures: Equatable {
    public var trackpad = TrackpadSwipes()
    public var mouse = MouseSwipes()
    public var scroll = ScrollGesture()

    public init() {}

    init(_ t: Table) throws {
        for key in t.keys where !["trackpad", "mouse", "scroll"].contains(key) {
            guard key == "fingers" || key == "distance" || key == "step" || GestureSwipe(rawValue: key) != nil else {
                throw ConfigError(path: t.path(key), "'\(key)' is not one of 'trackpad', 'mouse', 'scroll'")
            }
            throw ConfigError(path: t.path(key), "'\(key)' goes in [gestures.trackpad] now")
        }
        trackpad = try t.table("trackpad").map(TrackpadSwipes.init) ?? trackpad
        mouse = try t.table("mouse").map(MouseSwipes.init) ?? mouse
        scroll = try t.table("scroll").map(ScrollGesture.init) ?? scroll
        try t.done()
        // The same fingers across would scroll the strip and swipe at once.
        if scroll.enabled, trackpad.enabled, scroll.fingers == trackpad.fingers,
           let across = [GestureSwipe.swipeLeft, .swipeRight].first(where: { trackpad.swipes[$0] != nil }) {
            throw ConfigError(path: t.path("scroll.fingers"),
                              "[gestures.trackpad] already uses \(trackpad.fingers) fingers for '\(across.rawValue)'; use other fingers, or bind only swipe-up and swipe-down there")
        }
    }

    /// What the trackpad swipes run; none while it is off.
    public var trackpadSwipes: [GestureSwipe: [String]] { trackpad.enabled ? trackpad.swipes : [:] }

    /// What the mouse swipes run: its own, or the trackpad's; none while it is off.
    public var mouseSwipes: [GestureSwipe: [String]] {
        mouse.enabled ? mouse.swipes ?? trackpad.swipes : [:]
    }
}

/// `[gestures.trackpad]`: swipes on the trackpad with `fingers` fingers, once they move `distance` millimetres. A
/// swipe that shows a switcher goes on picking with the same fingers, a step every `step` millimetres, until they lift.
public struct TrackpadSwipes: Equatable {
    public var enabled = true
    /// How many fingers swipe, 2 to 5.
    public var fingers = 3
    /// Millimetres the fingers move before it is a swipe.
    public var distance = 15.0
    /// Millimetres the fingers move for each step of a switcher's pick.
    public var step = 12.0
    public var swipes: [GestureSwipe: [String]] = [:]

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        fingers = try t.int("fingers") ?? fingers
        guard (2...5).contains(fingers) else { throw ConfigError(path: t.path("fingers"), "must be 2 to 5") }
        distance = try t.double("distance") ?? distance
        guard (6...40).contains(distance) else { throw ConfigError(path: t.path("distance"), "must be 6 to 40") }
        step = try t.double("step") ?? step
        guard (4...50).contains(step) else { throw ConfigError(path: t.path("step"), "must be 4 to 50") }
        swipes = try gestureSwipes(t, besides: ["enabled", "fingers", "distance", "step"])
        try t.done()
    }
}

/// `[gestures.mouse]`: swipes on a Magic Mouse, as `[gestures.trackpad]` has them on the trackpad but with lengths for
/// its narrower surface, and fingers that may already rest on it before the last lands. Two by default: held as a
/// mouse is, it seldom feels a third, which lies along its edge. Its own swipes replace all of the trackpad's; without
/// any, those run. Off until `enabled`.
public struct MouseSwipes: Equatable {
    public var enabled = false
    /// How many fingers swipe, 2 to 4. One scrolls; two swipe between full-screen apps unless that is off.
    public var fingers = 2
    /// Millimetres the fingers move before it is a swipe.
    public var distance = 8.0
    /// Millimetres the fingers move for each step of a switcher's pick.
    public var step = 4.0
    /// Nil for the trackpad's.
    public var swipes: [GestureSwipe: [String]]?

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        fingers = try t.int("fingers") ?? fingers
        guard (2...4).contains(fingers) else { throw ConfigError(path: t.path("fingers"), "must be 2 to 4") }
        distance = try t.double("distance") ?? distance
        guard (3...30).contains(distance) else { throw ConfigError(path: t.path("distance"), "must be 3 to 30") }
        step = try t.double("step") ?? step
        guard (2...30).contains(step) else { throw ConfigError(path: t.path("step"), "must be 2 to 30") }
        let own = try gestureSwipes(t, besides: ["enabled", "fingers", "distance", "step"])
        swipes = own.isEmpty ? nil : own
        try t.done()
    }
}

/// `[gestures.scroll]`: `fingers` fingers moved across the trackpad scroll a strip with them, as SlideScroll's do: let
/// go, it coasts on at their speed and settles with the column nearest the middle in view, and once it rests the
/// window switcher shows it for `switcher-ms`, that column's window picked, unless not `show-switcher`. Pushed on past
/// an end, the display's side there glows, unless not `edge-flash`. Off until `enabled`. Never on a mouse.
public struct ScrollGesture: Equatable {
    public var enabled = false
    /// How many fingers scroll, 3 to 5.
    public var fingers = 4
    /// How many screens the strip moves as the fingers cross the whole trackpad.
    public var speed = 1.5
    /// Whether the window switcher shows the strip once it rests after the fingers let go, and for how long.
    public var showSwitcher = true
    public var switcherMs = 1000
    /// Whether the display's side glows, left or right, as the fingers push the strip on past that end.
    public var edgeFlash = true

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        fingers = try t.int("fingers") ?? fingers
        guard (3...5).contains(fingers) else { throw ConfigError(path: t.path("fingers"), "must be 3 to 5") }
        speed = try t.double("speed") ?? speed
        guard (0.25...5).contains(speed) else { throw ConfigError(path: t.path("speed"), "must be 0.25 to 5") }
        showSwitcher = try t.bool("show-switcher") ?? showSwitcher
        edgeFlash = try t.bool("edge-flash") ?? edgeFlash
        switcherMs = try t.int("switcher-ms") ?? switcherMs
        guard (100...5000).contains(switcherMs) else {
            throw ConfigError(path: t.path("switcher-ms"), "must be 100 to 5000")
        }
        try t.done()
    }

    /// What macOS does as `fingers` fingers move across the trackpad, which scrolling a strip with them would set off
    /// too, from its trackpad settings: `three` and `four` are TrackpadThreeFingerHorizSwipeGesture and
    /// TrackpadFourFingerHorizSwipeGesture (0 off, 1 between pages, 2 between full-screen apps and Spaces), and `drag`
    /// whether three fingers drag. Three fingers between Spaces takes four as well.
    public static func clashes(fingers: Int, three: Int, four: Int, drag: Bool) -> [String] {
        switch fingers {
        case 3:
            var clashes: [String] = []
            if three == 2 {
                clashes.append("switch Spaces")
            } else if three != 0 {
                clashes.append("swipe between pages")
            }
            if drag { clashes.append("drag") }
            return clashes
        case 4:
            return four == 2 || three == 2 ? ["switch Spaces"] : []
        default:
            return []
        }
    }
}

/// A gesture table's swipes: every key but `besides` must be one.
private func gestureSwipes(_ t: Table, besides: [String]) throws -> [GestureSwipe: [String]] {
    var swipes: [GestureSwipe: [String]] = [:]
    for key in t.keys where !besides.contains(key) {
        guard let swipe = GestureSwipe(rawValue: key) else {
            let choices = GestureSwipe.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            throw ConfigError(path: t.path(key), "'\(key)' is not one of \(choices)")
        }
        swipes[swipe] = try t.commands(key)
    }
    return swipes
}

/// Which displays' workspaces the workspace switcher shows.
public enum WorkspaceSwitcherDisplays: String, CaseIterable {
    /// Every display's, a group per display.
    case all
    /// Only the workspaces of the display under the pointer.
    case pointer
}

/// What the workspace switcher's cards show in each window.
public enum WorkspaceSwitcherThumbnails: String, CaseIterable {
    /// A picture of the window, needing Screen Recording; its app's icon until there is one.
    case windows
    /// Its app's icon.
    case icons
    /// A fixed picture of each workspace's layout, the same whatever its windows.
    case schematic
}

/// `[workspace-switcher]`: hold the modifier on its own and a capsule of the workspaces shows at the pointer, each
/// drawn small in its layout; release to switch to the one picked. `enabled`, `delay-ms`, `corner-radius`, `position`,
/// `show-titles`, `letter-keys`, `letters` and `highlight-color` left out are `[switcher]`'s.
public struct WorkspaceSwitcher: Equatable {
    public var enabled = true
    public var modifier = SwitcherModifier.none
    /// How long the modifier is held alone before the capsule shows.
    public var delayMs = 200
    public var trigger = SwitcherTrigger.hold
    /// With `double-tap`, how long each tap and the gap between them may last.
    public var doubleTapMs = 300
    public var displays = WorkspaceSwitcherDisplays.all
    /// Whether workspaces without windows get a card.
    public var showEmpty = true
    /// Workspace numbers left out.
    public var exclude: [Int] = []
    /// Points; each card is as wide as its display's proportions give.
    public var cardHeight = 85.0
    public var thumbnails = WorkspaceSwitcherThumbnails.windows
    /// Points.
    public var cornerRadius = 52.0
    public var position = SwitcherPosition.auto
    /// Whether each window in a card shows its title on a band along its foot; not on a schematic card.
    public var showTitles = true
    /// Whether each window in a card has a letter key that switches to its workspace and focuses it, and the
    /// letters, in reading order; not on a schematic card.
    public var letterKeys = true
    public var letters = SwitcherDefaults.defaultLetters
    /// The pick's ring and glow, and a schematic card's windows once picked.
    public var highlightColor = Highlight.accent

    public init() {}

    init(_ t: Table?, defaults: SwitcherDefaults) throws {
        var shared = defaults
        if let t { try shared.read(t) }
        enabled = shared.enabled
        delayMs = shared.delayMs
        trigger = shared.trigger
        doubleTapMs = shared.doubleTapMs
        cornerRadius = shared.cornerRadius
        position = shared.position
        showTitles = shared.showTitles
        letterKeys = shared.letterKeys
        letters = shared.letters
        highlightColor = shared.highlightColor ?? .accent
        guard let t else { return }
        modifier = try t.choice("modifier") ?? modifier
        displays = try t.choice("displays") ?? displays
        showEmpty = try t.bool("show-empty") ?? showEmpty
        exclude = try t.ints("exclude") ?? exclude
        guard exclude.allSatisfy({ $0 >= 1 }) else { throw ConfigError(path: t.path("exclude"), "workspace numbers start at 1") }
        cardHeight = try t.double("card-height") ?? cardHeight
        guard (60...200).contains(cardHeight) else { throw ConfigError(path: t.path("card-height"), "must be 60 to 200") }
        thumbnails = try t.choice("thumbnails") ?? thumbnails
        try t.done()
    }
}

/// Which point of a floating window stays put when `resize` changes its size. The names match
/// `DinkyLayout.ResizeAnchor`.
public enum FloatingResizeAnchor: String, CaseIterable {
    /// It grows and shrinks about its centre.
    case center
    /// Its top-left corner stays: it grows to the right and down.
    case topLeft = "top-left"
}

/// `[floating]`: what tiling commands do to a floating window.
public struct Floating: Equatable {
    /// Points `move` shifts a floating window by when the command gives no number.
    public var moveStep = 50
    public var resizeAnchor = FloatingResizeAnchor.center

    public init() {}

    init(_ t: Table) throws {
        moveStep = try t.int("move-step") ?? moveStep
        guard (1...1000).contains(moveStep) else { throw ConfigError(path: t.path("move-step"), "must be 1 to 1000") }
        resizeAnchor = try t.choice("resize-anchor") ?? resizeAnchor
        try t.done()
    }
}

/// What focusing another window of the workspace does while one is fullscreen. The names match
/// `DinkyLayout.FullscreenFocus`.
public enum FullscreenFocusChange: String, CaseIterable {
    /// Fullscreen ends; the window goes back to its tile.
    case exit
    /// The newly focused window goes fullscreen and the other goes back to its tile.
    case follow
    /// The newly focused window goes fullscreen too; the other stays fullscreen behind it.
    case keep
}

/// Where focusing a scrolling column scrolls it. The names match `DinkyLayout.ColumnCentring`.
public enum CenterFocusedColumn: String, CaseIterable {
    /// Just far enough to show it whole.
    case never
    /// To the middle of the display, an end column too, the display bare beyond it.
    case always
    /// To the middle of the display, but never past the strip's ends: an end column, and with narrow columns the one
    /// next to it, only to the display's edge, the columns beside it filling the rest.
    case alwaysFill = "always-fill"
    /// To the middle when it did not all show; one already in view stays where it is.
    case onOverflow = "on-overflow"
}

/// What fullscreen does to the other columns of a scrolling workspace.
public enum FullscreenScrolling: String, CaseIterable {
    /// The window's column widens to the screen and its neighbours slide off it.
    case push
    /// The window covers the columns where they are.
    case over
}

/// `[fullscreen]`: dinky's fullscreen, a window filling its workspace over the tree.
public struct Fullscreen: Equatable {
    public var focusChange = FullscreenFocusChange.exit
    /// With `follow`, how long the newly focused window waits before going fullscreen, so the window it took focus
    /// from is back in its tile first. 0 swaps them at once.
    public var followDelayMs = 0
    public var scrolling = FullscreenScrolling.push

    public init() {}

    init(_ t: Table) throws {
        focusChange = try t.choice("focus-change") ?? focusChange
        followDelayMs = try t.int("follow-delay-ms") ?? followDelayMs
        guard (0...5000).contains(followDelayMs) else {
            throw ConfigError(path: t.path("follow-delay-ms"), "must be 0 to 5000")
        }
        scrolling = try t.choice("scrolling") ?? scrolling
        try t.done()
    }
}

/// A block per display with its workspace number, the focused display's filled, the focused display's
/// workspace number as text, or nothing, hiding the item (the CLI still works).
public enum MenuBarIcon: String, CaseIterable {
    case blocks, text, none
}

/// Show the menu bar item, hide it, or hide it only while a single display is connected, where one block or number
/// tells nothing the screen doesn't.
public enum MenuBarIconHiding: String, CaseIterable {
    case never, always
    case singleDisplay = "single-display"
}

/// Below the target, or above it as a ring that never covers content or takes clicks.
public enum BorderOrder: String, CaseIterable {
    case below, above
}

public struct Borders: Equatable {
    public var enabled = true
    public var width = 4.0
    /// The focused window's: the top-level `highlight-color` when the table leaves it out and that is set.
    public var activeColor = Highlight.color(try! Color(hex: "#e1e3e4"))
    public var inactiveColor = try! Color(hex: "#494d64")
    public var order = BorderOrder.below
    /// Bundle IDs whose windows get no border.
    public var excludeApps: [String] = []
    /// Whether a binding that does nothing makes the focused window's edge glow once.
    public var noopFlash = true
    /// The glow's colour: the top-level `highlight-color` when the table leaves it out and that is set, else Claude's
    /// orange, as the screen's edges glow while Claude uses the computer.
    public var noopFlashColor = Highlight.color(try! Color(hex: "#d97757"))
    /// The ring around the window, in points; 0 leaves it out.
    public var noopFlashWidth = 2.0
    /// How far the glow inside the window reaches in, fading as it goes, in points.
    public var noopFlashSpread = 100.0
    /// The glow's opacity at the window's edge, as a share of the colour's own; 0 leaves it out.
    public var noopFlashOpacity = 0.6
    /// Whether a pinned column's shown windows get a ring of their own, borders on or off, focused or not.
    public var pinned = true
    /// The pinned windows' ring: the top-level `highlight-color` when the table leaves it out and that is set, else
    /// Claude's orange, as the noop flash.
    public var pinnedColor = Highlight.color(try! Color(hex: "#d97757"))
    /// The pinned windows' ring, in points; 0 leaves it out.
    public var pinnedWidth = 2.0

    public init() {}

    init(_ t: Table?, highlight: Highlight?) throws {
        activeColor = highlight ?? activeColor
        noopFlashColor = highlight ?? noopFlashColor
        pinnedColor = highlight ?? pinnedColor
        guard let t else { return }
        enabled = try t.bool("enabled") ?? enabled
        width = try t.double("width") ?? width
        activeColor = try t.highlight("active-color") ?? activeColor
        inactiveColor = try t.color("inactive-color") ?? inactiveColor
        order = try t.choice("order") ?? order
        excludeApps = try t.strings("exclude-apps") ?? excludeApps
        noopFlash = try t.bool("noop-flash") ?? noopFlash
        noopFlashColor = try t.highlight("noop-flash-color") ?? noopFlashColor
        noopFlashWidth = try t.double("noop-flash-width") ?? noopFlashWidth
        guard (0...8).contains(noopFlashWidth) else { throw ConfigError(path: t.path("noop-flash-width"), "must be 0 to 8") }
        noopFlashSpread = try t.double("noop-flash-spread") ?? noopFlashSpread
        guard (8...160).contains(noopFlashSpread) else { throw ConfigError(path: t.path("noop-flash-spread"), "must be 8 to 160") }
        noopFlashOpacity = try t.double("noop-flash-opacity") ?? noopFlashOpacity
        guard (0...1).contains(noopFlashOpacity) else { throw ConfigError(path: t.path("noop-flash-opacity"), "must be 0 to 1") }
        pinned = try t.bool("pinned") ?? pinned
        pinnedColor = try t.highlight("pinned-color") ?? pinnedColor
        pinnedWidth = try t.double("pinned-width") ?? pinnedWidth
        guard (0...8).contains(pinnedWidth) else { throw ConfigError(path: t.path("pinned-width"), "must be 0 to 8") }
        try t.done()
    }

    /// Whether windows of the app with this bundle ID get a border.
    public func decorates(bundleID: String?) -> Bool {
        !(bundleID.map(excludeApps.contains) ?? false)
    }
}

public struct FocusFollowsMouse: Equatable {
    public var enabled = false
    /// How long the pointer must rest on a window before it takes focus.
    public var delayMs = 100
    /// Whether resting on the peeking edge of an accordion child focuses it. Off, only the front child does.
    public var accordionEdges = true

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        delayMs = try t.int("delay-ms") ?? delayMs
        guard delayMs >= 0 else { throw ConfigError(path: t.path("delay-ms"), "must be 0 or more") }
        accordionEdges = try t.bool("accordion-edges") ?? accordionEdges
        try t.done()
    }
}

/// How windows travel: on a spring, or along one of easings.net's timing functions over `duration-ms`, as yabai's
/// `window_animation_easing`. The names match `DinkyLayout.Easing`.
public enum AnimationCurve: String, CaseIterable {
    case spring, linear
    case easeInSine = "ease-in-sine", easeOutSine = "ease-out-sine", easeInOutSine = "ease-in-out-sine"
    case easeInQuad = "ease-in-quad", easeOutQuad = "ease-out-quad", easeInOutQuad = "ease-in-out-quad"
    case easeInCubic = "ease-in-cubic", easeOutCubic = "ease-out-cubic", easeInOutCubic = "ease-in-out-cubic"
    case easeInQuart = "ease-in-quart", easeOutQuart = "ease-out-quart", easeInOutQuart = "ease-in-out-quart"
    case easeInQuint = "ease-in-quint", easeOutQuint = "ease-out-quint", easeInOutQuint = "ease-in-out-quint"
    case easeInExpo = "ease-in-expo", easeOutExpo = "ease-out-expo", easeInOutExpo = "ease-in-out-expo"
    case easeInCirc = "ease-in-circ", easeOutCirc = "ease-out-circ", easeInOutCirc = "ease-in-out-circ"
}

/// `[animations]`: windows glide to their tiles instead of jumping. Off while macOS's Reduce Motion is on.
public struct Animations: Equatable {
    public var enabled = true
    /// Roughly how long a window takes to reach its tile on the spring, exactly how long along an easing. 0 jumps,
    /// as with animations off. 363 with `damping` 1 is SlideScroll's spring, its stiffness 300.
    public var durationMs = 363
    /// How the spring settles, 0.5 to 1: 1 eases into place without overshooting; lower gets there sooner and
    /// overshoots, more the lower.
    public var damping = 1.0
    public var curve = AnimationCurve.spring

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        durationMs = try t.int("duration-ms") ?? durationMs
        guard (0...1000).contains(durationMs) else { throw ConfigError(path: t.path("duration-ms"), "must be 0 to 1000") }
        damping = try t.double("damping") ?? damping
        guard (0.5...1).contains(damping) else { throw ConfigError(path: t.path("damping"), "must be 0.5 to 1") }
        curve = try t.choice("curve") ?? curve
        try t.done()
    }
}

/// `[drag]`: dragging a tiled window with the mouse.
public struct Drag: Equatable {
    /// Have the other windows make room for a dragged window and show a preview where it will go.
    public var placeholders = true
    /// The preview's border: the top-level `highlight-color` when the table leaves it out. Nil follows the system
    /// accent colour.
    public var previewBorderColor: Highlight?
    /// Its fill. Nil is the border colour at 30%.
    public var previewFillColor: Color?
    /// Points, for the preview and the outlines around it.
    public var previewBorderWidth = 3.0
    /// Whether the tile a dragged window goes back to is outlined while the drag would put it back.
    public var homeOutline = true
    /// Held, exactly these, a press anywhere in a window drags it, not only on its title bar. Empty is off.
    public var mouseModifier: KeyCombo.Modifiers = []

    public init() {}

    init(_ t: Table) throws {
        placeholders = try t.bool("placeholders") ?? placeholders
        if let names = try t.string("mouse-modifier") {
            guard let modifiers = KeyCombo.Modifiers(names: names) else {
                throw ConfigError(path: t.path("mouse-modifier"),
                                  "'\(names)' is not 'none' or modifiers (alt, ctrl, cmd, shift) joined by '-'")
            }
            mouseModifier = modifiers
        }
        previewBorderColor = try t.highlight("preview-border-color") ?? previewBorderColor
        previewFillColor = try t.color("preview-fill-color") ?? previewFillColor
        previewBorderWidth = try t.double("preview-border-width") ?? previewBorderWidth
        homeOutline = try t.bool("home-outline") ?? homeOutline
        guard (0...20).contains(previewBorderWidth) else {
            throw ConfigError(path: t.path("preview-border-width"), "must be 0 to 20")
        }
        try t.done()
    }
}

/// Where the HUD shows: above the Dock, or below the menu bar.
public enum HudPosition: String, CaseIterable {
    case bottom, top
}

/// `[hud]`: a glass capsule naming the new layout or binding mode for a moment after it changes.
public struct Hud: Equatable {
    public var enabled = true
    public var position = HudPosition.bottom
    /// How long it stays before fading out. Another change meanwhile restarts the count.
    public var durationMs = 1200
    /// Points between the capsule and the Dock or menu bar, or the screen's edge where neither is.
    public var offset = 16.0
    /// Shown for the `layout` command.
    public var onLayoutChange = true
    /// Shown when the binding mode changes.
    public var onModeChange = true
    /// Shown when a display moves to another workspace, with that workspace's layout.
    public var onWorkspaceChange = true
    /// Shown, with the command's answer, when a binding does nothing.
    public var onNoop = false

    public init() {}

    init(_ t: Table) throws {
        enabled = try t.bool("enabled") ?? enabled
        position = try t.choice("position") ?? position
        durationMs = try t.int("duration-ms") ?? durationMs
        guard (100...10000).contains(durationMs) else { throw ConfigError(path: t.path("duration-ms"), "must be 100 to 10000") }
        offset = try t.double("offset") ?? offset
        guard (0...200).contains(offset) else { throw ConfigError(path: t.path("offset"), "must be 0 to 200") }
        onLayoutChange = try t.bool("on-layout-change") ?? onLayoutChange
        onModeChange = try t.bool("on-mode-change") ?? onModeChange
        onWorkspaceChange = try t.bool("on-workspace-change") ?? onWorkspaceChange
        onNoop = try t.bool("on-noop") ?? onNoop
        try t.done()
    }
}

/// Which of a modifier's two keys bindings answer to.
public enum ModifierSide: String, CaseIterable {
    case both, left, right
}

/// `[modifiers]`: a modifier limited to one side is only a binding's modifier from that side's key; the other
/// key types as usual, so right Option can still make special characters while left Option drives dinky.
public struct ModifierSides: Equatable {
    public var alt = ModifierSide.both
    public var ctrl = ModifierSide.both
    public var cmd = ModifierSide.both
    public var shift = ModifierSide.both
    /// The modifiers a switcher's `hyper` holds together, two or more.
    public var hyper: KeyCombo.Modifiers = [.alt, .ctrl, .cmd, .shift]

    public init() {}

    init(_ t: Table) throws {
        alt = try t.choice("alt") ?? alt
        ctrl = try t.choice("ctrl") ?? ctrl
        cmd = try t.choice("cmd") ?? cmd
        shift = try t.choice("shift") ?? shift
        if let names = try t.string("hyper") {
            guard let modifiers = KeyCombo.Modifiers(names: names),
                  KeyCombo.Modifiers.names.filter({ modifiers.contains($0.1) }).count >= 2 else {
                throw ConfigError(path: t.path("hyper"), "'\(names)' is not two or more of alt, ctrl, cmd, shift joined by -")
            }
            hyper = modifiers
        }
        try t.done()
    }
}

/// `[hooks]`: dinky commands run on events. Each is a command string or a list, empty by default.
public struct Hooks: Equatable {
    /// Once, after dinky has first read the windows and displays.
    public var startup: [String] = []
    /// When dinky starts switching a display to a workspace, or a switch in flight gets a new target.
    public var workspaceChanging: [String] = []
    /// When a display's current workspace changes, by dinky or natively, and when a dinky switch gives up.
    public var workspaceChanged: [String] = []
    /// When the focused window changes.
    public var focusChanged: [String] = []
    /// When the binding mode changes.
    public var modeChanged: [String] = []

    public init() {}

    init(_ t: Table) throws {
        startup = try t.commands("startup", allowEmpty: true) ?? startup
        workspaceChanging = try t.commands("workspace-changing", allowEmpty: true) ?? workspaceChanging
        workspaceChanged = try t.commands("workspace-changed", allowEmpty: true) ?? workspaceChanged
        focusChanged = try t.commands("focus-changed", allowEmpty: true) ?? focusChanged
        modeChanged = try t.commands("mode-changed", allowEmpty: true) ?? modeChanged
        try t.done()
    }
}
