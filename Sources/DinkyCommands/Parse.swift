import DinkyLayout

/// A command string that does not parse. `description` names the string and the accepted form.
public struct CommandError: Error, Equatable, CustomStringConvertible {
    public let input: String
    public let message: String

    public var description: String { message }
}

extension Command {
    /// Parses a command string such as `workspace 3`, `move-window-to-workspace 3 --follow` or `focus left`.
    public static func parse(_ string: String) throws(CommandError) -> Command {
        let words = words(string)
        guard let name = words.first else {
            throw CommandError(input: string, message: "empty command")
        }
        guard let doc = all.first(where: { $0.name == name }) else {
            let names = all.map(\.name).joined(separator: ", ")
            throw CommandError(input: string, message: "unknown command '\(string)', expected one of: \(names)")
        }
        if name == "exec-and-forget" {
            let shell = string.drop(while: \.isWhitespace).dropFirst(name.count).drop(while: \.isWhitespace)
            guard !shell.isEmpty else { throw CommandError(input: string, message: "can't parse '\(string)', expected '\(doc.syntax)'") }
            return .execAndForget(String(shell))
        }
        let parsed: Command?
        do {
            parsed = try parse(name, Array(words.dropFirst()))
        } catch {
            throw CommandError(input: string, message: "can't parse '\(string)': \(error.message)")
        }
        guard let command = parsed else {
            throw CommandError(input: string, message: "can't parse '\(string)', expected '\(doc.syntax)'")
        }
        return command
    }

    /// Nil for arguments that don't fit; `focus` and the list-* queries throw a message naming the problem.
    private static func parse(_ name: String, _ args: [String]) throws(CommandError) -> Command? {
        let none = args.isEmpty
        let one = args.count == 1 ? args[0] : nil
        switch name {
        case "workspace":
            return one.flatMap(workspaceTarget).map { .workspace($0) }
        case "workspace-back-and-forth":
            return none ? .workspaceBackAndForth : nil
        case "move-window-to-workspace":
            let (rest, follow) = followFlag(args)
            guard rest.count == 1, let target = workspaceTarget(rest[0]) else { return nil }
            return .moveWindowToWorkspace(target, follow: follow)
        case "move-window-to-display":
            let (rest, follow) = followFlag(args)
            guard rest.count == 1, let target = DisplayTarget(rawValue: rest[0]) else { return nil }
            return .moveWindowToDisplay(target, follow: follow)
        case "focus":
            return try focus(args)
        case "focus-monitor":
            if let n = one.flatMap({ Int($0) }) { return n >= 1 ? .focusMonitorNumber(n) : nil }
            return one.flatMap(MonitorTarget.init(rawValue:)).map { .focusMonitor($0) }
        case "move":
            let (rest, floatingOnly) = flag("--floating-only", in: args)
            guard (1...2).contains(rest.count), let direction = Direction(rest[0]) else { return nil }
            guard rest.count == 2 else { return .move(direction, floatingOnly: floatingOnly) }
            guard rest[1].allSatisfy({ $0.isASCII && $0.isNumber }), let points = Int(rest[1]), (1...10_000).contains(points)
            else { return nil }
            return .move(direction, points: points, floatingOnly: floatingOnly)
        case "join-with":
            return one.flatMap(Direction.init).map { .joinWith($0) }
        case "resize":
            let (rest, floatingOnly) = flag("--floating-only", in: args)
            guard rest.count == 2, let dimension = ResizeDimension(rawValue: rest[0]),
                  rest[1].hasPrefix("+") || rest[1].hasPrefix("-"), let delta = Int(rest[1]) else { return nil }
            return .resize(dimension, by: delta, floatingOnly: floatingOnly)
        case "layout":
            let layouts = args.compactMap(LayoutName.init(rawValue:))
            guard !none, layouts.count == args.count else { return nil }
            return .layout(layouts)
        case "fullscreen":
            return none ? .fullscreen : nil
        case "grid":
            let rest = args.filter { $0 != "--toggle" }
            guard rest.count == 1, args.count - rest.count <= 1 else { return nil }
            return try grid(rest[0]).map { .grid($0, toggle: rest.count < args.count) }
        case "cycle-size":
            let percents = args.compactMap(percent)
            guard !none, percents.count == args.count else { return nil }
            return .cycleSize(percents)
        case "flatten-workspace-tree":
            return none ? .flattenWorkspaceTree : nil
        case "balance-sizes":
            return none ? .balanceSizes : nil
        case "rotate":
            return one.flatMap { Int($0) }.flatMap(Rotation.init(rawValue:)).map { .rotate($0) }
        case "mirror":
            return one.flatMap(MirrorAxis.init(rawValue:)).map { .mirror($0) }
        case "retile":
            return none ? .retile : nil
        case "window-switcher":
            return none ? .windowSwitcher : nil
        case "workspace-switcher":
            return none ? .workspaceSwitcher : nil
        case "clear-minimum-sizes":
            return none ? .clearMinimumSizes : nil
        case "mode":
            return one.map { .mode($0) }
        case "reload-config":
            return none ? .reloadConfig : nil
        case "enable":
            return one.flatMap(Toggle.init(rawValue:)).map { .enable($0) }
        case "list-windows":
            return .listWindows(try WindowQuery(parsing: args))
        case "list-workspaces":
            return .listWorkspaces(try WorkspaceQuery(parsing: args))
        case "list-monitors", "list-displays":
            return .listMonitors(try MonitorQuery(parsing: args))
        case "list-modes":
            return none ? .listModes(current: false) : one == "--current" ? .listModes(current: true) : nil
        case "debug-state":
            return none ? .debugState : nil
        default:
            return nil
        }
    }

