import Foundation
import Testing
import DinkyConfig
import DinkyLayout
import TOMLDecoder
@testable import DinkyCommands

/// docs/schemas/dinky.json is written by hand; these keep it from drifting away from the code.
struct SchemaTests {
    private static let schema: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/schemas/dinky.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private var definitions: [String: [String: Any]] { Self.schema["definitions"] as! [String: [String: Any]] }

    @Test func `Command pattern lists every command`() throws {
        let pattern = definitions["command"]!["pattern"] as! String
        let regex = try NSRegularExpression(pattern: pattern)
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for doc in Command.all {
            #expect(matches(doc.name), "\(doc.name)")
            #expect(matches(doc.syntax), "\(doc.syntax)")
        }
        for bad in ["", "fly left", "workspaces 3", "layouts", "modes main"] {
            #expect(!matches(bad), "\(bad)")
        }
        // The alternation names exactly the commands, no more.
        let listed = pattern.split(separator: "(")[1].split(separator: ")")[0].split(separator: "|").map(String.init)
        #expect(Set(listed) == Set(Command.all.map(\.name)))
        #expect(listed.count == Command.all.count, "a command is listed twice")
    }

    /// The config's curve names, the layout engine's easings and the schema's enum are the same list.
    @Test func `Animation curves agree`() {
        let configured = Set(AnimationCurve.allCases.map(\.rawValue))
        #expect(configured == Set(Easing.allCases.map(\.rawValue) + ["spring"]))
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let animations = properties["animations"]!["properties"] as! [String: [String: Any]]
        #expect(Set(animations["curve"]!["enum"] as! [String]) == configured)
    }

    @Test func `Resize anchors agree`() {
        let configured = FloatingResizeAnchor.allCases.map(\.rawValue)
        #expect(configured.allSatisfy { ResizeAnchor(rawValue: $0) != nil })
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let floating = properties["floating"]!["properties"] as! [String: [String: Any]]
        #expect(floating["resize-anchor"]!["enum"] as! [String] == configured)
    }

    @Test func `Fullscreen focus changes agree`() {
        let configured = FullscreenFocusChange.allCases.map(\.rawValue)
        #expect(configured.allSatisfy { FullscreenFocus(rawValue: $0) != nil })
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let fullscreen = properties["fullscreen"]!["properties"] as! [String: [String: Any]]
        #expect(fullscreen["focus-change"]!["enum"] as! [String] == configured)
        #expect(fullscreen["scrolling"]!["enum"] as! [String] == FullscreenScrolling.allCases.map(\.rawValue))
    }

    @Test func `Column centrings agree`() {
        let configured = CenterFocusedColumn.allCases.map(\.rawValue)
        #expect(configured.allSatisfy { ColumnCentring(rawValue: $0) != nil })
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let scrolling = properties["scrolling"]!["properties"] as! [String: [String: Any]]
        #expect(scrolling["center-focused-column"]!["enum"] as! [String] == configured)
    }

    @Test func `HUD positions agree`() {
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let hud = properties["hud"]!["properties"] as! [String: [String: Any]]
        #expect(hud["position"]!["enum"] as! [String] == HudPosition.allCases.map(\.rawValue))
    }

    @Test func `Switcher modifiers agree`() {
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let switcher = properties["window-switcher"]!["properties"] as! [String: [String: Any]]
        #expect(switcher["modifier"]!["enum"] as! [String] == SwitcherModifier.allCases.map(\.rawValue))
        let layouts = switcher["layouts"]!["items"] as! [String: Any]
        #expect(layouts["enum"] as! [String] == SwitcherLayoutKind.allCases.map(\.rawValue))
        #expect(switcher["tiles-style"]!["enum"] as! [String] == SwitcherTilesStyle.allCases.map(\.rawValue))
        #expect(switcher["position"]!["enum"] as! [String] == SwitcherPosition.allCases.map(\.rawValue))
        let shared = properties["switcher"]!["properties"] as! [String: [String: Any]]
        #expect(shared["position"]!["enum"] as! [String] == SwitcherPosition.allCases.map(\.rawValue))
        #expect(shared["trigger"]!["enum"] as! [String] == SwitcherTrigger.allCases.map(\.rawValue))
        #expect(switcher["trigger"]!["enum"] as! [String] == SwitcherTrigger.allCases.map(\.rawValue))
    }

