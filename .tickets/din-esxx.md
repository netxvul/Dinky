---
id: din-esxx
status: closed
deps: []
links: []
created: 2026-09-26T21:52:51Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [layout, mouse]
---
# Resize drags set the window size and the tree follows


## Notes

**2026-09-26T22:05:57Z**

Workspace.resize(_:to:moving:) in Sources/KexLayout/ResizeTo.swift: per axis, nearest tiles container along the axis with a neighbour on the moved side takes the delta from that neighbour (both neighbours split it when the edge is unknown), clamped by minimumRatio and minimum sizes; accordions resize as a unit, fullscreen does nothing. Drag.swift: on release, one edge moved per axis = resize, both edges moved on any axis = move (swap or snap back). 12 tests in ResizeToTests. VM: edge, corner and move drags verified with a synthetic button held on the dragged window's title bar (/tmp/btnat) plus debug ax-frame; pressing on another window's resize edge (/tmp/btn at 600,700) made some runs flaky.
