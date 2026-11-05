---
id: din-ohjx
status: closed
deps: []
links: []
created: 2026-09-25T20:59:21Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [testing]
---
# Fuzz harness in the VM with invariant checks


## Notes

**2026-09-25T22:22:15Z**

Harness done: debug-state query, kex debug ax-close/ax-minimize/ax-unminimize/ax-frame/hide-app/unhide-app, scripts/fuzz.py, scripts/vm-fuzz.sh, just fuzz. Runs of 150 steps: seeds 11, 21, 22 clean; 23, 31, 32, 33 found shift-frame and g-bounce classes. Fixed the tab heuristic (din-y4b1). Filed din-9egq (multi-pass min-size layout), din-4wkw (quit/hide bounce), din-czpm (1 s quiet period drops Cmd-Tab), din-2h2u (opening a document follows to the app's old Space), din-mocv (--follow leaves the window unfocused). See RESULTS.md, Fuzzing, 26 September.
