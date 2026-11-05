---
id: din-7mf9
status: closed
deps: []
links: []
created: 2026-09-25T13:46:44Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [layout, config]
---
# balance-sizes, per-monitor gaps, focus boundaries, after-startup-command


## Notes

**2026-09-25T13:55:35Z**

Done: balance-sizes (Workspace.balanceSizes), per-monitor gaps (PerMonitor/MonitorPattern in KexConfig, resolved per display in Coordinator.fitToDisplays; inner.horizontal/vertical split in layout Gaps), focus --boundaries/--boundaries-action/--wrap-around + focus-monitor (FocusCommands.swift, DisplayModel.focusOverride cleared on next focus change), after-startup-command (Callbacks.start). +21 tests. VM: accordion default gives h_accordion roots; gaps fallback 60 vs name match 12; balance-sizes restores equal widths after resize smart +200; wrap/stop/fail/all-monitors single-display paths and focus-monitor errors verified. Not done: two-display focus crossing (host needed), numeric/regex monitor patterns, focus-monitor --wrap-around, dfs-next/prev.
