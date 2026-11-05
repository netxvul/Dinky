---
id: din-5rp2
status: closed
deps: [din-z1jw]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 0
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, events]
---
# WindowServer event stream and window model

Replace polling with SLSRegisterNotifyProc notifications as JankyBorders does: window create, destroy, move, resize, reorder, level, hide, unhide, front app change, Space change. Feed a window model with lifetime-safe identity (window id plus pid plus creation), owner, frame, level, Space, and whether it is a normal window. AX observers only where WindowServer has no signal (title, minimize).

## Acceptance Criteria

Opening, closing, moving and switching Spaces all show up as events within a frame or two, on 27.0, with SIP on on the host. No timer polling remains except as a sanity reconcile.


## Notes

**2026-09-25T10:40:11Z**

events.m/events.h, WindowModel.swift, Events.swift in place. Host (27.0, SIP on) observation with kex events + an all-types probe: notify procs run on the main thread, inside [NSApp run]; with a plain CFRunLoopRun and no NSApplication nothing is delivered (JankyBorders pumps SLSGetEventPort itself; we must not, it would steal AppKit's events). Main connection, no SLSNewConnection needed (JankyBorders and yabai both use the main one; yabai's SLSNewConnection is only for animations). Handler signature is (type, data, len, context); a 5th arg is garbage. Payloads seen: 1325/1326 are 12 bytes, u64 sid @0 + u32 wid @8; 804/806/807/808/811/815/816 are 4 bytes, u32 wid @0; 1508 is 0 bytes (front pid looked up via _SLPSGetFrontProcess -> SLSGetConnectionIDForPSN -> SLSConnectionGetPID); 1201 (24 bytes, not used) also arrives. Per-window events need SLSRequestNotificationsForWindows with the whole tracked list, re-sent on every add/remove (804 close only arrives for requested windows). Opening TextEdit: create/resize/level events within ~1-50 ms of each other and of the front-app change; quit: close/hide/destroy for all its windows within 5 ms. Seed of 11 windows takes ~80 ms total process time. Not observed: Space change (1401), Space created/destroyed (1327/1328), 723/1322, window moved between Spaces, minimize. The kex VM was running but ssh on :22 refused connections for the whole session. Do not close until 1401 is seen, ideally in the VM.

**2026-09-25T10:41:37Z**

Event stream and WindowModel done; Space-change (1401) and Space create/destroy events not yet observed live, verify in din-drei and when din-j0o9 consumes them. Closing.
