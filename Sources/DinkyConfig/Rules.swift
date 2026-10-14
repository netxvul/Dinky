import Foundation

/// One `[[rules]]` entry: when a new window matches every condition that is set, run the commands.
/// `app-name` and `title` are case-insensitive regexes found anywhere in the text. `workspace-layout` and
/// `workspace` are about the workspace the window is on when the rule's commands run, see `matches(layout:workspace:)`.
public struct WindowRule: Equatable {
    public var appId: String?
    public var appName: String?
    public var title: String?
    public var kind: WindowKind?
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

    /// Whether every condition that is set holds for this window, its workspace's aside.
    public func matches(appId: String?, appName: String?, title: String, kind: WindowKind) -> Bool {
        func search(_ pattern: String?, _ text: String?) -> Bool {
            guard let pattern else { return true }
            return text?.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (self.appId == nil || self.appId == appId) && (self.kind == nil || self.kind == kind)
            && search(self.appName, appName) && search(self.title, title)
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

/// A workspace's layout as a rule's `workspace-layout` names it. `floating` is a workspace that does not tile, with
/// `tiling = false` or `float = true`; `dwindle` is another name for `tiles`.
public enum RuleLayout: String, CaseIterable {
    case scrolling, tiles, dwindle, accordion, fixed, floating

    var canonical: RuleLayout { self == .dwindle ? .tiles : self }
}

/// `[mode.<name>]`: key combos mapped to the commands they run, in order.
public struct Mode: Equatable {
    public var bindings: [KeyCombo: [String]] = [:]

    public init() {}

    init(_ t: Table) throws {
        for key in t.keys {
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
}
