---
id: din-cc9k
status: closed
deps: [din-kqko, din-5rp2]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout]
---
# Frame applier with gaps, per-app coalescing and readback

Turn tree rectangles into AX writes: gaps applied, AXEnhancedUserInterface cleared, size-position-size, one queue per app so a slow app blocks only itself, newest frame wins, readback after settle, bounded correction for windows that refuse a size (no retry loops).

## Acceptance Criteria

Five windows including Safari and a terminal land where computed or report a bounded DIFF once. A hung app does not delay the others.


## Notes

**2026-09-25T10:47:36Z**

FrameScheduler (KexLayout, pure: queue per pid, newest wins, one retry, minimumSizes) + Layout.raises(current:) + FrameApplier (kex, AX side, 1 s messaging timeout, AXEnhancedUserInterface cleared once per app). kex tile now builds a Workspace (--gap N, --accordion). VM: TextEdit x3 OK; Safari refuses below 574x240 (DIFF retried once, minimum recorded); Terminal snaps to grid (247x154 for 246x160, DIFF retried once, no minimum since it shrank); second run skips everything in place. Terminal SIGSTOPped: others land, Terminal reports unreadable after ~4 s of timeouts on its own queue. Limitation: AXRaise without activation does not lift a window above another app's active window, so cross-app accordion stacking needs activation or a private ordering call.
