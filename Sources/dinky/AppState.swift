import DinkyConfig
import Foundation

// State that outlives a single command: the current config, the hotkey engine, whether dinky is
// enabled, the display model and the coordinator that tiles. Main thread only.
final class AppState {
    static let shared = AppState()

    /// Runs each binding's commands in order through the dispatcher. Started by the app once
    /// Accessibility is granted.
    let hotkeys = HotkeyEngine { commands in
        // A binding that uses a switcher's modifier is the modifier at work for something else, unless it is the
        // switcher's own command, which steps its pick.
        if !commands.contains("window-switcher") { WindowSwitcher.shared.dismiss() }
        if !commands.contains("workspace-switcher") { WorkspaceSwitcher.shared.dismiss() }
        for command in commands {
            let reply = Dispatcher.run(command)
            if !reply.ok { fputs("\(command): \(reply.text)\n", stderr) }
        }
    }

    /// The config in effect. A config that fails to load leaves the previous one here.
    private(set) var config = Config.default
    /// The last load error, shown first in the status item's menu. Nil once a load succeeds.
    private(set) var configError: ConfigError?
    private(set) var enabled = true
    /// Displays and their Spaces, started on first use.
    private(set) lazy var displays: DisplayModel = {
        let model = DisplayModel()
        model.start()
        return model
    }()
    /// Which Space each workspace is, arranged by the app once tiling runs.
    let numbers = WorkspaceNumbers()
    /// Tiling and borders, started by the app once Accessibility is granted.
    private(set) var coordinator: Coordinator?
    /// The journal of original frames that disable, quit and `dinky recover` restore.
    let recovery = Recovery()
    private let hooks = Hooks()
    private let hoverFocus = HoverFocus()
    private var watcher: ConfigWatcher?

    private init() {
        hotkeys.load(modes: config.modes, sides: config.modifiers)
        hotkeys.yields = { WindowSwitcher.shared.takes($0) || WorkspaceSwitcher.shared.takes($0) }
    }

    /// Loads `~/.config/dinky/dinky.toml`, writing the default config there first if it is missing.
    @discardableResult
    func loadConfig() -> ConfigError? {
        let url = Config.userConfigURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? (Config.defaultTOML + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        apply(Result { () throws(ConfigError) in try Config.load(from: url) })
        if watcher == nil {
            watcher = ConfigWatcher(url: url) { [weak self] in self?.apply($0) }
        }
        return configError
    }

    func startCoordinator() {
        guard coordinator == nil else { return }
        let coordinator = Coordinator(displays: displays, config: config)
        self.coordinator = coordinator
        coordinator.start()
        // Once the windows are known, so each workspace's windows move with it, and before the hooks, which
        // report workspace numbers.
        numbers.arrange()
        hooks.start()
        recovery.start(model: coordinator.model, applier: coordinator.applier)
        hoverFocus.update(config: config.focusFollowsMouse)
        WindowSwitcher.shared.update(config: config)
        WorkspaceSwitcher.shared.update(config: config)
    }

    /// The one enable transition. Off stops tiling and puts every window back where it was before dinky
    /// touched it, and returns the restore's summary. This is the emergency path: `dinky enable off`, the
    /// menu's Enabled item, `dinky recover` and quitting all come through here.
    @discardableResult
    func setEnabled(_ on: Bool) -> String {
        if on { recovery.resume() }
        enabled = on
        propagateEnabled()
        return on ? "" : recovery.restore()
    }

    /// `dinky recover` and the menu's restore item: after a crash, stops tiling and restores every
    /// journaled window, including those the crashed session left tiled.
    func recover() -> Reply {
        guard recovery.recoverable > 0 else { return .error("no windows from a previous session to restore") }
        return .ok(setEnabled(false) + "; dinky is disabled, `dinky enable on` tiles again")
    }

    /// Quitting stops tiling and puts every window back.
    func quit() {
        setEnabled(false)
    }

    private func apply(_ result: Result<Config, ConfigError>) {
        switch result {
        case .success(let config):
            self.config = config
            configError = nil
            hotkeys.load(modes: config.modes, sides: config.modifiers)
            // At launch the app arranges the workspaces itself, once the coordinator has started.
            if let coordinator {
                coordinator.update(config: config)
                numbers.arrange()
                hoverFocus.update(config: config.focusFollowsMouse)
                WindowSwitcher.shared.update(config: config)
                WorkspaceSwitcher.shared.update(config: config)
            }
            applyStartAtLogin(config.startAtLogin)
        case .failure(let error):
            configError = error
            fputs("config: \(error), keeping the previous config\n", stderr)
        }
        // The new hotkeys and a reload while disabled stay disabled.
        propagateEnabled()
    }

    /// Hands `enabled` to the parts that keep their own copy. The activation follower and hover focus read it
    /// when they decide.
    private func propagateEnabled() {
        hotkeys.enabled = enabled
        coordinator?.enabled = enabled
    }
}
