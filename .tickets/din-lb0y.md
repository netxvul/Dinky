---
id: din-lb0y
status: closed
deps: [din-mlu6, din-g6bk]
links: []
created: 2026-09-25T09:32:54Z
type: task
priority: 2
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [release, ui]
---
# Menu bar wired to the command vocabulary

Keep the status item with the current Space number of the focused display and the action menu, driven by the dispatcher. Show config errors and disabled state there.

## Acceptance Criteria

Every menu action equals its CLI command. A config error is visible without opening a log.


## Notes

**2026-09-25T11:12:14Z**

Status item shows the focused display's workspace (DisplayModel.focusedDisplay().currentWorkspace), '!' appended on a config error, greyed when disabled; refreshed on EventHub spaceChange and the 0.5 s timer. Menu: 'Space N of M', config error item, Go to / Move Window to / Move Window and Follow submenus, Re-tile, Reload Config, Enabled checkbox (enable toggle), restore item when a crashed session left windows, Quit. Every item runs a command string (tooltip 'kex <command>'); 'recover' is the one app-level command, handled next to the Dispatcher for both socket and menu. Verified by screenshot in the VM.
