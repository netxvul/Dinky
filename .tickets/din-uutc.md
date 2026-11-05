---
id: din-uutc
status: closed
deps: [din-j2iv, din-g6bk]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, commands]
---
# Directional focus, move, swap and join-with

focus left|right|up|down by geometry within the Space, across containers. move <dir> swaps with the neighbour or moves out of the container at the edge. join-with <dir> puts the focused window into the neighbour's container, creating one if needed. Focus uses AX raise plus activate (proven in the spike).

## Acceptance Criteria

In a three-window layout every direction from every window does what i3 would do. Focus never switches Spaces.


## Notes

**2026-09-25T11:28:40Z**

Wired and verified in the VM (kex-cmds build, ws4, three TextEdit windows in h[A v[B C]]). focus <dir> goes through Workspace.neighbor on the focused window's tree (floating windows fall back to the on-screen geometry search), focuses with AX raise + activate, and holds the tree to the target for 0.5 s so stale focus events cannot pull it back (that race undid focus in a 2-child accordion). focusWindow also tells the activation follower the activation is kex's own: without it, activating TextEdit from another app followed to TextEdit's window on another Space. Verified: 12/12 focus cases (every window, every direction), cross-app focus TextEdit/Notes/Preview, Space never changed. move: 12/12 cases match i3 (swap in column, leave column at the edge, into column after its most recent child, wrap root at the workspace edge e.g. v[B h[A C]]); join-with: 12/12 as designed (A right -> v[A B C], B left -> h[v[A B] C], B down -> h[A B C], edges no-op). Engine table test MoveEveryDirectionTests added. No swap command in the vocabulary (move swaps).
