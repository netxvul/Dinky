---
id: din-ecx6
status: closed
deps: [din-cc9k]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [release, recovery]
---
# Enable, disable, restore on quit, crash recovery

Journal original frames and Space membership before kex first touches a window. Disable and quit cancel queued work and restore frames on still-valid displays. After a crash, reconcile live identities and offer restoration from the journal. Emergency disable binding.

## Acceptance Criteria

Quit puts every window back where it was. Killing kex and relaunching offers restore and does not touch windows that were reused IDs.


## Notes

**2026-09-25T11:12:14Z**

Done in Sources/kex/Recovery.swift, wired from AppState (setEnabled, recover, quit) and App (SIGTERM/SIGINT go through NSApp.terminate so kill quits cleanly). Journal: ~/Library/Application Support/kex/journal.json, {pid, launched, windows:[{id,pid,bundleID,firstSeen,frame,spaceID}]}, dates as seconds since 1970, saved 0.5 s debounced, removed when empty. Recorded once per normal window from the coordinator's WindowModel; Recovery subscribes to EventHub after the coordinator (plus activeSpaceDidChange), so the model has the event before Recovery reads the pre-tiling frame. Restore (enable off, quit, kex recover): coordinator off, skip closed windows (model identity must match) and windows whose display is gone, write frames through a FrameApplier in current stacking order, bridged-move windows back to their original Space if it still exists, write frames again for moved ones, log what failed, clear the journal. Crash: a journal from another pid is carried over only for windows with the same pid and bundle id whose app launched before firstSeen; the rest are logged as reused ids. Menu offers 'Restore N windows from the previous session'; kex recover runs the same and leaves kex disabled. Emergency path: kex enable off (restores everything); a service-mode binding such as alt-shift-semicolon then a key -> 'enable off' belongs in the default config, not edited here. Caveat: the coordinator's frame writes already queued when disabling are not cancelled, only stopped from being scheduled. VM: enable off restored 6/6 frames exactly; kill -9 + relaunch + recover restored 6/6; faked reused ids (pid, firstSeen) were skipped; SIGTERM after move-window-to-workspace put the window back on its Space and frame.
