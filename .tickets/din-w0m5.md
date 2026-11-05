---
id: din-w0m5
status: closed
deps: [din-g6bk]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-zyzn
tags: [hotkeys]
---
# Hotkey engine with modes and chained commands

Event tap on key down; parse AeroSpace key syntax (alt-shift-h, ctrl-left, esc) into keycode and modifiers; bindings per mode; a binding runs one command or a list; mode <name> switches. Self-posted events are tagged and passed through. Bindings from config, replaced on reload.

## Acceptance Criteria

The PLAN.md default bindings work, including the service mode round trip. A key not bound passes to the app untouched.


## Notes

**2026-09-25T10:35:08Z**

Engine done: HotkeyEngine.swift (init(onCommands:), load(modes:), setMode, currentMode, enabled, start/stop), KeyCodes.swift (all 100 KeyCombo.keyNames mapped via Carbon kVK_ constants; 'kex hotkeys --check' prints 0 unmapped). Matching compares only alt/ctrl/cmd/shift, so the secondary-fn and caps-lock bits are ignored. Events tagged 0x64696E6B pass through. onCommands runs via DispatchQueue.main.async so slow commands cannot time out the tap. Follower/switchSpace moved to SpaceSwitching.swift unchanged. 'kex hotkeys' is print-only with Config.default and handles 'mode X' itself. Tested on host with posted events: alt-1, alt-shift-1, ctrl-left with fn (0x840000), ctrl-right without fn, alt-shift-semicolon -> service -> alt-shift-h / esc / r back to main, alt-tab, alt-h all printed; unbound r in main and a tagged alt-1 passed through. VM ssh was refused, so no VM run. Hotkeys.swift keeps installHotkeyTap()/hotkeysEnabled as a temporary shim (ctrl-arrow only, on the engine) for App.swift until the dispatcher wires the engine. Open until din-g6bk runs the commands.

**2026-09-25T10:41:37Z**

Engine done and wired into the app by din-g6bk with config bindings. Live tap test with real commands happens with din-mlu6 in the VM. Closing.
