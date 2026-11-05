---
id: din-kqko
status: closed
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, tests]
---
# Layout tree model with pure tests

Per-Space tree: containers with orientation and ratios, leaves are windows. Insert beside the focused leaf by splitting its rectangle along the longer side, 50/50, deterministic tie-break. Remove collapses redundant containers keeping order. Flatten. Accordion is a container mode. Fullscreen is a per-Space overlay that hides the tree without changing it. Pure Swift, no AppKit, unit tests for every operation.

## Acceptance Criteria

Tests cover insert axes and ties, stable topology on resize, removal, flatten, accordion geometry with padding, fullscreen, and gaps arithmetic.


## Notes

**2026-09-25T10:04:57Z**

Layout engine in Sources/KexLayout (Tree, Geometry, Workspace, Commands), 61 XCTests. Decisions: Workspace is a value type holding bounds/gaps/accordionPadding so layout() is pure and insert/resize use gap-free tree geometry (not stale frames). Neighbour lookup uses a virtual layout where accordions are split like tiles (real accordion frames overlap, so geometry alone picks the wrong child); ties go to the most recently focused window. Containers track an active (MRU) child for accordion stacking. Tile edges are rounded to whole points. Accordion parents always take new windows as siblings. insert focuses the new window. Minimum resize ratio 0.1. move/join follow AeroSpace semantics. Fullscreen keeps other frames, just puts the window first in order.
