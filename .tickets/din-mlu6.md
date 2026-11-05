---
id: din-mlu6
status: closed
deps: [din-j0o9, din-g6bk]
links: [din-8j6i]
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, commands]
---
# Workspace commands on the focused display

workspace N, prev, next, workspace-back-and-forth, all acting on the focused display with the mimi swipe. Coalesce rapid requests to the newest target and confirm by observed Space change, not by submission.

## Acceptance Criteria

Ten alternating switches settle on the last request with no late jumps, on both displays.


## Notes

**2026-09-25T10:25:03Z**

No longer blocked on din-8j6i: cursor-warp display targeting is implemented in switch.m; the two-display validation stays with din-8j6i and din-drei.

**2026-09-25T10:55:20Z**

SpaceSwitcher (SpaceSwitching.swift): one flight per display. A request during a flight only replaces its target; when the posted swipe is observed to land (kex_current_space_id polled every 10 ms) the switcher either finishes or swipes on to the newest target from the observed Space, so obsolete swipes are never replayed and a finished flight can't be followed by a late one. No landing within 1 s -> retry once, then log and drop. workspace prev/next count from the in-flight target, so repeated 'next' adds up. move-window-to-workspace now waits (0.5 s) for kex_window_space_id to confirm the move before following through the same switcher. The follower's per-display lastSeen guard is set on every post. VM (one display): 10 alternating 2/1 settled on 1, no late jumps over 6 s; concurrent bursts 2/3/1, 3/1/2, 1/5/3 (fired within 50 ms) and sequential ones settled on the last request received; next x3 went 1 -> 4; move --follow 2 -> 4 landed with the window. Two-display validation stays with din-8j6i/din-drei.