    @Test func `Workspace switcher choices agree`() {
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let switcher = properties["workspace-switcher"]!["properties"] as! [String: [String: Any]]
        #expect(switcher["modifier"]!["enum"] as! [String] == SwitcherModifier.allCases.map(\.rawValue))
        #expect(switcher["displays"]!["enum"] as! [String] == WorkspaceSwitcherDisplays.allCases.map(\.rawValue))
        #expect(switcher["thumbnails"]!["enum"] as! [String] == WorkspaceSwitcherThumbnails.allCases.map(\.rawValue))
        #expect(switcher["position"]!["enum"] as! [String] == SwitcherPosition.allCases.map(\.rawValue))
    }

    @Test func `Workspace layouts agree`() {
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        let layouts = LayoutKind.allCases.map(\.rawValue)
        #expect(properties["default-layout"]!["enum"] as! [String] == layouts)
        let workspace = properties["workspace"]!["additionalProperties"] as! [String: Any]
        let keys = workspace["properties"] as! [String: [String: Any]]
        #expect(keys["layout"]!["enum"] as! [String] == layouts)
    }

    @Test func `Rule layouts agree`() {
        let definitions = Self.schema["definitions"] as! [String: [String: Any]]
        #expect(definitions["ruleLayout"]!["enum"] as! [String] == RuleLayout.allCases.map(\.rawValue))
    }

    @Test func `Menu bar icons agree`() {
        let properties = Self.schema["properties"] as! [String: [String: Any]]
        #expect(properties["menu-bar-icon"]!["enum"] as! [String] == MenuBarIcon.allCases.map(\.rawValue))
        #expect(properties["hide-menu-bar-icon"]!["enum"] as! [String] == MenuBarIconHiding.allCases.map(\.rawValue))
    }

    @Test func `Key combo pattern matches every key name`() throws {
        let pattern = definitions["keyCombo"]!["pattern"] as! String
        let regex = try NSRegularExpression(pattern: pattern)
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for name in KeyCombo.keyCodes.keys {
            #expect(matches(name), "\(name)")
            #expect(matches("alt-shift-\(name)"), "\(name)")
        }
        for bad in ["", "alt-", "hyper-a", "alt-hh", "pageUp", "f21", "keypad-", "alt--", "A"] {
            #expect(!matches(bad), "\(bad)")
        }
    }

