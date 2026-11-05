---
id: din-czpm
status: closed
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 2
assignee: Mikkel Malmberg
tags: [switching, fuzzing]
---
# Cmd-Tab within 1 s of a Space change is not followed

SpaceSwitching ignores every app activation for 1 s after any Space change (quietAfterSpaceChange), to avoid chasing the activation macOS makes on arrival (Finder on an empty Space). A real Cmd-Tab in that second is dropped too: the app becomes active with its key window on another Space, nothing visible changes, and keystrokes go to the hidden window.

Reproduction (VM): TextEdit with a.txt on workspace 3. workspace 5 (empty); sleep 0.5; open -a TextEdit. Result: display stays on 5, TextEdit is front, the focused window is a.txt on workspace 3. With sleep 1.5 instead it follows to 3.
Fuzzer, seeds 21-23 and 31-33, activating TextEdit or Safari from an empty workspace: after 0.5 s it stayed 11 times and followed 3 times; after 1.5 s it followed 13 times and stayed 2 times (Finder activations always stay: arriving on an empty Space already makes Finder front).

Idea: the arrival activation is always of an app with a window on the new Space or of Finder, so the quiet period could apply to those only.


## Notes

**2026-09-25T22:44:28Z**

The 1 s blanket quiet period is gone: only the first activation within 300 ms of a Space change (noted by kex's own switch, the Space-change event, or the check on each activation) is taken as the arrival's and ignored. VM: TextEdit a.txt on 3; workspace 5 (empty), 0.5 s, open -a TextEdit follows to 3; the same with a posted Cmd-Tab; and after 1.5 s. Empty workspace 4 with a Finder window on 6 still stays (bounce check).
