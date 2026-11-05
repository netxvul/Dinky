---
id: din-ame0
status: closed
deps: []
links: []
created: 2026-09-27T22:00:35Z
type: bug
priority: 1
assignee: Mikkel Malmberg
tags: [switching, fuzzing]
---
# Follow loop between two apps on the host

Reported 27 September 2026: kex sometimes switches Spaces between two apps without end, possibly after an app closes and macOS activates a fallback app. Not reproduced in the VM: 5 seeds x 80 steps of scripts/fuzz.py --switching (quits, closes, activations, native and kex switches, pointer moves with focus-follows-mouse on, native full-screen toggles) on one display, with the h-loop invariant (three or more Space changes while idle) never firing. The switcher retries a swipe once and gives up, and the follower never follows an app that has a window on the focused display's current Space, so a loop needs a late arrival activation (seen once: 'activate Finder: followed 2 -> 6' after landing on an empty workspace, so arrivals can come later than the 300 ms arrivalWindow) or two displays, which the VM cannot test. Mitigation shipped: the follower pauses for 5 s after 4 follows within 3 s and logs the trail, and the bundled app now logs to ~/Library/Logs/kex.log. Next: wait for a trail from the host and read it.


## Notes

**2026-09-28T06:33:18Z**

Two-display host run 28 September: 'activate Helium: followed 1 -> 2' 0.7 s after ten fast kex switches on main (pointer on the portrait display), and 2.6 s after a single 'workspace 1' in step 2. Helium's window was on workspace 2. The user was working at the time, so these may have been their activations. The log from 08:20 to 08:22 also shows Helium and Ghostty follows alternating about 1.4 s apart. Follower log lines now name the display instead of its CGDirectDisplayID (which was 2 for the main display).

**2026-09-28T06:55:51Z**

Root cause found and fixed 28 September. Not the follower: Coordinator.apply, for accordion and fullscreen trees, activated the tree's focused window when each frame pass finished, using the focus captured when the pass started. FrameScheduler reports every overlapping batch, so right after launch a pass started with the tree's stale first focus and a newer pass with the real one both finished and activated their windows in turn; each activation moved the tree's focus and started the next pass, forever. Nothing was logged because only follows are logged. Repro in the VM: accordion workspace with Terminal and Safari, Safari focused, restart kex: 29-30 alternating activations in 8 s, 3 of 3 trials, still going 20 s later; with Terminal focused it settled. Fix: a finished pass activates its window only if it is still the tree's focus, focus is still in that tree, and the window is not already focused (Coordinator.shouldBringForward). After: 0 activations in 8 s, 6 of 6 restarts; focus left/right, a new window and quitting an app still leave the focused window on top.

**2026-09-28T09:30:08Z**

Reopened by the user 28 September (loop after restart, and on Cmd-backtick between Ghostty windows, accordion only); the first fix only covered part of it. Two more stale-focus paths: (1) the applier's raise after each pass: raising a window of the frontmost app makes it that app's key window, so a pass with an older tree focus took focus back; (2) syncFocus on the front-app event read the previous window, since the app's front window settles ms later, so the tree missed about half of all Cmd-backtick switches and later passes acted on that. Fix: frame passes no longer activate anything (the tree follows macOS focus and commands focus themselves), raises are skipped when they could move focus off a window other than the pass's front (FrameApplier.raisingKeepsFocus), and the coordinator re-syncs focus 20 ms after a front-app event as the border manager already did. VM, two Terminal windows + Safari in an accordion: before, sustained 4/s ping-pong on Cmd-backtick and restart; after, 0 of 20 Cmd-backtick presses wrong (no bounce, tree and top window match), 6 of 6 restarts with 0 focus changes, focus commands, open, quit and switching away and back all correct.