    /// One value for every key the schema knows, table forms where a key takes a scalar or a table.
    private static let everyKey = """
        start-at-login = false
        workspaces = 4
        default-layout = 'accordion'
        default-tiling = true
        follow-app-activation = false
        float-windows-without-fullscreen = false
        menu-bar-icon = 'text'
        hide-menu-bar-icon = 'always'
        scripting-addition = false
        highlight-color = '#59168b'

        [workspace-to-display]
        1 = 'main'
        2 = ['secondary', 'main']

        [workspace.2]
        tiling = true
        layout = 'fixed'
        columns = 2
        rows = 2
        expand = 'rows'

        [accordion]
        padding = 20
        orientation = 'keep'

        [scrolling]
        column-width = 0.5
        center-focused-column = 'on-overflow'

        [switcher]
        enabled = true
        delay-ms = 150
        trigger = 'double-tap'
        double-tap-ms = 250
        corner-radius = 24
        position = 'center'
        show-titles = true
        letter-keys = true
        letters = 'asdfg'
        highlight-color = 'accent'

        [window-switcher]
        enabled = true
        highlight-color = '#ff000080'
        modifier = 'alt'
        delay-ms = 200
        trigger = 'hold'
        double-tap-ms = 300
        layouts = ['tiles']
        corner-radius = 20
        tiles-style = 'row'
        show-single = false
        show-titles = false
        letter-keys = false
        letters = 'qwerty'
        position = 'top'

        [workspace-switcher]
        enabled = false
        highlight-color = '#00ff00'
        modifier = 'ctrl'
        delay-ms = 250
        trigger = 'double-tap'
        double-tap-ms = 400
        displays = 'pointer'
        show-empty = false
        exclude = [3]
        card-height = 90
        thumbnails = 'icons'
        corner-radius = 18
        position = 'mouse'
        show-titles = false
        letter-keys = true
        letters = 'zxcv'

        [gestures.trackpad]
        enabled = true
        fingers = 4
        distance = 18
        step = 15
        swipe-left = 'workspace-switcher'
        swipe-right = ['window-switcher']
        swipe-up = 'focus up'
        swipe-down = 'focus down'

        [gestures.mouse]
        enabled = true
        fingers = 2
        distance = 8
        step = 6
        swipe-up = 'window-switcher'
        swipe-down = 'workspace-switcher'
        swipe-left = 'focus left'
        swipe-right = 'focus right'

        [gestures.scroll]
        enabled = true
        fingers = 3
        speed = 2

        [floating]
        move-step = 20
        resize-anchor = 'top-left'

        [fullscreen]
        focus-change = 'keep'
        follow-delay-ms = 200
        scrolling = 'over'

        [gaps]
        inner.horizontal = 4
        inner.vertical = 6
        outer.top = 1
        outer.bottom = 2
        outer.left = 3
        outer.right = 4

        [display.main]
        gaps.inner = 2
        gaps.outer.top = 30
        gaps.outer.bottom = 0
        gaps.outer.left = 0
        gaps.outer.right = 0

        [display.secondary]
        gaps.inner.horizontal = 1
        gaps.inner.vertical = 1
        gaps.outer = 8

        [borders]
        enabled = true
        width = 2.5
        active-color = '#ff0000'
        inactive-color = '#00ff0080'
        order = 'above'
        exclude-apps = ['com.apple.finder']
        noop-flash = true
        noop-flash-color = 'accent'
        noop-flash-width = 3.5
        noop-flash-spread = 20
        noop-flash-opacity = 0.5

        [focus-follows-mouse]
        enabled = true
        delay-ms = 50
        accordion-edges = false

        [animations]
        enabled = true
        duration-ms = 100
        damping = 0.9
        curve = 'ease-in-out-expo'

        [drag]
        placeholders = false
        preview-border-color = '#7aa2f7'
        preview-fill-color = '#7aa2f74d'
        preview-border-width = 2.5
        home-outline = false
        mouse-modifier = 'ctrl-cmd'

        [hud]
        enabled = true
        position = 'top'
        duration-ms = 800
        offset = 10
        on-layout-change = true
        on-mode-change = false
        on-workspace-change = false
        on-noop = true

        [modifiers]
        alt = 'left'
        ctrl = 'right'
        cmd = 'both'
        shift = 'both'
        hyper = 'ctrl-alt-cmd'

        [hooks]
        startup = 'exec-and-forget true'
        workspace-changing = ['exec-and-forget true']
        workspace-changed = []
        focus-changed = 'exec-and-forget true'
        mode-changed = 'exec-and-forget true'

        [[rules]]
        app-id = 'com.apple.Safari'
        app-name = 'safari'
        title = 'settings'
        kind = 'dialog'
        disk-image = false
        workspace-layout = ['scrolling', 'tiles']
        workspace = 2
        run = ['layout floating', 'move-window-to-workspace 2']

        [mode.main]
        alt-1 = 'workspace 1'
        alt-r = 'mode resize'

        [mode.main.free]
        alt-shift-h = 'grid 1:2:0:0:1:1'

        [mode.resize]
        esc = ['mode main']
        h = 'resize width -50'
        """

