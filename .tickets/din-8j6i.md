---
id: din-8j6i
status: closed
deps: []
links: [din-mlu6]
created: 2026-09-25T09:32:53Z
type: task
priority: 0
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, spike, displays]
---
# Spike: fast switch on a display without the cursor

The Dock swipe acts on one display. Find how to target a display: mimi's per-display handling, yabai's display focus adjustment, cursor warp during the swipe, or the swipe event's display fields. Measure on two displays on the host.

## Acceptance Criteria

workspace N switches the focused display, not the cursor's, reliably, with the chosen technique documented in RESULTS.md.


## Notes

**2026-09-25T10:00:43Z**

Research and implementation done, left open for a two-display run on the host. Answer: the Dock swipes the display under the cursor; neither the CGEvent fields nor the IOHID payload name a display (mimi space.m:431-449, dockswipe.m:23-58). mimi (space.m:493-502), yabai (space_manager.c:939-942) and bobrwm (skylight.zig:843-859) all warp the cursor to the target display's centre and never restore it; Tuna does no targeting. switch.m now does the same for the mimi path when the pointer is on another display, waits 30 ms around the swipes, then warps back and reattaches the mouse. kex_switch_to_space_index refuses unknown display UUIDs. VM single-display check: switch 2/1 --path mimi landed, --times 10 10/10. Full write-up in RESULTS.md, 'Display targeting for switching'.

Setup: two displays attached, "Displays have separate Spaces" on (the default), at least 2 Spaces on each display, `mru-spaces` false, `swift build` done. Run everything from the repo with `.build/debug/kex`. `kex switch` always acts on the main display (the one with the menu bar in System Settings > Displays, Switch.swift:47), so the display under test is chosen by moving the pointer, not by a flag. `sleep 3;` gives you time to move the pointer after pressing Return.

1. `.build/debug/kex ls`. Expect two displays, one marked `(main)`, each with a `*` on its current Space. Note both current Spaces.
2. Pointer on the main display: `.build/debug/kex switch 2 --path mimi`. Expect `mimi 1 -> 2 landed` in roughly 40 to 100 ms, the main display on Space 2, the other display unchanged, and the pointer not moving (no warp). Then `switch 1 --path mimi` to go back.
3. The case this ticket is about: `sleep 3; .build/debug/kex switch 2 --path mimi`, and during the sleep put the pointer on the secondary display and leave it still. Expect `landed` in roughly 100 to 170 ms (the warp adds two 30 ms waits), the **main** display on Space 2, the secondary display's Space unchanged, and the pointer back where you left it after at most a brief flicker to the main display's centre. `ls` should agree on both displays.
4. Same with the pointer on the secondary display: `sleep 3; .build/debug/kex switch 1 --path mimi --times 10`. Expect `10 landed, 0 timed out`, the secondary display never changing, and the pointer ending where you left it.
5. Mouse during the warp: `sleep 3; .build/debug/kex switch 2 --path mimi`, and keep moving the mouse on the secondary display through the switch. Expect the switch to land on the main display, and the pointer not to stick or freeze after it jumps back.
6. Menu bar and focus: after step 3, note which display shows the active (non-dimmed) menu bar and which window has keyboard focus. Expect both unchanged from before the switch. If the menu bar moved to the main display, record it: mimi and yabai set it explicitly after a warp, and kex may need to do the same or deliberately undo it.
7. The other direction: in System Settings > Displays > Arrange, drag the menu bar to the other display so it becomes main; `ls` shows `(main)` moved. Repeat steps 2 and 3 with the roles swapped (the pointer now sits on the former main display in step 3). Expect the same results. Move the menu bar back afterwards.
8. If step 3 switches the secondary display instead, or times out: the warp did not reach the Dock in time. Record the output. The next things to try are a longer wait after the warp in `mimi_post_swipes`, then setting the swipe events' location to the target display with `CGEventSetLocation` instead of warping (see RESULTS.md).

Pass means steps 3, 4 and 7 behave as described. Then close din-8j6i.

**2026-09-25T11:46:55Z**

Test procedure rewritten for the shipped CLI (the spike subcommands are gone): see RESULTS.md, Display targeting for switching, steps 1 to 9. Also covers din-ethk's move-window-to-display.

**2026-09-26T21:12:30Z**

Implemented and single-display verified; only the two-display run on the host remains (RESULTS.md procedure). Folding that into din-drei and closing.
