import Foundation

/// One `[[rules]]` entry: when a new window matches every condition that is set, run the commands.
/// `app-name` and `title` are case-insensitive regexes found anywhere in the text. `disk-image` is whether the window
/// comes from a mounted disk image, such as a .dmg's Finder window or an installer run from one. `workspace-layout` and
/// `workspace` are about the workspace the window is on when the rule's commands run, see `matches(layout:workspace:)`.
public struct WindowRule: Equatable {
    public var appId: String?
    public var appName: String?
    public var title: String?
    public var kind: WindowKind?
    /// Whether the window comes from a mounted disk image; nil for either.
    public var diskImage: Bool?
    /// The layouts the window's workspace may have; nil for any.
    public var workspaceLayouts: [RuleLayout]?
    /// The numbers the window's workspace may have; nil for any.
    public var workspaces: [Int]?
    public var run: [String] = []

    public init() {}

    init(_ t: Table) throws {
        appId = try t.string("app-id")
        appName = try regex(t, "app-name")
        title = try regex(t, "title")
        kind = try t.choice("kind")
        diskImage = try t.bool("disk-image")
        if let names = try t.stringOrStrings("workspace-layout") {
            workspaceLayouts = try names.map { name in
                guard let layout = RuleLayout(rawValue: name) else {
                    let choices = RuleLayout.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
                    throw ConfigError(path: t.path("workspace-layout"), "'\(name)' is not one of \(choices)")
                }
                return layout
            }
            guard !workspaceLayouts!.isEmpty else { throw ConfigError(path: t.path("workspace-layout"), "can't be empty") }
        }
        if let numbers = try t.intOrInts("workspace") {
            guard !numbers.isEmpty, numbers.allSatisfy({ $0 >= 1 }) else {
                throw ConfigError(path: t.path("workspace"), "expected workspace numbers from 1")
            }
            workspaces = numbers
        }
        guard let run = try t.commands("run") else { throw ConfigError(path: t.path("run"), "missing, every rule needs 'run'") }
        self.run = run
        try t.done()
    }

    /// Whether the rule has a condition on the window's workspace, which is checked as its commands run.
    public var asksWorkspace: Bool { workspaceLayouts != nil || workspaces != nil }

    /// Whether the workspace conditions that are set hold for a window on a workspace laid out by `layout`, numbered
    /// `workspace` (nil for one off the numbered workspaces). `dwindle` and `tiles` are the same layout.
    public func matches(layout: RuleLayout, workspace: Int?) -> Bool {
        let layoutHolds = workspaceLayouts.map { $0.contains { $0.canonical == layout.canonical } } ?? true
        let numberHolds = workspaces.map { numbers in workspace.map(numbers.contains) ?? false } ?? true
        return layoutHolds && numberHolds
    }

    /// Whether every condition that is set holds for this window, its workspace's aside. `diskImage` is only asked
    /// when the rule has the condition, as finding it out reads the file system.
    public func matches(appId: String?, appName: String?, title: String, kind: WindowKind,
                        diskImage: () -> Bool = { false }) -> Bool {
        func search(_ pattern: String?, _ text: String?) -> Bool {
            guard let pattern else { return true }
            return text?.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (self.appId == nil || self.appId == appId) && (self.kind == nil || self.kind == kind)
            && search(self.appName, appName) && search(self.title, title)
            && (self.diskImage == nil || self.diskImage == diskImage())
    }
}

private func regex(_ t: Table, _ key: String) throws -> String? {
    guard let pattern = try t.string(key) else { return nil }
    if (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) == nil {
        throw ConfigError(path: t.path(key), "'\(pattern)' is not a valid regex")
    }
    return pattern
}

public enum WindowKind: String, CaseIterable {
    case normal, dialog, sheet, panel
}

/// A workspace's layout as a rule's `workspace-layout` names it. `free` is a workspace that does not tile, with
/// `layout = 'free'` or `tiling = false`; `floating` is its old name and `dwindle` another name for `tiles`.
public enum RuleLayout: String, CaseIterable {
    case scrolling, tiles, dwindle, accordion, fixed, free, floating

    var canonical: RuleLayout {
        switch self {
        case .dwindle: .tiles
        case .floating: .free
        default: self
        }
    }
}

/// `[mode.<name>]`: key combos mapped to the commands they run, in order. A table in it named for a layout, such as
/// `[mode.main.free]`, binds keys anew on a workspace laid out that way, over the mode's own.
public struct Mode: Equatable {
    public var bindings: [KeyCombo: [String]] = [:]
    /// By layout, `dwindle` as `tiles`, the bindings that take over from `bindings` on a workspace with it.
    public var layouts: [RuleLayout: [KeyCombo: [String]]] = [:]

    public init() {}

    init(_ t: Table, layouts allowed: Bool = true) throws {
        for key in t.keys {
            if t.isTable(key) {
                let names = RuleLayout.allCases.filter { $0 != .floating }.map { "'\($0.rawValue)'" }.joined(separator: ", ")
                guard allowed, let layout = RuleLayout(rawValue: key), layout != .floating else {
                    throw ConfigError(path: t.path(key), allowed ? "'\(key)' is not a layout: \(names)" : "a layout's table can't hold tables")
                }
                guard layouts[layout.canonical] == nil else {
                    throw ConfigError(path: t.path(key), "'\(key)' is the same layout as another table here")
                }
                layouts[layout.canonical] = try Mode(t.table(key)!, layouts: false).bindings
                continue
            }
            let combo: KeyCombo
            do {
                combo = try KeyCombo(key)
            } catch {
                throw ConfigError(path: t.path(key), error.message)
            }
            if bindings[combo] != nil {
                throw ConfigError(path: t.path(key), "'\(combo)' is bound twice")
            }
            bindings[combo] = try t.commands(key)
        }
        try t.done()
    }

    /// The commands bound to `combo` on a workspace laid out by `layout`: its layout's table's, else the mode's.
    public func commands(for combo: KeyCombo, on layout: RuleLayout?) -> [String]? {
        layout.flatMap { layouts[$0.canonical]?[combo] } ?? bindings[combo]
    }

    /// The bindings in force on a workspace laid out by `layout`: the mode's, its layout's table's in their place.
    public func bindings(on layout: RuleLayout?) -> [KeyCombo: [String]] {
        guard let table = layout.flatMap({ layouts[$0.canonical] }) else { return bindings }
        return bindings.merging(table) { $1 }
    }

    /// Every binding's commands, the layouts' tables' too.
    public var allCommands: [[String]] { Array(bindings.values) + layouts.values.flatMap(\.values) }
}
