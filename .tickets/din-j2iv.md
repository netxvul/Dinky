---
id: din-j2iv
status: closed
deps: [din-cc9k, din-j0o9]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, events]
---
# Automatic tiling driven by events

On window create: classify (normal, transient, floating rule), insert normal windows into the tree of their Space, apply. On destroy or move to another Space: remove and re-apply. On external Space change or display change: reconcile. Transients (sheets, dialogs, utility panels, non-resizable windows) float.

## Acceptance Criteria

Opening three windows tiles them as they appear. Closing one re-tiles. A Save sheet never becomes a tile. Moving a window with the native drag between Spaces is reconciled without dragging it back.


## Notes

**2026-09-25T10:49:05Z**

This is the integration ticket: wire WindowModel (via EventHub.shared.subscribe), DisplayModel, BorderManager and FrameApplier into the app through AppState, then the automatic tiling loop on top. Feed FrameApplier.minimumSizes back where cheap. Accordion/fullscreen stacking of the focused child must use activate plus raise (see din-yq3m note).

**2026-09-25T10:58:46Z**

Coordinator.swift (serialized owner: one Workspace per (display UUID, Space id), placements per window, dirty trees flushed to FrameApplier when on screen) + WindowRules.swift (rule matching). WindowModel now subscribes via EventHub. AppState.startCoordinator from App.start after ensureWorkspaceCount; config reload -> Coordinator.update (gaps, padding, BorderManager); enable off stops applying, on reconciles. Classification: first time a window is isNormal and on a visible Space (AX lists current-Space windows only): float unless AX subrole AXStandardWindow, kAXSize settable, and no matching on-window-detected rule running 'layout floating'; AX element missing -> retry 0.2s x5 then float. Sheets with a parent never enter the model. Minimized or on a full-screen Space -> leaves the tree. Focus followed with kex_border_focused_window on front-app/reorder/create. Overlapping layouts activate+AXRaise the focused child when it is on the focused Space. minimumSizes only recorded by FrameApplier (engine has no ratio hook). Dispatcher: layout tiles|accordion, move, join-with, resize smart, fullscreen, flatten-workspace-tree, new 'retile' command; kex tile sends retile when the app runs. VM: startup tiles existing windows; TextEdit c, d, Notes tiled on arrival; Calculator floats (non-resizable); quitting Notes re-tiles; spike move of a window to Space 2 re-tiled both Spaces and window stays on 2; Export-as-PDF save panel stays native; per-Space trees verified on 1/2/3; accordion peeks by padding; enable off/on reconciles. Not tested: real Mission Control drag, minimize, multi-display.
