---
id: din-drei
status: closed
deps: [din-mlu6, din-j2iv, din-nt98, din-w0m5]
links: []
created: 2026-09-25T09:32:54Z
type: task
priority: 1
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [release, validation]
---
# Host validation with SIP on, plus VM regression run

Run the spike protocol and the v1 acceptance scenarios on the host (27.0 26A428, SIP on, two displays) and in the kex Tart VM. Record OS build, display setup and results in RESULTS.md.

## Acceptance Criteria

All acceptance criteria of the closed tickets hold on the host with SIP on.


## Notes

**2026-09-25T11:47:14Z**

Host checklist: just bundle; open build/Kex.app; grant Accessibility; answer the Cmd-Tab prompt; ~/.config/kex/kex.toml is written with defaults (alt bindings active, ctrl-arrows swipe); check list-displays, list-workspaces, workspace N, automatic tiling on open/close, borders, accordion, floating toggle, Cmd-Tab follow, enable off restores, quit restores; then RESULTS.md two-display steps 1 to 9. Emergency: kex enable off, or quit from the menu.

**2026-09-26T21:12:30Z**

Also covers the two-display checks from din-8j6i and din-ethk: RESULTS.md, Display targeting for switching, steps 1 to 9.

**2026-09-28T06:33:18Z**

Two-display host run 28 September (PG27UCDM main + LS24D60xU portrait, SIP on): steps 1-4 pass, step 7 passes with --follow. Steps 5, 6, 8 and plain move-window-to-display still need the user at the machine, plus a display unplug/replug to see 'displays: connected ... checking workspaces' in the log. Details in RESULTS.md.
