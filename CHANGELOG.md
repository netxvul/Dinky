# Changelog

## Unreleased

### HUD

- A capsule of Liquid Glass names the new layout, such as `h_accordion` or `scrolling`, after the `layout` command, and the new binding mode when it changes, for a moment on the focused display. The new `[hud]` table places it above the Dock (`position = 'bottom'`, the default) or below the menu bar (`'top'`), `offset` points away, keeps it up for `duration-ms` (1200 by default), and turns it off for either change with `on-layout-change` or `on-mode-change`, or entirely with `enabled = false`.
- When a display moves to another workspace, the capsule shows there the workspace's number and layout, such as `2 · v_accordion`. `[hud] on-workspace-change = false` turns it off.
- A key binding or gesture that does nothing, such as `move left` at the edge (a floating window's too), a resize at its limit, `focus` or `focus-monitor` with nothing that way, `workspace next` on the last workspace or `workspace 6` with five, moving a window to where it already is, `rotate` in a scrolling layout or `fullscreen` on a lone window that already fills its workspace, breathes a soft glow around the focused window twice: `'#ed8796'` at its edge, fading out 24 points outside and 12 inside, over the window and any border it has, even with borders off or for an app in `exclude-apps`. `[borders] noop-flash = false` turns it off; `noop-flash-color`, `noop-flash-count`, `noop-flash-ms` and `noop-flash-spread` tune it. `[hud] on-noop = true` also shows why in the capsule. A command that leaves fullscreen before finding nothing to do, as `move left` at the edge does, does not flash. With `[fullscreen] focus-change = 'exit'`, the default, `fullscreen` on such a lone window no longer turns fullscreen on. The CLI keeps its exit status; a few replies now say why nothing changed, such as `move left: nothing to do` for a floating window or `fullscreen: the window already fills the workspace`.

### Switcher

- New `[window-switcher]`: set `modifier` to `'alt'`, `'ctrl'`, `'cmd'` or `'shift'`, hold it on its own over a workspace, and after `delay-ms` (200 by default) a glass capsule of the workspace's windows shows over the pointer, the focused one under it, in strip order on a scrolling workspace and tree order on an accordion one; move the pointer across to pick one. On a tiles or fixed workspace it is a map of the workspace over the pointer, each tile where it is; move onto one to pick it, or set `tiles-style = 'row'` for a row there too. Release the modifier to focus the window picked; Esc or any other key closes it. `layouts` picks where it shows, `['scrolling', 'tiles']` by default, with `'accordion'` and `'fixed'` too; `corner-radius` rounds the capsule; `show-single = false` leaves a workspace with a lone window out. Thumbnails need Screen Recording, asked for the first time it shows; without it the capsule shows app icons. `[modifiers]` decides which key of the pair counts.
- New `[workspace-switcher]`: hold its own `modifier` on its own and a glass capsule of the workspaces shows over the pointer, a card per workspace drawn small in its layout with the windows where they are: an accordion's neighbours peeking out, a fixed workspace's empty cells, a scrolling workspace's columns in view with a count of those parked either side. Move across to pick one and release to switch to it. Each card has its display's proportions; with more than one display, `displays = 'all'` (the default) shows every display's workspaces, a named group per display, and `'pointer'` only the display under the pointer's. `show-empty`, `exclude`, `card-height`, `thumbnails = 'icons'` or `'schematic'` (a fixed picture of each workspace's layout, whatever its windows) and `corner-radius` tune it. It can't share `[window-switcher]`'s modifier, unless their `trigger`s differ: one key can be held for one switcher and double-tapped for the other.
- New `window-switcher` and `workspace-switcher` commands show either capsule from a key binding, in the middle of the display under the pointer: the arrows or h, j, k, l and Tab move the pick, Return or Space takes it, Esc closes it, the binding again steps to the next one, and letting go of the binding's modifiers takes the pick, as Cmd-Tab does.
- In `[window-switcher]`'s row, a column's stacked windows show one over the other, as their tiles sit on screen, and the pointer picks between them by height; any group whose tiles sit apart shows them where they are, while an accordion's windows still sit side by side.
- Both switchers show window titles, a window without one its app's name. `[window-switcher]` puts each under its card; on a map, and over a column's upper window, on a band along the card's foot. `[workspace-switcher]` puts each window's title on a band along its foot in the card, leaving out covered and tiny windows and schematic cards. `show-titles = false` in `[switcher]` turns them off in both, or in either switcher's own table for that one alone.
- Both switchers give each window a letter, drawn as a small key at its title's right (in the window switcher the picked window's key takes the highlight colour). Press it while the capsule is up and the window switcher focuses that window at once; the workspace switcher switches to its workspace and focuses it there. It works held, double-tapped or from a binding. `letters` (default `'asdfgqwertyuiopzxcvbnm'`, without h, j, k and l, which move the pick) sets the letters and their order, handed out left to right; `letter-keys = false` turns them off. Both go in `[switcher]` for both switchers, or in either one's own table for that one alone.

- New `position` in `[window-switcher]` and `[workspace-switcher]` puts the capsule in the middle of the display (`'center'`), below the menu bar (`'top'`), above the Dock (`'bottom'`) or over the pointer even from a key binding (`'mouse'`). `'auto'`, the default, keeps it over the pointer when held and in the middle from a binding. Held away from the pointer, moving the pointer picks what lines up with it.
- New `[switcher]` holds what both switchers share: `enabled`, `delay-ms`, `corner-radius`, `position`, `show-titles`, `letter-keys` and `letters`. Each can also go in `[window-switcher]` or `[workspace-switcher]`, for that one alone, and wins there. `enabled = false` turns a switcher off, its modifier, binding and swipe alike, keeping its settings.
- New `trigger = 'double-tap'` in `[switcher]`, or either switcher's own table, shows the capsule when its modifier is tapped on its own twice instead of held. It stays up at the pointer, as from a key binding: the arrows, Tab, a digit or the pointer pick, Return, Space or a click take the pick and Esc closes it. `double-tap-ms` (default `300`) is how long each tap and the gap between them may last. `'hold'`, the default, keeps the modifier held as before.
- A switcher's `modifier` can be `'hyper'`: the modifiers `[modifiers] hyper` names, `'alt-ctrl-cmd-shift'` by default and two or more of them, held together from either side. Holding and double-tapping work as with one modifier; letting go of any one of them lets go.
- Swipes on the trackpad are set in `[gestures.trackpad]`, with `enabled = false` to turn them off; `fingers`, `distance`, `step` and the swipes directly in `[gestures]` are an error saying where they go now.
- New `[gestures.mouse]` runs `[gestures.trackpad]`'s swipes on a Magic Mouse, two fingers by default since it seldom feels a third, with its own `distance` (8 mm) and `step` (4 mm) for the narrow surface, and its own swipes if set. Fingers already resting on the mouse count, so the swipe starts as the last lands. Driving a switcher, lifted fingers may land again within a moment and go on picking, stroke after stroke; lift them for longer or click to take the pick, right-click to close it. Turn off macOS's two-finger swipe between full-screen apps in System Settings, Mouse, or bind only `swipe-up` and `swipe-down` there; `dinky doctor` says when they clash. It is off until `enabled = true`.

### Highlight colour

- New top-level `highlight-color` sets one colour, `'#rrggbb'` or `'#rrggbbaa'`, for every highlight a table leaves unset: the pick's ring and glow in both switchers, the focused window's border and a drag's preview. Each can still have its own: `highlight-color` in `[switcher]`, or in `[window-switcher]` or `[workspace-switcher]` for one switcher alone, `[borders] active-color` and `[drag] preview-border-color`, and a table's own wins. `'accent'` anywhere means the accent colour in System Settings, following it as it changes. Unset everywhere, everything looks as before.

### Fullscreen

- New `[fullscreen] focus-change` says what Cmd-Tab, a click or `focus` onto another window of the workspace does while one is fullscreen: `'exit'` ends fullscreen, as before; `'follow'` makes the newly focused window fullscreen and puts the other back in its tile; `'keep'` makes it fullscreen too. `fullscreen` again ends it for every window. With `'follow'`, `follow-delay-ms` makes the newly focused window wait until the other is back in its tile.
- On a scrolling workspace, `fullscreen` widens the window's column across the screen and slides its neighbours off either side, their edges showing a gap from it, instead of covering them where they are; when fullscreen ends, the strip slides back to where it was. With `focus-change = 'follow'` or `'keep'`, focusing a neighbour scrolls a whole screen to it. `[fullscreen] scrolling = 'over'` covers them as before.

### Animations

- New `[animations] curve` picks how windows travel: `'spring'`, as before, or one of the [easings.net](https://easings.net) timing functions yabai offers, such as `'ease-out-cubic'`, run over exactly `duration-ms`. `'linear'` and the `ease-in-`, `ease-out-` and `ease-in-out-` forms of `sine`, `quad`, `cubic`, `quart`, `quint`, `expo` and `circ` are there.

### Floating

- New `grid <rows>:<columns>:<x>:<y>:<width>:<height>` command, after yabai's `--grid`: it floats the focused window and places it on cells of a grid over its display, inside the gaps, gliding there with animations on. `grid 1:2:0:0:1:1` puts it on the left half, `grid 3:3:1:1:1:1` in the centre ninth. `grid --toggle` tiles a window that already floats, so one key goes back and forth. In a `[[rules]]` entry it opens an app's new windows there.
- New `cycle-size <percent>...` command steps the focused window through sizes given as percentages of its display, such as `cycle-size 50% 30% 60%`: each press picks the size after the one it has now, or the first. A floating window is centred at that width and height; a tile or scrolling column takes that width and keeps its height.
- The tiling bindings work on floating windows. `move` shifts one by `[floating] move-step` points (50 by default), `resize` grows or shrinks it about its centre, and `fullscreen` fills the display and then puts it back, all inside the gaps. `balance-sizes` and `flatten-workspace-tree` act on the tiles of its workspace. Before, they answered that the window was not tiled.
- `move` takes a number of points for a floating window, as `move left 10` does, in place of `[floating] move-step`, and `[floating] resize-anchor = 'top-left'` makes `resize` grow one to the right and down instead of about its centre.
- `move` and `resize` take `--floating-only`, which leaves a window that does not float alone, for bindings meant only for floating windows.
- New `disk-image` condition in `[[rules]]` matches windows that come from a mounted disk image: the Finder window a .dmg opens, and the windows of an app run from one, such as its installer. `disk-image = true` with `run = 'layout floating'` keeps them out of the tiles.

### Workspaces and displays

- New `recent` target, after yabai's: `workspace recent` shows the workspace focused before the current one, on any display, and `focus-monitor recent` focuses the display focused before the focused one; again, either goes back. `move-window-to-workspace recent` and `move-window-to-display recent` send the focused window there, with `--follow` too. `workspace-back-and-forth` still goes back on the focused display.
- New `free` layout: `[workspace.<number>] layout = 'free'` (or `default-layout = 'free'`) lays nothing out and floats every window on that workspace where it stands, those opened there and those moved there, so `move`, `resize`, `fullscreen` and `cycle-size` work on them from the first press. With `tiling = false` instead, dinky leaves the workspace's windows alone and those bindings answer that the window is not tiled. A window the workspace floated tiles again once it is on a workspace with another layout, or when its own workspace stops being free. There, `grid --toggle` puts a window back where it was before the grid placed it, and `layout` and `join-with` answer that the workspace is free instead of seeming to tile a window it floats again at once. The HUD, the workspace switcher and rules' `workspace-layout` call a workspace dinky does not tile `free`; `workspace-layout = 'floating'` still matches it. `layout floating` on a window that already floats no longer forgets where `fullscreen` and `grid --toggle` took it from.
- `[window-switcher] layouts` takes `'free'`: on a free workspace, or one with `tiling = false`, the capsule is a row of the windows on it, left to right by where they stand. Floating windows on a tiled workspace still stay out of it.
- Bindings by layout: a table in a mode named for a layout, such as `[mode.main.free]` or `[mode.main.scrolling]`, binds keys for a workspace laid out that way. While the focused workspace has that layout, its keys take over from the mode's same keys, and the mode's other keys stay.

### Menu bar

- New top-level `hide-menu-bar-icon = 'single-display'` hides the menu bar item while only one display is connected and shows it again once a second one is. `'always'` hides it, as `menu-bar-icon = 'none'` does; `'never'`, the default, changes nothing.

- The menu bar item shows a block per display, left to right, with the workspace it shows: filled for the focused display, outlined for the others, with corner marks for a full-screen Space, after DeskPeek. `menu-bar-icon = 'text'` brings back the focused display's number. `'none'` hides it.

### Rotate and mirror

- New `rotate <90|180|270>` and `mirror <x-axis|y-axis>` commands, after yabai's `space --rotate` and `--mirror`. `rotate` turns the workspace's tiles clockwise: a quarter turn makes a row a column and a column a row; a half turn reverses everything. `mirror y-axis` swaps left and right, `x-axis` top and bottom. Sizes move with their windows. Fixed and scrolling layouts answer that they are not supported.

### Drag

- Dropping a dragged tile works like yabai's insert feedback. In the middle of the tile under the pointer the two swap, as before; towards an edge that tile splits in two, side by side or one above the other, and the dragged window takes the half on that side. While you drag, an accent border with a translucent fill over that tile shows the part the window will take; a swap is filled more strongly and lights up the dragged window's own tile too, where the other window will go. In the scrolling layout, left and right make the window a column of its own; a fixed layout's grid only swaps.
- `[drag] preview-border-color`, `preview-fill-color` and `preview-border-width` set how the drop's feedback looks, `preview-border-width` for every border including a swap's, as yabai's `insert_feedback_color`. Unset, the border follows the system accent colour and the fill is it at 30%. `home-outline = false` drops the grey outline of the tile the window came from.

### Scripting addition

- A scrolling strip scrolls through dinky's Dock scripting addition wherever it is injected (SIP off; see [Scripting addition](docs/scripting-addition.md)), its windows sliding past the screen edges; without it the strip moves its windows frame by frame. Snapshot glides are gone, and with them `[scrolling] glide`: an old config that still sets it loads, and `dinky doctor` says the key can go.
- New top-level `scripting-addition = false` keeps dinky off its Dock scripting addition, even with SIP off and the addition installed: it neither checks for it nor injects it, and strips move their windows frame by frame. `true`, the default, uses it where it answers.

### Fixes

- On a scrolling workspace, only the column nearest each display edge peeks out; the ones beyond it tuck under it with 2 points on screen, so the edge shows one window's shadow. Before, every parked column hung at the same spot and their shadows piled up into a dark band.
- `focus` from a floating window looks for the nearest window on that window's display. Before, it looked on the main display, so on another display it found the wrong window or none.
- Clicking a picture in picture video, a browser's, IINA's or any other app's, no longer switches to the workspace of the app's window. The video floats on every Space and is no tile, so `follow-app-activation` took the click for a Cmd-Tab to an app with no window here. Leaving picture in picture, with a browser's "back to tab" or the button that takes the video back to IINA's window, still goes to that window's workspace: a click that closes a floating window and shows a window again, or turns its app's window key, on another Space is followed.
- In the scrolling layout, a column scrolled out towards another display hides wholly behind the column in view nearest that display, inside its biggest window, so its shadow hides too, behind a fullscreen window that pushes the strip as well, and that column reaches out to the outer gap at the display's edge. Before, it stopped flush at the display's edge and showed in the outer gap, so the column in view looked as if it floated over it; hidden behind that column, each window piled another shadow on it, and with the strip scrolled to its far end the column stopped short of the edge by the gutter parked windows keep on the other side, about 25 points.
- Restarting dinky leaves windows on their workspaces. Before, quitting moved every window back to the Space it was first seen on, and on the next start rules such as `move-window-to-workspace 2 --follow` and `cycle-size` ran again for windows already open, moving them back, switching workspaces and reshuffling a scrolling strip. Quitting now puts back frames only, `enable off` still puts back Spaces too, and rule commands other than `layout floating`, `layout tiling` and `grid` run only for new windows.
- In the scrolling layout, the focused column stays in view when a column left of it closes or moves to another workspace, grows to a window's minimum width, or when the display or gaps change. Before, the strip kept its scroll position, and the focused column could end up parked off screen.
- Moving the Dock to another edge, resizing it or turning its hiding on or off fits every layout to the space left at once. Before, the tiles kept the area the Dock left them until the next workspace switch, so with the Dock moved to a side the scrolling strip ran under it, and after a resize the gap above or beside the Dock was wrong.
- An app that stops answering no longer holds up dinky, or with it every key and click: dinky asks WindowServer rather than the app which window is in front, gives every Accessibility call half a second at most, talks to the app it focuses off the main thread, and its switcher and drag taps only listen until they have something to take. Before, a stalled editor could hold every click for a second and more.
- An app that does not answer dinky's writes is left alone for one to eight seconds, its newest frames kept for when it answers, instead of being written to again and again; its windows keep their tiles. A window floats only once its Accessibility element is gone. A window whose size stays the same is only moved, one message to its app instead of three.
- On a scrolling workspace, a click on a column's sliver at an edge scrolls it into view and focuses it once it rests; the click no longer reaches the app. A click that moves focus anywhere else lands where it was pressed: the strip scrolls once the button is up.
- On a scrolling workspace, a scroll across more columns than the screen shows slides those in view out and those coming into view in right behind them, about a screen's width however far it goes, instead of sweeping every column between across the screen; the columns between go straight to where it leaves them, out of view. A new `focus` while the strip is still scrolling through the scripting addition carries the scroll on from where it shows, instead of jumping back to where the last one was going.
- Picking a window in Mission Control no longer throws a scrolling strip's windows around. A window `fullscreen` had filled through macOS's Fill and that left fullscreen when another window was focused stayed tiled as far as macOS knew, and Mission Control put it back where its tiling had it as it closed, filling the screen or side by side with another, leaving an empty column in the strip. Such a window now goes through Return to Previous Size the next time it is focused, and once Mission Control closes every workspace on screen is laid out again.
- Snapshots for the switchers are taken once things go quiet after a focus change, together, instead of two at a time as an app comes to the front.
- In the scrolling layout, focusing a column that was hidden behind the column in view at a display's edge, with another display beyond it, keeps it on its own display. Before, it started its glide back where the strip had it, off the screen, which was on the other display, and macOS moved it to that display's Space, out of the strip.
- Connecting or disconnecting a display keeps a scrolling strip's columns in their order. Before, the windows Accessibility could not read for a moment while macOS rearranged the displays floated, and came back into the strip in whatever order they could be read again, at the default width.

## 0.18

### Key bindings

- New `[modifiers]` table picks which key of each modifier pair your bindings answer to: `'both'` (the default), `'left'` or `'right'`. With `alt = 'left'`, left Option runs dinky's bindings and right Option types special characters like `˙` and `≈` as usual.

## 0.17

### Menu

- Layout > Scrolling switches the focused window's workspace to the scrolling layout.

### Fixes

- Switching more than one workspace away no longer stops on the workspaces in between. Before, macOS briefly activated the app on each one it passed, which put that app into the Cmd-Tab order. Multi-step switches are faster too.
- Borders stay on while focus moves during an animation, such as scrolling the scrolling layout. Before, the borders of the window losing focus and the one gaining it blinked off until the windows arrived.
- Switching workspaces works with natural scrolling off. Before, on macOS 27 the swipe went the wrong way and bounced back to the workspace you were on, and following an app from the Dock or Cmd-Tab failed the same way.
- Switching workspaces on macOS before 27 uses the swipe those versions understand. Before, it bounced back there too.

## 0.16

### Tiling

- New `scrolling` layout, after niri and Hyprland: windows open as columns in a row that scrolls past the display edges to the focused one. Columns are 0.49 of the display wide by default, as Omarchy sets them (`[scrolling] column-width`); a lone column fills the display. Columns out of view hang off the edge with a sliver showing, an inner gap from the columns in view, or wait behind the columns in view where another display is beyond.
- `layout scrolling` switches the focused workspace to scrolling and `layout tiles` or `accordion` back, and `layout` with several names now cycles through them: `layout tiles accordion scrolling`.

## 0.15

### Tiling

- New windows open on the focused display, unless a rule moves them.

### Fixes

- An empty workspace activates Finder, even with the desktop turned off, so typing no longer goes to an app on another workspace.

## 0.14

### Install

- The Homebrew cask installs on macOS 15 or later, as the app supports. Before, it asked for a newer macOS.

### Command line

- `dinky -v` prints the version, like `dinky version` and `dinky --version`.

### Fixes

- Switching to an empty workspace keeps focus on its display. Before, macOS could hand focus to a window on another display, so typing and the next `workspace next` went there. `focus-monitor` onto an empty display also takes the keyboard off the other display's window.

## 0.13

### Tiling

- Windows that can't go full screen float on their own, like Finder's copy progress window, About This Mac and Calculator. Terminals and editors that can hide their title bar still tile. Set `float-windows-without-fullscreen = false` to tile them as before, or tile a single app with a `layout tiling` rule.

## 0.12

### Fixes

- Cmd-Tab to an app on another workspace brings that app's window to the front when you get there. Before, another app could stay in front, and for an app with windows on several workspaces dinky could go to the wrong one.

## 0.11

### Fixes

- Obsidian and other Electron apps tile again. Their windows could keep a slot in the layout while staying where they were, with other windows tiling around the empty slot.

## 0.10

### Scripting

- `dinky list-modes --current` prints the binding mode dinky is in, and `mode-changed` hooks get `$DINKY_MODE` and `$DINKY_PREV_MODE`, so a bar can show the mode.

### Menu

- Clear Saved Minimum Sizes in the menu, or `dinky clear-minimum-sizes`, forgets the minimum window sizes dinky has learned for each app, so windows can tile smaller again after an app lowers its minimum.

## 0.9

### Menu

- The menu bar menu has every command: focus, move, join, resize, layout, displays and modes as well as workspaces. Each item shows the key bound to it, and bindings no item covers are listed under Other Key Bindings.

## 0.8

### Fixes

- Sleeping and waking, or anything else that makes displays drop out and come back, no longer piles other workspaces' windows onto workspace 1. Once the displays settle, each window goes back to its workspace.
- After displays come or go, windows that apps moved around on hidden workspaces snap straight back into their tiles when you next visit, instead of gliding in from wherever the app put them.
- `workspace prev` and `workspace next` no longer get stuck on a display with nothing on it. A display focused with `focus-monitor` or `focus --boundaries all-monitors-outer-frame` stops counting as focused once dinky focuses a window or a display comes or goes, even when that window had focus before.

## 0.7

### Fixes

- Unplugging the display dinky was animating on no longer leaves windows stuck mid-glide at odd sizes. Animations continue on the display that is main now, and a glide that stalls for any other reason lands its windows within a couple of seconds.

## 0.6

### Motion

- Windows take about 150 ms to glide to their tiles by default, up from 50. Set `[animations] duration-ms` to change it.

### Fixes

- The minimum sizes dinky learns for an app are kept across quits and `enable off`; restoring windows no longer overwrites them with the ones from launch.
- A new window that reuses a closed window's id is tiled instead of being left where it opened.
- When macOS moves a display's Spaces to another display, their layouts move with them instead of starting over.
- A minimized window keeps its border, hidden, instead of getting a new one when it comes back.
- `move-window-to-display --follow` focuses the moved window as reliably as `move-window-to-workspace --follow` does, instead of sometimes leaving the layout behind on the old window.
- `dinky help` says what `enable off` does: it stops tiling and restores every window.

## 0.5

### Motion

- Windows glide to their tiles instead of jumping. Set the speed with `[animations] duration-ms` (50 by default) or turn it off with `enabled = false`. It's off while macOS's Reduce Motion is on.
- While you drag a tiled window, dinky outlines the tile it came from and the tile it will swap with. The window now swaps with the tile under the pointer, not the one under its centre. `[drag] placeholders = false` turns the outlines off.

### Layouts

- `flatten-workspace-tree` puts windows back into the workspace's configured layout: a fixed grid gets its cells back, and an accordion workspace becomes an accordion again.
- `move` past the edge of an accordion that fills the workspace takes the window out of it, into a tile beside the accordion, as in AeroSpace.

### Other

- dinky warns when another window manager is also running, with a `!` in the menu bar, a line in the menu and in `dinky doctor`. Two window managers undo each other's layouts, which looks like dinky failing to tile.
- The update window shows what changed, and every release is listed at [dinky.rodeo/changelog](https://dinky.rodeo/changelog/).

### Fixes

- Clicking between two windows of the same app moves focus and the border to the window you clicked.
- A window put into native full screen, or slow to finish a resize, no longer teaches dinky that its app can't shrink. That could leave every window of the app filling the screen.

## 0.4

**Upgrading:** workspaces are now numbered across all displays. `workspaces` is the total rather than a count per display, and `workspaces` inside `[display.<pattern>]` is now a config error. Use `[workspace-to-display]` to put a workspace on a particular display.

### Workspaces

- Workspace numbers stay put when you dock or undock. Each workspace is one Space, on the main display unless `[workspace-to-display]` places it elsewhere.
- dinky removes Spaces it no longer needs instead of letting leftovers pile up.
- Tiled windows keep their layout when their workspace moves to another display.
- `workspace N` goes to whichever display the workspace is on; `workspace prev` and `next` step through the focused display's workspaces.
- Queries, hooks and the menu bar use the new global numbers.

### Layouts

- New `fixed` layout: give a workspace a grid with `[workspace.N]` `columns` and `rows`. New windows fill empty cells without resizing the others; when the grid is full, `expand` adds a column, adds a row, or stacks windows in the last cell.
- `default-tiling = false` leaves workspaces untiled unless a `[workspace.N]` table turns tiling on.
- `dwindle` is accepted as another name for the `tiles` layout.

### Fixes

- Cmd-Tab to Helium and Safari web apps switches Spaces again.
- `workspace-back-and-forth` returns to the workspace you were on, not a Space you swiped past.
