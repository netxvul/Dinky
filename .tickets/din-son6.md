---
id: din-son6
status: closed
deps: [din-19v3, din-j0o9]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces]
---
# Ensure workspace count on start and reload

For each display, if it has fewer user Spaces than config workspaces, create the missing ones. Never remove. Report in the log and menu bar if creation is unavailable.

## Acceptance Criteria

With workspaces = 5 and a fresh display with one Space, kex creates four. Extra Spaces are left alone.


## Notes

**2026-09-25T10:55:20Z**

ensureWorkspaceCount() (Sources/kex/WorkspaceCount.swift) runs from App.start(): per display, creates missing user Spaces with kex_create_space, waits up to 2 s for each to appear in DisplayModel, never removes, logs what it created; a 0 result is logged once and that display is skipped. VM: workspaces = 5 on a 3-Space display -> 'display 1 had 3, created 2 [31, 32]', list-workspaces and Mission Control show Desktop 1-5. Not done: config reload does not re-run it (AppState exposes no config-change hook; reload-config and the watcher live in AppState/Dispatcher cases owned elsewhere) and no menu-bar notice when creation is unavailable (App.swift not mine). Both are one-line calls to ensureWorkspaceCount() / a log check once AppState has a hook.
