# Changelog

## Unreleased

### HUD

- A capsule of Liquid Glass names the new layout, such as `h_accordion` or `scrolling`, after the `layout` command, and the new binding mode when it changes, for a moment on the focused display. The new `[hud]` table places it above the Dock (`position = 'bottom'`, the default) or below the menu bar (`'top'`), `offset` points away, keeps it up for `duration-ms` (1200 by default), and turns it off for either change with `on-layout-change` or `on-mode-change`, or entirely with `enabled = false`.
- When a display moves to another workspace, the capsule shows there the workspace's number and layout, such as `2 · v_accordion`. `[hud] on-workspace-change = false` turns it off.

### Switcher

- New `[window-switcher]`: set `modifier` to `'alt'`, `'ctrl'`, `'cmd'` or `'shift'`, hold it on its own over a workspace, and after `delay-ms` (200 by default) a glass capsule of the workspace's windows shows over the pointer, the focused one under it, in strip order on a scrolling workspace and tree order on an accordion one; move the pointer across to pick one. On a tiles or fixed workspace it is a map of the workspace over the pointer, each tile where it is; move onto one to pick it, or set `tiles-style = 'row'` for a row there too. Release the modifier to focus the window picked; Esc or any other key closes it. `layouts` picks where it shows, `['scrolling', 'tiles']` by default, with `'accordion'` and `'fixed'` too; `corner-radius` rounds the capsule; `show-single = false` leaves a workspace with a lone window out. Thumbnails need Screen Recording, asked for the first time it shows; without it the capsule shows app icons. `[modifiers]` decides which key of the pair counts.
- New `[workspace-switcher]`: hold its own `modifier` on its own and a glass capsule of the workspaces shows over the pointer, a card per workspace drawn small in its layout with the windows where they are: an accordion's neighbours peeking out, a fixed workspace's empty cells, a scrolling workspace's columns in view with a count of those parked either side. Move across to pick one and release to switch to it. Each card has its display's proportions; with more than one display, `displays = 'all'` (the default) shows every display's workspaces, a named group per display, and `'pointer'` only the display under the pointer's. `show-empty`, `exclude`, `card-height`, `thumbnails = 'icons'` or `'schematic'` (a fixed picture of each workspace's layout, whatever its windows) and `corner-radius` tune it. It can't share `[window-switcher]`'s modifier.
- New `window-switcher` and `workspace-switcher` commands show either capsule from a key binding, in the middle of the display under the pointer: the arrows or h, j, k, l and Tab move the pick, Return or Space takes it, Esc closes it, the binding again steps to the next one, and letting go of the binding's modifiers takes the pick, as Cmd-Tab does.

- New `position` in `[window-switcher]` and `[workspace-switcher]` puts the capsule in the middle of the display (`'center'`), below the menu bar (`'top'`), above the Dock (`'bottom'`) or over the pointer even from a key binding (`'mouse'`). `'auto'`, the default, keeps it over the pointer when held and in the middle from a binding. Held away from the pointer, moving the pointer picks what lines up with it. `[workspace-switcher]` takes `[window-switcher]`'s when left out.

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

### Workspaces and displays

- New `recent` target, after yabai's: `workspace recent` shows the workspace focused before the current one, on any display, and `focus-monitor recent` focuses the display focused before the focused one; again, either goes back. `move-window-to-workspace recent` and `move-window-to-display recent` send the focused window there, with `--follow` too. `workspace-back-and-forth` still goes back on the focused display.
- New `[workspace.<number>] float = true` floats every window on that workspace, those opened there and those moved there, so `move`, `resize`, `fullscreen` and `cycle-size` work on them from the first press. With `tiling = false` alone, dinky leaves the workspace's windows alone and those bindings answer that the window is not tiled. A window floated this way keeps floating wherever it goes. There, `grid --toggle` puts a window back where it was before the grid placed it, instead of tiling it.

### Menu bar

- The menu bar item shows a block per display, left to right, with the workspace it shows: filled for the focused display, outlined for the others, with corner marks for a full-screen Space, after DeskPeek. `menu-bar-icon = 'text'` brings back the focused display's number. `'none'` hides it.

### Rotate and mirror

- New `rotate <90|180|270>` and `mirror <x-axis|y-axis>` commands, after yabai's `space --rotate` and `--mirror`. `rotate` turns the workspace's tiles clockwise: a quarter turn makes a row a column and a column a row; a half turn reverses everything. `mirror y-axis` swaps left and right, `x-axis` top and bottom. Sizes move with their windows. Fixed and scrolling layouts answer that they are not supported.

### Drag

- Dropping a dragged tile works like yabai's insert feedback. In the middle of the tile under the pointer the two swap, as before; towards an edge that tile splits in two, side by side or one above the other, and the dragged window takes the half on that side. While you drag, an accent border with a translucent fill over that tile shows the part the window will take; a swap is filled more strongly and lights up the dragged window's own tile too, where the other window will go. In the scrolling layout, left and right make the window a column of its own; a fixed layout's grid only swaps.
- `[drag] preview-border-color`, `preview-fill-color` and `preview-border-width` set how the drop's feedback looks, `preview-border-width` for every border including a swap's, as yabai's `insert_feedback_color`. Unset, the border follows the system accent colour and the fill is it at 30%. `home-outline = false` drops the grey outline of the tile the window came from.
- Dragging or gliding a window is lighter: each step of its move reads only the window's frame, and the rest of it, such as the Space it was dropped on, once it has been still for a moment.

### Rules

- New `app-id-regex` key matches the bundle ID by regex, like `app-name` does for the app's name: `app-id-regex = '^com\.jetbrains\.'` covers every JetBrains app with one rule. `app-id` still matches exactly.

### Key bindings

- `hyper` and `meh` name the usual modifier combinations: `hyper-1` is `alt-ctrl-cmd-shift-1`, and `meh-1` is `alt-ctrl-shift-1`.

### Fixes

- On a scrolling workspace, only the column nearest each display edge peeks out; the ones beyond it tuck under it with 2 points on screen, so the edge shows one window's shadow. Before, every parked column hung at the same spot and their shadows piled up into a dark band. With `glide = 'snapshots'`, the peeks stay put through a scroll instead of vanishing and fading back.
- `focus` from a floating window looks for the nearest window on that window's display. Before, it looked on the main display, so on another display it found the wrong window or none.
- Clicking a picture in picture video, a browser's, IINA's or any other app's, no longer switches to the workspace of the app's window. The video floats on every Space and is no tile, so `follow-app-activation` took the click for a Cmd-Tab to an app with no window here. Leaving picture in picture, with a browser's "back to tab" or the button that takes the video back to IINA's window, still goes to that window's workspace: a click that closes a floating window and shows a window again, or turns its app's window key, on another Space is followed.
- In the scrolling layout, a column scrolled out towards another display hides wholly behind the column in view nearest that display, in the place of its biggest window. Before, it stopped flush at the display's edge and showed in the outer gap, so the column in view looked as if it floated over it.
- Restarting dinky leaves windows on their workspaces. Before, quitting moved every window back to the Space it was first seen on, and on the next start rules such as `move-window-to-workspace 2 --follow` and `cycle-size` ran again for windows already open, moving them back, switching workspaces and reshuffling a scrolling strip. Quitting now puts back frames only, `enable off` still puts back Spaces too, and rule commands other than `layout floating`, `layout tiling` and `grid` run only for new windows.
- In the scrolling layout, the focused column stays in view when a column left of it closes or moves to another workspace, grows to a window's minimum width, or when the display or gaps change. Before, the strip kept its scroll position, and the focused column could end up parked off screen.
- Moving the Dock to another edge, resizing it or turning its hiding on or off fits every layout to the space left at once. Before, the tiles kept the area the Dock left them until the next workspace switch, so with the Dock moved to a side the scrolling strip ran under it, and after a resize the gap above or beside the Dock was wrong.
- A `layout` command keeps a `fixed` workspace's template when it leaves its shape alone, such as one that changes nothing or turns the overflow accordion vertical, so later windows still fill the grid.
- dinky keeps tiling a window after its app closes and reopens it, as Slack does when you close its window with Cmd-W and open it again from the Dock.

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
