import Foundation

// The config's `[hooks]`: `workspace-changing` when kex starts or retargets a switch, `workspace-changed`
// when any display's current workspace changes (kex's switches and native ones alike) or a kex switch
// ends without one (gave up, or came back where it started), `focus-changed` when the focused window changes, debounced, `mode-changed` when the binding mode
// changes, with the new mode and the previous one, `display-changed` once the workspaces have been arranged after a
// display connects or disconnects, and `startup` once. Started once the coordinator has read the windows and
// displays, so startup fires nothing but `startup`. Main thread only.
final class Hooks {
    /// The workspace number each display was last seen on, by UUID; "" off the numbered workspaces.
    private var workspaces: [String: String] = [:]
    private var pendingFocus: DispatchWorkItem?
    /// The displays connected when last seen, by UUID.
    private var connected: Set<String> = []
    /// Displays whose kex switch announced `workspace-changing` and has not yet reported `workspace-changed`.
    private var announced: Set<String> = []

    func start() {
        let state = AppState.shared
        for display in state.displays.displays { workspaces[display.uuid] = number(display) }
        connected = Set(state.displays.displays.map(\.uuid))
        state.displays.observe { [weak self] in self?.displaysChanged($0) }
        // Arranging can renumber what a display shows without a Space change.
        state.numbers.observe { [weak self] in self?.displaysChanged(AppState.shared.displays) }
        state.numbers.onArranged = { [weak self] in self?.arranged() }
        SpaceSwitcher.shared.onTarget = { [weak self] uuid, target in self?.switchTargeted(uuid, target) }
        SpaceSwitcher.shared.onGiveUp = { [weak self] uuid in self?.switchEnded(uuid) }
        SpaceSwitcher.shared.onLanded = { [weak self] uuid in self?.switchEnded(uuid) }
        state.coordinator?.onFocusChange = { [weak self] in self?.focusChanged() }
        state.hotkeys.onModeChange = { mode, previous in
            Hud.shared.modeChanged(mode)
            run(AppState.shared.config.hooks.modeChanged, env: ["KEX_MODE": mode, "KEX_PREV_MODE": previous])
        }
        run(state.config.hooks.startup)
    }

    private func displaysChanged(_ model: DisplayModel) {
        let commands = AppState.shared.config.hooks.workspaceChanged
        for (i, display) in model.displays.enumerated() {
            let new = number(display)
            // A display that just appeared has not switched.
            guard let old = workspaces[display.uuid] else {
                workspaces[display.uuid] = new
                continue
            }
            guard old != new else { continue }
            // kex's swipe passes through the Spaces in between; report only where it lands.
            if let target = SpaceSwitcher.shared.target(on: display.uuid), target != display.currentSpaceID { continue }
            workspaces[display.uuid] = new
            announced.remove(display.uuid)
            runWorkspaceHooks(commands, workspace: new, previous: old, display: i)
            Hud.shared.workspaceChanged(on: display, space: display.currentSpaceID)
        }
    }

    /// Reports displays that came or went once an arrangement has run for the displays now present, which waits for
    /// the displays to settle.
    private func arranged() {
        let now = Set(AppState.shared.displays.displays.map(\.uuid))
        guard now != connected else { return }
        let previous = connected.count
        connected = now
        run(AppState.shared.config.hooks.displayChanged, env: ["KEX_DISPLAYS": "\(now.count)", "KEX_PREV_DISPLAYS": "\(previous)"])
    }

    /// Announces where a kex switch is going before it lands, so a bar can show it at once.
    private func switchTargeted(_ uuid: String, _ target: UInt64) {
        let displays = AppState.shared.displays.displays
        guard let i = displays.firstIndex(where: { $0.uuid == uuid }) else { return }
        WorkspaceSwitcher.shared.leaving(space: displays[i].currentSpaceID)
        let workspace = AppState.shared.numbers.label(of: target)
        announced.insert(uuid)
        runWorkspaceHooks(AppState.shared.config.hooks.workspaceChanging, workspace: workspace, previous: number(displays[i]), display: i)
        Hud.shared.workspaceChanged(on: displays[i], space: target)
    }

    /// Every switch that announced `workspace-changing` ends with one `workspace-changed`, naming where the display
    /// is: one that did not land, so what was announced does not stand, and one that landed on the workspace it set
    /// out from, as a burst going there and back does, which no Space change reports.
    private func switchEnded(_ uuid: String) {
        let model = AppState.shared.displays
        // Catching up with the Space change reports it, if there is one to report.
        model.reconcile()
        guard announced.remove(uuid) != nil else { return }
        guard let i = model.displays.firstIndex(where: { $0.uuid == uuid }) else { return }
        let new = number(model.displays[i])
        let old = workspaces[uuid] ?? new
        workspaces[uuid] = new
        runWorkspaceHooks(AppState.shared.config.hooks.workspaceChanged, workspace: new, previous: old, display: i)
        Hud.shared.workspaceChanged(on: model.displays[i], space: model.displays[i].currentSpaceID)
    }

    /// Runs workspace hooks with the numbers `exec-and-forget` passes on; `display` is 0-based.
    private func runWorkspaceHooks(_ commands: [String], workspace: String, previous: String, display: Int) {
        run(commands, env: ["KEX_WORKSPACE": workspace, "KEX_PREV_WORKSPACE": previous, "KEX_DISPLAY": "\(display + 1)"])
    }

    private func focusChanged() {
        pendingFocus?.cancel()
        let work = DispatchWorkItem { run(AppState.shared.config.hooks.focusChanged) }
        pendingFocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func number(_ display: Display) -> String {
        AppState.shared.numbers.label(of: display.currentSpaceID)
    }
}

/// Runs kex command strings through the dispatcher, logging failures. `env` reaches `exec-and-forget`.
private func run(_ commands: [String], env: [String: String] = [:]) {
    for command in commands {
        let reply = Dispatcher.run(command, env: env)
        if !reply.ok { fputs("hook \(command): \(reply.text)\n", stderr) }
    }
}

/// Starts a process without waiting for it. Its output goes to kex's own stdout and stderr, the log.
/// kex's own directory and Homebrew's go first on PATH, since apps started from Finder lack them, so scripts
/// can call `kex`.
func exec(_ argv: [String], env: [String: String] = [:]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: argv[0])
    process.arguments = Array(argv.dropFirst())
    var environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
    let own = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
    environment["PATH"] = own + ":/opt/homebrew/bin:/opt/homebrew/sbin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        fputs("exec \(argv[0]): \(error.localizedDescription)\n", stderr)
    }
}
