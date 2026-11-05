---
id: din-nt98
status: closed
deps: [din-5rp2]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-oji3
tags: [visuals, borders]
---
# Focus borders on SkyLight windows

Reimplement JankyBorders' approach (GPL, no code lifted): one border window per managed window created with SLSNewWindow, ordered directly above or below its target with SLSTransactionOrderWindow, moved and resized from the event stream, drawn with active or inactive colour, width and style from config. Works on every display and Space. Hidden for full-screen and minimized windows.

## Acceptance Criteria

Borders track windows during native drags and kex re-tiles without lag or flicker. Focus change recolours within a frame. Works with SIP on on the host, on 27.0.


## Notes

**2026-09-25T10:47:45Z**

Implemented: borders.m/borders.h (C API: create(scale)/update/move/move_to_space/hide/show/destroy/focused_window), BorderWindow.swift, Borders.swift (BorderManager(config:model:), handle(_:), update(config:), onlyFocused). Borders ordered BELOW the target (kCGSOrderBelow) so they never cover content; stroke's inner edge is the window frame, radius = cornerRadius + width/2. Verified in VM (2x display): borders hug frames (4pt = 8px, crisp, follow 16pt corners), follow kex tile and accordion re-layouts, front window active-coloured, hidden app's borders removed and restored on unhide. Findings: the target's own shadow falls on the below-ordered border and darkens it (#e1e3e4 reads ~#b9bbbc next to the window), same as JankyBorders order=below. Hidden windows lose their document tags, so their BorderWindow is destroyed and recreated on unhide. Not verified: native mouse drags (lag/flicker), Space switch live, SIP-on host (din-drei). Sub-level not copied (JankyBorders uses a raw mach message for it).

**2026-09-25T10:49:05Z**

Borders done and verified in the VM (fit, colours, following re-tiles, hide/unhide). Ordered below the target. Not yet checked: native drags, Space switch, host with SIP on; those go to din-drei. Wiring into the app is part of din-j2iv. Closing.
