# Spike results

Run on 24 September 2026 in a Tart VM (`kex`, cloned from `tuna-golden-gate-base`): macOS 27.0 build 26A5416b, SIP **disabled** (how the Cirrus Labs images ship), 1024x768 display at 2x, admin logged in on the console. The binary was built on the host (27.0 build 26A428, SIP on) and copied in. Commands ran over SSH with Accessibility, Screen Recording, Post Event and Apple Events granted to `/usr/libexec/sshd-keygen-wrapper` in the guest's TCC database. `mru-spaces` was set to false; the switch-on-activate setting and Reduce Motion were left at defaults.

The host itself has not been tested. Both differences from the plan's target (beta build, SIP off) should be closed by rerunning on the host.

## Step 1, `ls`: pass

Displays, Spaces and window membership matched Mission Control throughout.

## Step 2, `switch`: pass via mimi's swipe

| Path | Adjacent | Two away | 10 rapid alternations |
|---|---|---|---|
| Tuna swipe | timeout, Dock ignores it | timeout | not run |
| mimi augmented swipe | lands, screen changes | lands | min 41, median 66, max 99 ms, 0 timeouts |
| bridged set-current-Space | see below | not run | 13 to 34 ms but see below |

Tuna's form (no IOHID payload) is ignored by the Dock on this build, as mimi's comments say. mimi's form with the serialized IOHID payload and velocity 9999 works every time. Two-away switches take about 128 ms median because mimi waits 30 ms between steps.

The bridged `SLSBridgedManagedDisplaySetCurrentSpaceOperation` changes the Space ID that SkyLight reports but only sometimes changes the screen. Pixel sampling showed it never switched the display from Space 1 to 2, even after 3 s and a click, while it did switch from 2 back to 1 every time. Not usable.

Latency is measured to `SLSManagedDisplayGetCurrentSpace` flipping, a lower bound on the visual switch.

## Step 3, `move`: pass

All through `SLSBridgedMoveWindowsToManagedSpaceOperation`, no fallback. Every case landed in 3 to 14 ms with membership correct in `ls` and in Mission Control:

- move away, move back from the hidden Space, move and follow (follow via mimi swipe, 78 ms)
- frontmost window moved away: the app stays frontmost, the current Space does not change
- one TextEdit window moved while its sibling stayed on the source Space
- a TextEdit window with a Save sheet open: the sheet moved with it and was usable on the other Space
- the same window moved back and forth 5 times: all landed, max 10 ms

## Step 4, `focus`: pass with a caveat

- AX raise plus activate: hits for two windows of one app on the same Space, and with the sibling on another Space, without changing the Space.
- yabai's private path alone often misses when the app is not frontmost. With an AX raise added after it, which yabai also does, it hits in every same-Space case.
- Neither path can focus a window on another Space. AX does not list it, and the private path does nothing. Neither pulls the current Space away. A window manager must switch first, which is what we want.

## Step 5, `tile`: pass

Five windows on Space 1 landed where computed except for known size refusals: Safari enforces a 574 pt minimum width in a 512 pt column, and Terminal snaps to its character grid. Neither blocked the other windows. Two Spaces tiled separately and switched between with mimi's swipe felt like a working tiler in screenshots.

## Decision

All five gates pass on this VM. The winning paths are mimi's augmented Dock swipe for switching, the bridged operation for moving, and AX raise for focus. Rerun on the host with SIP on before starting the real app.

## Addendum, 25 September: Mission Control's own shortcuts instead of the swipe

Added `--path keys` (Control-Left/Right, one keystroke per step) and `--path number` (Control-N). Findings in the same VM:

- Synthetic Control-Arrow is ignored unless the events carry the secondary-fn flag as well as Control (the hotkey is registered with flags 0x840000, since arrow keys carry fn on Apple keyboards). Modifier flags-changed events alone do not help. With the fn bit it works every time.
- Control-N is off by default. Enabling symbolic hotkeys 118 to 120 through `defaults` and restarting the Dock or running `activateSettings -u` did not take effect within the session, so it was not measured.
- Latency, Control-Arrow, adjacent, 10 alternations: min 554, median 558, max 601 ms to the Space ID flip. Two away: about 610 ms. Two keystrokes posted back to back: 738 ms, and it lands on the right Space.
- Visual settle, sampled every 100 ms: the target Space is on screen by about 290 ms with the keys path, and the Space ID flips only when the slide animation ends. With mimi's swipe the screen has already changed at the first 32 ms sample.
- Reduce Motion set through `defaults` made no measurable difference, but that setting may also need a logout to apply.