    /// The scalar forms of the top-level gaps.
    private static let scalarGaps = """
        [gaps]
        inner = 5
        outer = 10
        """

    @Test func `Schema and config know every key`() throws {
        #expect(Config.defaultTOML.hasPrefix("#:schema \(Self.schema["$id"] as! String)\n"))
        for fixture in [Self.everyKey, Self.scalarGaps] {
            #expect(throws: Never.self) { try Config.parse(fixture) }
            try check(TOMLTable(source: fixture), Self.schema, at: "")
        }
        try check(TOMLTable(source: Config.defaultTOML), Self.schema, at: "")
        try covers(TOMLTable(source: Self.everyKey), Self.schema, at: "")
    }

    /// Every key in `table` is in the schema, at the same path.
    private func check(_ table: TOMLTable, _ schema: [String: Any], at path: String) {
        let schema = object(schema)
        let known = schema["properties"] as? [String: Any] ?? [:]
        for key in table.keys {
            let here = path.isEmpty ? key : "\(path).\(key)"
            guard let child = known[key] as? [String: Any] ?? pattern(schema, key)
                    ?? schema["additionalProperties"] as? [String: Any] else {
                Issue.record("\(here) is not in the schema")
                continue
            }
            each(table, key, child, at: here, check)
        }
    }

    /// Every key in the schema is in `table`, at the same path, and every open-ended table has an entry.
    private func covers(_ table: TOMLTable, _ schema: [String: Any], at path: String) {
        let schema = object(schema)
        for (key, child) in schema["properties"] as? [String: [String: Any]] ?? [:] {
            let here = path.isEmpty ? key : "\(path).\(key)"
            guard table.contains(key: key) else {
                Issue.record("\(here) is in the schema but not the fixture")
                continue
            }
            each(table, key, child, at: here, covers)
        }
        for key in table.keys {
            if let child = pattern(schema, key) { each(table, key, child, at: "\(path).\(key)", covers) }
        }
        if let child = schema["additionalProperties"] as? [String: Any] {
            #expect(!table.keys.isEmpty, "\(path) has no entries in the fixture")
            for key in table.keys where pattern(schema, key) == nil { each(table, key, child, at: "\(path).\(key)", covers) }
        }
    }

    /// The schema of `key` under a `patternProperties` pattern it matches, if any.
    private func pattern(_ schema: [String: Any], _ key: String) -> [String: Any]? {
        let patterns = schema["patternProperties"] as? [String: [String: Any]] ?? [:]
        return patterns.first { key.range(of: $0.key, options: .regularExpression) != nil }?.value
    }

    /// Calls `walk` on `table[key]` when it is a table, or on each table in it when it is an array of tables.
    private func each(_ table: TOMLTable, _ key: String, _ schema: [String: Any], at path: String,
                      _ walk: (TOMLTable, [String: Any], String) -> Void) {
        if let nested = try? table.table(forKey: key) {
            walk(nested, schema, path)
        } else if let items = object(schema)["items"] as? [String: Any], let array = try? table.array(forKey: key) {
            for i in 0..<array.count {
                if let item = try? array.table(atIndex: i) { walk(item, items, "\(path)[\(i)]") }
            }
        }
    }

    /// The object form of a schema node: follows a `$ref`, and of a `oneOf` of a scalar and a table, takes the table.
    private func object(_ schema: [String: Any]) -> [String: Any] {
        let schema = resolve(schema)
        let options = schema["oneOf"] as? [[String: Any]] ?? []
        return options.first { $0["properties"] != nil } ?? schema
    }

    /// Follows a local `$ref`.
    private func resolve(_ schema: [String: Any]) -> [String: Any] {
        guard let ref = schema["$ref"] as? String, ref.hasPrefix("#/definitions/") else { return schema }
        return definitions[String(ref.dropFirst("#/definitions/".count))]!
    }
}
