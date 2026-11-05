---
id: din-g6bk
status: closed
deps: [din-jf9s]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, commands]
---
# Command dispatcher and vocabulary

Parse command strings like 'workspace 3', 'move-window-to-workspace 3 --follow', 'layout accordion', 'focus left', 'mode service' into typed commands and run them against the coordinator. One vocabulary for bindings, CLI and menu. Command list documented in one place.

## Acceptance Criteria

Every command in the PLAN.md config draft parses; unknown commands fail with a message naming the offending string.


## Notes

**2026-09-25T10:25:03Z**

Also: wire KexConfig into the app (load ~/.config/kex/kex.toml, ConfigWatcher, keep previous config on error and show it in the menu bar and log, reload-config command, start-at-login from config replacing the UserDefaults TODO in Onboarding.swift).

**2026-09-25T10:38:42Z**

Done. New target KexCommands (depends on KexLayout for Direction): Command enum, Command.parse (CommandError names the string and the accepted syntax), Command.all reference (syntax + description). 14 tests incl. every default-config binding. App: Dispatcher.swift (switch over Command -> Reply), AppState.swift (config, HotkeyEngine, enabled, workspace history), Queries.swift. Config: loads ~/.config/kex/kex.toml (writes default if missing), ConfigWatcher when auto-reload-config, errors keep previous config + stderr + first menu item. start-at-login from config (bundle only). follow-app-activation -> followEnabled. HotkeyEngine wired: bindings from config.modes, reloaded on config change, mode <name> -> setMode, enable -> engine.enabled; Hotkeys.swift shim removed. Menu items carry command strings and run through Dispatcher. Not yet (reply error 'not yet'): move, join-with, resize, fullscreen, flatten-workspace-tree, layout other than 'layout tiles' (spike runTile). focus <dir> is a geometric nearest-window pick on the current Space; move-window-to-display places the window via AX on the other display, untested with 2 displays. Workspaces act on the main display (din-mlu6).