The keyboard route is the plain, supported way to switch and it works, but it is roughly 10x slower to the eye than the high-velocity swipe, which skips the animation entirely.

## Addendum, 25 September: Cmd-Tab and Dock activation

Cmd-Tab or a Dock click on an app whose windows are on another Space makes macOS switch there with its own slide, because of the "When switching to an application, switch to a Space with open windows" setting (`com.apple.dock workspaces-auto-swoosh`). With the setting on, activating TextEdit from another Space took about 294 ms to the Space ID flip, plus the animation.

With the setting off, macOS only activates the app. The `kex hotkeys` daemon now observes `NSWorkspace.didActivateApplicationNotification`, finds the app's frontmost normal window through the CG window list and its Space through SkyLight, and swipes there with the mimi path. Measured through a coarse polling loop: TextEdit 77 ms, Terminal 62 ms, with the app frontmost afterwards. So every route to another Space, keyboard, Cmd-Tab or Dock, can go through the fast switch. Not yet tested: apps with windows on several Spaces, activation of an app with no windows, and what the real Cmd-Tab switcher does versus `open -a`.

## Display targeting for switching

Research from source only; there is no two-display machine to test on, and the VM has one display. Checkouts: mimi 1107d3e, yabai dd84572, bobrwm 537627f, Tuna as of 25 September.

**1. Which display the Dock swipes.** The display under the cursor. None of the four projects routes the swipe any other way:

- mimi `MimiFocusSpaceUsingGesture` (internal/native/space.m:487) finds the cursor's display (`mimiCursorDisplayID`, space.m:110-124, `SLSGetCurrentCursorLocation` plus `CGGetDisplaysWithPoint`) and warps if the target differs (space.m:493-502). Its comment at space.m:504-506: "Swipe gestures navigate spaces on the active display only", which is why it computes indices on the target display only after the warp.
- yabai's SIP-on path, `space_manager_focus_space_using_gesture` (src/space_manager.c:927-983, added 18 April 2026 in 7c4c5ba "#2780 implement space --focus with SIP enabled"), does the same: `cur_did = display_manager_cursor_display_id()` (display_manager.c:232-237), then `if (focus_display) CGWarpMouseCursorPosition(point);` (space_manager.c:939-942). `space_manager_focus_space` falls back to it when the scripting addition is unavailable (space_manager.c:1001-1006).
- bobrwm `routeDockSwipeToDisplay` (src/skylight.zig:843-859), called before any multi-step swipe (skylight.zig:251), returns early when the cursor is already on the display and otherwise warps to the display's centre. The function name states the assumption.
- Tuna has no targeting at all. `cursorDisplayIdentifier` (app/SystemExtension/SpacesRuntime.swift:146-155) takes `CGEvent(source: nil).location` and passes that display to `CGSCopyManagedDisplaySpaces` (SpacesRuntime.swift:55-63) only to read the current index and count; the swipe itself (SpacesRuntime.swift:109-143) carries no display. It works because the Dock swipes that same cursor display.

**2. Does the event name a display?** No. The CGEvent fields set are the type, HID type, motion, phase and phase alias, progress, `PositionX` = 0.1, `ZoomDeltaY` = 3 and, on the ended phase, velocity (mimi space.m:360-366 and 431-449). `PositionX` is a normalised trackpad position ("empirically required", space.m:365), not a screen point, and `PositionY` is never set. Field 169, `kCGEventSourceUnixProcessIDAlias`, gets `mach_absolute_time()` (space.m:443), a timestamp-like value rather than a display. The IOHID payload (mimi dockswipe.m:23-58, filled at 136-145) is a queue header (timestamp, a `senderID` left at 0, options, event count) plus a fluid-touch gesture record (position, swipe mask, motion, flavor, progress) and a velocity record, with no display field. So the only display information the Dock gets is where the cursor is: the event's location, which `CGEventCreate(NULL)` fills with the current pointer position, or the WindowServer's own cursor position. Not the display with the key window: all three projects that target a display move the cursor, not focus.

