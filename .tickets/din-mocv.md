---
id: din-mocv
status: closed
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 2
assignee: Mikkel Malmberg
tags: [focus, fuzzing]
---
# move-window-to-workspace --follow leaves the moved window unfocused

After move-window-to-workspace N --follow the display is on N with the moved window there, but Finder is the front app and no window is focused (list-windows --focused: 'no window is focused'). macOS activates Finder when the source Space loses the active app's last window, and windowMoved(refocus: false) does not focus the moved window after the switch lands.

Reproduction (VM): workspace 3; open -a TextEdit a.txt (only window there); move-window-to-workspace 4 --follow; sleep 1.5; list-windows --focused -> 'no window is focused', front app Finder.

Idea: when following, focus the moved window once the swipe lands (SpaceSwitcher completion).


## Notes

**2026-09-25T22:44:28Z**

switchSpace/SpaceSwitcher.request take a 'landed' callback, run once the display is on the target (dropped if a newer request replaces it). move-window-to-workspace --follow focuses the moved window there through Coordinator.focus -> focusWindow, which marks the activation as kex's own. VM: a.txt the only window on 3, move-window-to-workspace 1 --follow: on 1, focused TextEdit a.txt.
