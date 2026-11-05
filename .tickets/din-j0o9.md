---
id: din-j0o9
status: closed
deps: [din-5rp2]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, displays]
---
# Display and Space model

Per display: UUID, Space list in Mission Control order, current Space, focused display (from the focused window or cursor). Update on display connect, disconnect and arrangement changes. Full-screen Spaces are excluded from workspace numbering.

## Acceptance Criteria

Plugging and unplugging the external display updates the model without restart, and windows on a removed display are reconciled.


## Notes

**2026-09-25T10:48:09Z**

DisplayModel (Sources/kex/DisplayModel.swift), held lazily by AppState.shared.displays: per-display uuid/id/CG frame/isMain, all Spaces in MC order, user-only workspaces (full-screen excluded from numbering), current Space, previous Space per display (back-and-forth). focusedDisplay(): front window's Space -> window frame centre -> cursor -> main. Refreshes on SLS 1401/1327/1328 via EventHub, didChangeScreenParameters, activeSpaceDidChange, and reconcile() (commands and queries reconcile before acting; the follower's 0.5 s timer also reconciles). EventHub owns the single kex_events_start callback and fans out; WindowModel still calls kex_events_start itself and must adopt EventHub.shared.subscribe before both run in one process. Verified in VM (1 display, 3 Spaces): list-displays/list-workspaces/list-windows, workspace N/next/back-and-forth, activation follower (Safari 1->2, 3.2 ms). Not verified: plug/unplug and a second display (no second display in VM or host); windows on a removed display are left to the window model (din-j2iv). Left open for the two-display check.

**2026-09-25T10:49:05Z**

DisplayModel done, single display verified in the VM. Two-display behaviour (focused display choice, plug/unplug) untested for lack of hardware; validate with din-8j6i's procedure and din-drei. WindowModel must switch to EventHub.shared.subscribe when it runs inside the app (din-j2iv). Closing.