**3. What each does when the target is not the cursor's display.**

- mimi warps and does not restore the cursor: `CGWarpMouseCursorPosition(point);` then `mimiPumpRunLoop(kMimiSpaceGestureProcessingDelay);` (30 ms, space.m:497-502), posts the swipes, waits (space.m:579), then `mimiSetActiveMenuBarDisplay(new_did)` (`SLSSetActiveMenuBarDisplayIdentifier`, space.m:128-136) and, if the display's Space is still wrong, a synthetic left click at the display centre (space.m:580-594). There is one `CGWarpMouseCursorPosition` in the file and no restore.
- yabai: the same without the wait. `if (focus_display) CGWarpMouseCursorPosition(point);`, the swipes, then `display_manager_set_active_display_id(new_did); if (space_manager_active_space() != new_sid) { CGPostMouseEvent(point, false, 1, true); CGPostMouseEvent(point, false, 1, false); }` (space_manager.c:942-980). No restore. `CGAssociateMouseAndMouseCursorPosition` appears nowhere in yabai (nor in mimi, bobrwm or Tuna).
- bobrwm: warp only, `return c.CGWarpMouseCursorPosition(center) == c.kCGErrorSuccess;` (skylight.zig:858). No restore, no menu bar or click follow-up.
- Tuna: nothing; it always acts on the cursor's display.

**What kex does now** (Sources/KexPrivate/switch.m). `kex_switch_to_space_index` looks up `displayUUID` in `kex_displays()` and refuses with `switch: no display with UUID ...` on stderr when it is not there, for every path. The mimi path, `mimi_post_swipes`, checks whether the pointer is inside the target display's bounds. If it is, nothing changes from before. If not, it warps the pointer to the display's centre, waits 30 ms as mimi does, posts the swipes, waits 30 ms after the last one as well so the Dock reads them before the pointer moves, warps the pointer back, and calls `CGAssociateMouseAndMouseCursorPosition(true)` to end the short freeze of real mouse movement a warp causes. Restoring is kex's own choice; none of the sources do it. It does not copy the menu-bar and click follow-up from mimi and yabai, because kex switches the focused display, which should already own the menu bar; step 6 below checks that. The Tuna, bridged, keys and number paths are unchanged. In the VM (one display, pointer always on it) `switch 2` and `switch 1` with `--path mimi` still land, and `--times 10` landed 10 of 10, median 110 ms, just after a VM reboot.

Untested alternative: set the swipe events' location (`CGEventSetLocation`) to the target display instead of moving the pointer. No source does this, and it only helps if the Dock reads the event location rather than the WindowServer cursor. Worth one try on two displays if the warp flicker bothers.

**Test procedure for the host with two displays**

Setup: two displays attached, "Displays have separate Spaces" on (the default), at least 2 Spaces on each display, `mru-spaces` false, `swift build` done. Run everything from the repo with `.build/debug/kex`. `kex switch` always acts on the main display (the one with the menu bar in System Settings > Displays, Switch.swift:47), so the display under test is chosen by moving the pointer, not by a flag. `sleep 3;` gives you time to move the pointer after pressing Return.

