---
id: din-ep10
status: closed
deps: []
links: []
created: 2026-09-25T12:48:00Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [cli, config]
---
# AeroSpace-compatible list queries and callbacks for SketchyBar


## Notes

**2026-09-25T12:49:47Z**

Plan: query structs + flag parsing and pure Format rendering in KexCommands; quote-aware command tokenizer so --format with spaces survives the CLI; exec-and-forget; Callbacks.swift in the app wiring DisplayModel observers, Coordinator focus change (50 ms debounce) and HotkeyEngine mode change.

**2026-09-25T12:56:33Z**

Done. VM (192.168.64.62): list-workspaces --all -> 1..6, --focused -> 1, --empty/--visible filters, list-windows --workspace 1/--all/--focused, --format %{window-layout} gave h_accordion/h_tiles/floating/fullscreen after layout commands, list-monitors -> '1 | Apple Virtual'. exec-on-workspace-change fired for kex switches (one line per switch: a 1->4 swipe is reported once, intermediate Spaces skipped while SpaceSwitcher is in flight) and for native ctrl-arrow (tagged CGEvent so kex's tap passes it through). on-mode-changed fired on mode service / mode main; on-focus-changed fired after focus left/right. Known: windows on Spaces kex has not shown since start report floating (unclassified).
