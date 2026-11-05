---
id: din-xc2v
status: closed
deps: []
links: []
created: 2026-09-25T22:16:18Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [focus, config]
---
# Focus follows mouse


## Notes

**2026-09-25T22:24:10Z**

Implemented HoverFocus in Sources/kex/FocusFollowsMouse.swift (listen-only mouseMoved tap, 50 ms trailing throttle, 2 pt movement rule, dwell of delay-ms, 300 ms quiet after Space change or config load, left-button guard, popup-menu guard, accordion flag via Coordinator.container(of:)). Config [focus-follows-mouse] enabled=false, delay-ms=100, accordion=true, wired in AppState. Hit test uses layer-0 windows only: in the VM Dock (layer 20) and Notification Center (layer 21) keep opaque full-screen windows, so a 'topmost of any layer' test never finds a window. VM: hover focus, 60 ms sweep, retile/resize/layout under still pointer, button held, workspace switch quiet, delay-ms 0, enabled=false removes the tap (CGGetEventTapList), accordion=false all behave as designed.