1. Build and launch the app (`just bundle`, open `build/Kex.app`, grant Accessibility). `kex list-displays` must show two displays, one marked main and one focused; `kex list-workspaces` shows each display's Spaces with the current one starred. Note both current Spaces.
2. Pointer on the focused display: `kex workspace 2`. Expect that display on workspace 2 within about 100 ms, the other display unchanged, and the pointer not moving. `kex workspace 1` to go back.
3. The case this ticket is about: click a window on display A so A has focus, then move the pointer to display B and leave it still; run `sleep 3; kex workspace 2` from a terminal on either display (the terminal window's display is what has focus, so put the terminal on A). Expect A on workspace 2, B unchanged, and the pointer back where you left it after at most a brief flicker to A's centre. `kex list-workspaces` should agree.
4. With the pointer still on B: ten alternating `kex workspace 2` and `kex workspace 1` runs back to back. Expect A to settle on the last one and B never to change.
5. Keep moving the mouse on B during a `sleep 3; kex workspace 2`. Expect the switch on A and the pointer not to stick or freeze after it jumps back.
6. After step 3, note which display shows the active menu bar and which window has keyboard focus. Expect both unchanged. If the menu bar moved to A, record it: mimi and yabai set it explicitly after a warp.
7. `kex move-window-to-display next` on a tiled window, then `--follow` on another. Expect the window to land on the other display's current workspace, both displays re-tiled, and focus on the moved window in the follow case.
8. Swap which display is main in System Settings > Displays > Arrange and repeat steps 2, 3 and 7. Move the menu bar back afterwards.
9. If step 3 switches B instead, or times out: the warp did not reach the Dock in time. Record the output; the next things to try are a longer wait after the warp in `mimi_post_swipes`, then the `CGEventSetLocation` alternative above.

Pass means steps 3, 4 and 7 behave as described. Then close din-8j6i.

**Host run, 28 September 2026.** macOS 27.0 build 26A428, SIP on, Apple M1 Max with the lid closed. Two externals: PG27UCDM at 2560x1440 as main, and LS24D60xU rotated to 1440x2560 portrait, placed left of main at (-1440, -647). "Displays have separate Spaces" on, `mru-spaces` false. Main had 5 workspaces and the portrait display 1 (`[display.secondary] workspaces = 1`). Pointer moved with synthetic mouseMoved events; commands ran from a Ghostty window on main. The user was working on the machine during the run.

| Step | Result |
|---|---|
| 1 | Pass. Two displays, main marked, each with its current Space. |
| 2 | Pass. Pointer on main: `workspace 1` landed in 160 ms, no warp. |
| 3 | Pass. Pointer on the portrait display, focus on main: main switched (184 ms), the portrait display kept its Space, the pointer ended where it was left. |
| 4 | Pass. Ten alternating switches with the pointer on the portrait display: 10 of 10 landed on main in 93 to 176 ms, the pointer read the same after every one. |
| 5, 6, 8 | Not run. They need a hand on the mouse, eyes on the menu bar, and System Settings. |
| 7 | Pass for `--follow`: the window moved to the portrait display's workspace, both displays re-tiled, focus followed. Plain `move-window-to-display` not run. |

0.7 s after step 4's last switch, the follower logged `activate Helium: followed 1 -> 2` and took main back to workspace 2, where Helium's window was. The same happened 2.6 s after a single switch in step 2. With the user active it is not clear whether these were their activations; din-ame0 has the trail.

Found and fixed in the same run: a display connected after launch never got its workspaces, since the count was only ensured at launch and on reload. The app now ensures it a second after a new display appears. `[display.<pattern>]` tables take `workspaces`, so one display can have a different count. A new workspace whose default layout is accordion now starts with `auto` orientation, so on the portrait display it runs top to bottom (AeroSpace's `default-root-container-orientation = 'auto'`).

## Space creation spike: works

Run on 25 September 2026 in the same VM (macOS 27.0 26A5416b, SIP off, one 1024x768 display, 3 Spaces at the start). Ticket din-19v3.

**Result: kex can create a user Space on a display with `SLSBridgedSpaceCreateOperation`, through SkyLight's synchronous bridged dispatcher. Mission Control shows it, windows move to it, the swipe switches to it, and it survives `killall Dock`.** Nothing is injected into the Dock, so SIP should not matter, but the host has not been tried.

### What the runtime says

A probe that walks `objc_copyClassList` for `SLSBridged*` gives the same answer on the host (26A428) and in the VM (26A5416b):

```
SLSBridgedSpaceCreateOperation : SLSSynchronousBridgedWindowManagementOperation
  - initWithOptions:values:   @28@0:8I16@20     (uint32 options, NSDictionary values)
  - makeResultWithSpaceID:    @24@0:8Q16
  - invokeFallback            @16@0:8
  @ options TI,R   @ values T@"NSDictionary",R,C
SLSBridgedWindowManagementOperationSpaceIDResult
  - spaceID Q16@0:8
SLSBridgedSpaceDestroyOperation : SLSAsynchronousBridgedWindowManagementOperation
  - initWithSpaceID: @24@0:8Q16
```

It is a *synchronous* operation, so the asynchronous dispatcher from move.m does not fit. SkyLight has a synchronous twin, also non-exported: `__ZL54_SLSPerformSynchronousBridgedWindowManagementOperationP46SLSSynchronousBridgedWindowManagementOperation`. It returns the result object. Disassembly shows:

- The dispatcher and `-performWithWMBridgeDelegate` are the same code: both hand the operation to `SLSWMBridgeDelegate()`. In a client process that is `SLSWindowManagementFallbackBridge`, which calls `-invokeFallback`. For this class that means `SLSWindowServerClientSpaceCreate(…, options, values)`, a MIG call to WindowServer. The Dock is not involved.
- The exported `SLSSpaceCreate(cid, options, values)` builds the same operation when `SLSWindowManagementClientOperationsEnabled()` is true, and otherwise calls `SLSWindowServerClientSpaceCreate` directly.

No option or dictionary key is documented. The values follow bobrwm (below): `type` = 0 (user) and `Display Identifier` = the display UUID. `options` = 0.

### What other window managers do

- **yabai** (`space_manager_add_space`): only through its scripting addition. It injects into the Dock and calls the Dock's own `addSpace` on a new `ManagedSpace`. That needs SIP off, so it is not an option for kex.
- **bobrwm** (`skylight.zig createNativeSpace`): exactly this path. It calls `[[SLSBridgedSpaceCreateOperation alloc] initWithOptions:0 values:@{type: 0, "Display Identifier": uuid}]`, then `performWithWMBridgeDelegate`, and reads `spaceID` from the result. It then polls `SLSCopyManagedDisplaySpaces` until the count grows. It also uses `SLSBridgedSpaceDestroyOperation initWithSpaceID:` to remove Spaces.

### Calls and results on 26A5416b

| Call | Process | Result |
|---|---|---|
| `kex spaces create` (bridged op through the sync dispatcher) | kex (links AppKit) | `SpaceIDResult` with spaceID 23. In `SLSCopyManagedDisplaySpaces` immediately, type 0 |
| same, `--display <uuid> --restart-dock` | kex | spaceID 32. Still listed after `killall Dock` |
| bridged op via `-performWithWMBridgeDelegate` | bare Foundation probe | result **nil**, nothing created |
| same, with `SLSCopyManagedDisplaySpaces` called first | bare Foundation probe | nil |
| same | probe linking AppKit (`NSApplicationLoad()` or just touching `NSScreen`) | spaceID 44 / 45, created |
| exported `SLSSpaceCreate(cid, 0, values)` | bare probe, and AppKit probe | returns 0, nothing created |
| `SLSBridgedSpaceDestroyOperation` via `-performWithWMBridgeDelegate`, and exported `SLSSpaceDestroy` | bare probe, on Spaces 23 and 32 | nothing removed (return 0) |

So the working form is the bridged op, sent from a process with AppKit loaded. kex already links AppKit. Removing a Space from a bare process did not work, not even with the original creator gone. From a process with AppKit loaded it does; see "Removing Spaces" below. The test Spaces were removed with Mission Control's own close button.

### Mission Control and the Dock

Screenshots were taken in the VM with Control-Up and `screencapture`, and checked by eye. Copies are in the spike agent's scratchpad; they are not committed.

- Before: Desktop 1 to 3.
- After `spaces create`: **Desktop 4** appears at the end of the strip, with no Dock restart and no delay.
- `kex move 47 4` moved a TextEdit window there in 15 ms. `kex switch 4 --path mimi` switched to it in 437 ms. The screen showed an empty desktop with TextEdit, and the menu bar number read 4.
- **`killall Dock` was run twice** in the VM. After it, `spaces ls` still showed Space 23, and Mission Control still showed Desktop 4 with the TextEdit thumbnail on it. Space 32 also survived its restart.

The first two test Spaces (23, 32) were removed and 3 Spaces were confirmed. After the AppKit probe runs, the VM had 5 Spaces (44 and 45 added). The same Mission Control cleanup was sent, but the VM stopped answering on the network during it (tart still reports it running), so the final count is unverified. Expect 3, or 5 if the clicks did not land. Either way it is at least 3.

### Recommendation

Use it. `kex_create_space(displayUUID)` in `Sources/KexPrivate/spaces.m` is the real function. It returns the new Space ID, or 0 with the reason on stderr. The "ensure workspace count" feature (din-son6) can call it once per missing Space, then wait until `kex_displays()` lists the new ID; it showed up on the first poll here. Open points:

- **Host with SIP on:** not tested, per the brief. Nothing on this path touches the Dock, and the call is a plain client-to-WindowServer MIG call, so SIP should not matter. Confirm on the host before relying on it; it is a one-line `kex spaces create`.
- **Multi-display:** not tested, since the VM has one display. `--display <uuid>` goes into `Display Identifier`, which is the only way the target display is chosen.
- **The exported `SLSSpaceCreate` does not work** on this build. Do not replace the dispatcher lookup with it.

## Removing Spaces, 29 September: works with AppKit loaded

The earlier probe tried removal only from a bare Foundation process. A probe that loads AppKit (`[NSApplication sharedApplication]`, `NSScreen`), creates a Space with `kex_create_space` and then removes it gives:

| Call | Result |
|---|---|
| `SLSBridgedSpaceDestroyOperation initWithSpaceID:` then `-performWithWMBridgeDelegate` | removed at once. The delegate is AppKit's `NSWMWindowCoordinator`, which is why a bare process gets nothing |
| the same operation through the asynchronous dispatcher `move.m` uses | removed at once |
| `-invokeFallback` directly | nothing removed |
| exported `SLSSpaceDestroy(cid, sid)` | returns 0, nothing removed |

Also checked in the VM (26A5416b, SIP off): a Space created by another, exited process is removed; a Space with a window on it is removed and the window moves to the display's current Space, as with Mission Control's close button; removing the current Space drops the display to its first Space. The Dock's `com.apple.spaces` preferences agree afterwards, a `killall Dock` brings nothing back, and Mission Control shows no phantom desktop.

On the host (27.0, **SIP on**, two displays) a test Space created on the secondary display was removed the same way and left nothing behind in `com.apple.spaces`.

`kex_destroy_space` in `Sources/KexPrivate/spaces.m` uses `-performWithWMBridgeDelegate`. Workspace arranging (`Sources/kex/WorkspaceNumbers.swift`) calls it for empty Spaces no workspace is on, after moving any workspace's windows away, and switches a display to one of its workspaces before removing the Space it shows.

## Fuzzing, 26 September

`just fuzz <seed> <steps>` copies the debug binary and `scripts/fuzz.py` into the VM, restarts the app from that binary and runs the fuzzer there over ssh. Each step runs one weighted random action through the CLI: open, reopen, close, minimize, unminimize or quit TextEdit documents; Finder and Safari windows; hide and unhide apps (`kex debug hide-app`, the AX hidden attribute, because `NSRunningApplication.hide()` answers false from ssh); `open -a` activations (the Cmd-Tab path); `workspace` and `move-window-to-workspace` with and without `--follow`, which put TextEdit documents on several Spaces; tree commands; native Control-Arrow switches (posted in kex's `service` mode so kex's own ctrl-arrow bindings do not take them); trips to empty workspaces by kex or natively, sometimes followed by an activation 0.5 or 1.5 s later; and a "twin", a window shown at exactly another tile's frame, as Ghostty opens new windows. Between 3 and 8 windows are kept.

After each step it reads `kex debug-state` at 0.8 s and at 2.3 s and checks: tiled windows on screen within 2 pt of their expected frames (unless a minimum size is recorded; TextEdit, Finder and Safari only, since Terminal snaps to its grid); no overlap between tiles whose expected frames do not overlap; every window in at most one tree and on that tree's Space; every normal window on a shown workspace placed; the focused tiled window on screen; `list-workspaces --focused` agreeing with the display; the display staying on its Space after actions that should not switch (close, quit, minimize, hide, tree commands); and nothing moving between the two reads ("spontaneous shift"). What was wrong at 0.8 s but right at 2.3 s is printed as "settled late", not counted.

Runs, 150 steps each: seeds 11, 21 and 22 found nothing (earlier fuzzer versions, without quit and the bounce check); seed 23 shift-frame x11; seed 31 shift-frame x11; seed 32 g-bounce x2, a-frame x1 (Terminal's grid, since excluded); seed 33 g-bounce x5, shift-frame x2, shift-tree x1. The app never died.

**Same-app window at a tile's exact frame took the tile** (din-y4b1, fixed). `Coordinator.tab(replacedBy:in:)` let any newly shown window of the same app at exactly a tile's frame replace that tile as if it were a native tab, leaving the old window untracked under it. Confirmed on the user's Mac with Ghostty. In the VM: TextEdit a and b on workspace 3; `move-window-to-workspace 4 --follow` with b; focus b; `move-window-to-workspace 3 --follow`: a untracked. Also: a alone and minimized, b opened (same full frame), a unminimized: b untracked. Now a window arriving from another Space's tree is never a tab, and a same-frame newcomer is held out for 250 ms: if the tile's window is ordered out or closed in that time the newcomer takes its tile, otherwise it is tiled normally. TextEdit Merge All Windows, Show Next/Previous Tab and closing a tab still keep one tile in place. Seed 33 steps 54 and 55 (twin) settled late but correctly; a newcomer that was held once is not held again, so later events tile it at once.

**Tiles shift two or three times when a window refuses its size** (din-9egq). Minimum sizes are learned from readback after a write, settle, retry and settle, and each one found triggers another layout. Three TextEdit documents on an empty workspace, then `open -a Safari`: tiles moved at 0.93, 1.25 and 1.52 s, the first TextEdit tile going 500, 418, then 303 pt wide. All the shift-frame reports in seeds 23 and 31 (for example seed 23 steps 5, 6 and 12, seed 31 steps 11, 24, 41 and 54) are this: the last pass lands after the 0.8 s read.

**Quitting or hiding the front app throws the display to another Space** (din-4wkw). macOS activates another app, often Finder, and the activation follower chases its window. TextEdit's only window on workspace 5, a Finder window on 6: `pkill -x TextEdit` gives "activate Finder: followed 5 -> 6". Seed 32 steps 53 and 72, seed 33 steps 63, 103, 109, 122 and 133.

**Cmd-Tab within 1 s of a Space change is ignored** (din-czpm). The follower's quiet period drops real activations too. TextEdit's a.txt on workspace 3; `workspace 5` (empty), 0.5 s, `open -a TextEdit`: the display stays on 5 with TextEdit front and its key window on 3. Across the runs, TextEdit or Safari activated from an empty workspace followed 3 of 14 times after 0.5 s and 13 of 15 times after 1.5 s.

**Opening a document from another workspace follows the app to its old Space** (din-2h2u). The app activates before its new window exists. TextEdit's a.txt on 3; `workspace 6`, then `open -a TextEdit b.txt`: "followed 6 -> 3". The same with `open ~/Documents` while Finder has a window elsewhere, and seed 23 step 59.

**`move-window-to-workspace --follow` leaves the moved window unfocused** (din-mocv). After the move the source Space loses the active app's window, macOS activates Finder, and nothing focuses the window on arrival: `list-windows --focused` says no window is focused.

On the "weirdness when switching to empty spaces" report: landing on an empty workspace by itself never moved the display in these runs (by kex 38 of 38 times, by native Control-Arrow 32 of 32, seeds 21 to 23 and 31 to 33), and no frame changed during the idle period after a landing. What moves the user away from an empty workspace is the activation follower: din-4wkw when an app quits or hides there, din-2h2u when a document or window is opened from there, and din-czpm when a Cmd-Tab from there comes too soon and is dropped.
