---
id: din-xfjb
status: closed
deps: [din-5sdy]
links: []
created: 2026-09-25T09:32:54Z
type: chore
priority: 3
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [cleanup]
---
# Remove spike-only switch paths and CLI subcommands

Drop the Tuna and bridged set-current-Space paths, the keys and number experiments, and the velocity override once the CLI over the socket exists. Keep RESULTS.md as the record.

## Acceptance Criteria

switch.m contains only the mimi path; the spike subcommands are gone.


## Notes

**2026-09-25T11:32:12Z**

switch.m reduced to the mimi swipe with cursor warp; Tuna, bridged, keys, number paths and KEX_SWIPE_VELOCITY gone. KexSwitchPath kept as single-case enum (Mimi) with unused path/targetSpaceID params because SpaceSwitching.swift calls it. Removed CLI: ls, switch, move <wid>, focus <wid>, tile, hotkeys, spaces, events, borders. Added kex debug events|windows. help lists app/recover/debug. waitUntil moved to Wait.swift. vm-setup.sh no longer creates Spaces via kex ls (app ensures workspace count).
