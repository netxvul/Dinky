---
id: din-i1b8
status: closed
deps: [din-j2iv]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 2
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, edge-cases]
---
# Native tab groups, sheets and dialogs

Windows in a native tab group are one tile; inactive tabs never become tiles. Sheets and dialogs are attached to their parent for focus and moves. Minimized windows leave the tree and re-enter on unminimize.

## Acceptance Criteria

Safari with three tabs in one window is one tile. Minimizing and restoring a window re-tiles both times.


## Notes

**2026-09-25T11:45:50Z**

Tabs: Safari tabs are one WindowServer window (one tile, tab switch writes nothing). AppKit tab groups (TextEdit Merge All Windows) show a new tab by giving it the group's frame and ordering it in, then ordering the old one out; inactive tabs read as minimized with no Space. Coordinator.track now lets a newly shown window of the same app with a tile's exact frame take that tile (Workspace.replace, tested). VM: tab next/prev, + new tab and Cmd-W close produced no frame writes to the neighbour. Minimize/unminimize via AXMinimized: one layout pass each way, re-enters beside the focused tile. Sheets: never tracked (child windows); kex focus onto a window with a Save sheet put keystrokes in the sheet, move right carried the sheet along.