    /// Splits a command line into words at whitespace. Single or double quotes keep spaces inside a word,
    /// as in `list-windows --format '%{app-name} | %{window-title}'`.
    static func words(_ line: String) -> [String] {
        var words: [String] = [], word = "", inWord = false
        var quote: Character?
        for c in line {
            if let q = quote {
                if c == q { quote = nil } else { word.append(c) }
            } else if c == "'" || c == "\"" {
                quote = c
                inWord = true
            } else if c.isWhitespace {
                if inWord { words.append(word) }
                (word, inWord) = ("", false)
            } else {
                word.append(c)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }

    /// The command line for CLI arguments, quoting words with spaces or quotes so `words` splits it back
    /// the same. `exec-and-forget` is shell text and is passed as written.
    public static func line(_ args: [String]) -> String {
        guard args.first != "exec-and-forget" else { return args.joined(separator: " ") }
        return args.map { word in
            guard word.isEmpty || word.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" }) else { return word }
            return word.contains("'") ? "\"\(word)\"" : "'\(word)'"
        }.joined(separator: " ")
    }

    private static func workspaceTarget(_ word: String) -> WorkspaceTarget? {
        switch word {
        case "prev": return .prev
        case "next": return .next
        case "recent": return .recent
        default:
            guard let n = Int(word), n >= 1 else { return nil }
            return .number(n)
        }
    }

    /// `focus <direction>` with AeroSpace's `--boundaries`, `--boundaries-action` and `--wrap-around`, in any order.
    private static func focus(_ args: [String]) throws(CommandError) -> Command? {
        var rest = args[...], direction: Direction?
        var boundaries = FocusBoundaries.workspace, action = BoundariesAction.stop
        while let word = rest.popFirst() {
            switch word {
            case "--boundaries":
                guard let value = rest.popFirst().flatMap(FocusBoundaries.init(rawValue:)) else { return nil }
                boundaries = value
            case "--boundaries-action":
                guard let value = rest.popFirst().flatMap(BoundariesAction.init(rawValue:)) else { return nil }
                action = value
            case "--wrap-around":
                action = .wrapAroundTheWorkspace
            default:
                guard direction == nil, let value = Direction(word) else { return nil }
                direction = value
            }
        }
        guard let direction else { return nil }
        if boundaries == .workspace, action == .wrapAroundAllMonitors {
            throw CommandError(input: "", message: "wrap-around-all-monitors needs --boundaries all-monitors-outer-frame")
        }
        return .focus(direction, boundaries: boundaries, action: action)
    }

    /// `rows:columns:x:y:width:height`, six whole numbers. Nil when it is not that shape; throws when it is but the
    /// span does not fit the grid.
    private static func grid(_ word: String) throws(CommandError) -> GridPlacement? {
        let n = word.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard n.count == 6, word.split(separator: ":", omittingEmptySubsequences: false).count == 6 else { return nil }
        guard let placement = GridPlacement(rows: n[0], columns: n[1], x: n[2], y: n[3], width: n[4], height: n[5]) else {
            throw CommandError(input: "", message: "the grid needs at least one row and column, and x + width and "
                + "y + height must fit in its columns and rows")
        }
        return placement
    }

    /// A whole percentage from 1 to 100, written with or without `%`.
    private static func percent(_ word: String) -> Int? {
        guard let n = Int(word.hasSuffix("%") ? String(word.dropLast()) : word), (1...100).contains(n) else { return nil }
        return n
    }

    private static func followFlag(_ args: [String]) -> (rest: [String], follow: Bool) {
        (args.filter { $0 != "--follow" }, args.contains("--follow"))
    }

    /// The arguments without `name`, and whether it was there. Given twice, it is left in to fail the parse.
    private static func flag(_ name: String, in args: [String]) -> (rest: [String], present: Bool) {
        guard args.filter({ $0 == name }).count == 1 else { return (args, false) }
        return (args.filter { $0 != name }, true)
    }
}
