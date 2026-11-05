---
id: din-dukq
status: closed
deps: []
links: []
created: 2026-09-25T11:29:43Z
type: task
priority: 1
assignee: Mikkel Malmberg
tags: [layout, spaces]
---
# Fix follower, hidden apps, reload hook and small leftovers from wave five

Collected from agent reports: (1) the Cmd-Tab follower jumps to a window on another Space even when the app has a window on the current Space; prefer a window on the current Space of the focused display, follow only when there is none. (2) Windows of an app hidden with Cmd-H stay in their tree and leave empty tiles; on hide (816) remove from the tree, on unhide (815) re-insert. (3) ensureWorkspaceCount is not re-run on config reload; add it to the reload path. (4) Queued frame writes are not cancelled on enable off; give FrameApplier a cancel and call it. (5) Layout has no public initializer; add one and use it in Recovery. (6) kex help does not list recover.

## Acceptance Criteria

Cmd-Tab to an app with a window on the current Space stays put. Cmd-H then unhide re-tiles without empty tiles. Raising workspaces in the config and reloading creates Spaces. enable off leaves no late frame writes. kex help lists recover.


## Notes

**2026-09-25T11:45:50Z**

(1) followActivation stays put when the app has a window on the focused display's current Space; verified Finder with frontmost window on 1 and one on 5: activation from 5 stays, from 2 follows to 1. (2) 816/815 also fire for every window on each Space switch, so the kind cannot drive the tree; hidden windows already read as minimized, but the hide event can arrive before the state flips (Finder with two windows kept one). Coordinator now reconciles on NSWorkspace didHide/didUnhide; Cmd-H/unhide verified with 2 Finder windows and TextEdit. (3) reload runs ensureWorkspaceCount; workspaces=6 created Space 107 in the VM. (4) FrameScheduler.cancel (tested) via FrameApplier.cancel on enable off; the coordinator's completion also checks enabled. (5) Layout public init, used in Recovery. (6) help lists recover (Cli.swift change by the other agent), verified.
