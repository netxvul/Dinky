---
layout: default
title: Commands
description: dinky commands, the command line and socket, and scripting a bar.
permalink: /commands/
---

# Commands

Key bindings, `dinky <command>` and the menu share one vocabulary. `dinky help`
prints it.

<div class="wide-table" markdown="1">

| Command | |
|---|---|
| `workspace <n\|prev\|next\|recent>` | Show a workspace and focus its display. `prev`/`next` step through the focused display's and don't wrap. `recent` is the workspace focused before the current one, on any display, as yabai's `recent`; again, it goes back. |
| `workspace-back-and-forth` | Switch to the previous workspace of the focused display. |
| `move-window-to-workspace <n\|prev\|next\|recent> [--follow]` | Move the focused window, and with `--follow` go too. |
| `move-window-to-display <next\|prev\|recent> [--follow]` | Move the focused window to another display's workspace. `recent` is the display focused before the focused one. |
| `focus <left\|down\|up\|right> [--boundaries <b>] [--boundaries-action <a>]` | Focus the nearest window. `--boundaries` is `workspace` (default) or `all-monitors-outer-frame`, which continues onto the next display. `--boundaries-action` is `stop` (default), `fail`, `wrap-around-the-workspace` (`--wrap-around`) or `wrap-around-all-monitors`, which needs `all-monitors-outer-frame`. |
| `focus-monitor <left\|down\|up\|right\|next\|prev\|recent\|n>` | Focus a display. `recent` is the one focused before the focused one. |
| `move <left\|down\|up\|right> [<points>] [--floating-only]` | Move the focused window in the tree. A floating window moves that many points, `[floating] move-step` without a number; see [Floating windows](#floating-windows). |
| `join-with <left\|down\|up\|right>` | Put the focused window and its neighbour in a new container. |
| `resize <smart\|width\|height> <+n\|-n> [--floating-only]` | Resize by n points. A floating window grows about its centre, or its top-left corner with `[floating] resize-anchor`. |
| `layout <tiles\|accordion\|horizontal\|vertical\|auto\|h_tiles\|v_tiles\|h_accordion\|v_accordion\|floating\|tiling\|scrolling>...` | Set the container's layout, float/tile the window, or switch the workspace to [scrolling](configuration.md#scrolling); a container layout switches it back. Given several, applies the one after the current one, so `layout floating tiling` toggles and `layout tiles accordion scrolling` cycles. Acts on the focused window, tiling it first if it floats, so it does nothing on an empty workspace. On a [free](configuration.md#workspacenumber) workspace, where every window floats, anything but `floating` is an error. |
| `fullscreen` | Toggle filling the workspace (not macOS full screen). [`[fullscreen] focus-change`](configuration.md#fullscreen) says what focusing another window does meanwhile. A floating window fills its display, then goes back. A lone window that already fills its workspace stays as it is with `focus-change = 'exit'`, the default. |
| `grid [--toggle] <rows>:<columns>:<x>:<y>:<width>:<height>` | Float the focused window and glide it onto a grid over its display, as yabai's `--grid`. `--toggle` tiles a floating window instead, or on a free workspace puts it back where it was. See [Grid](#grid). |
| `cycle-size <percent>...` | Step the focused window to the next of these sizes, as percentages of its display. A floating window is centred at that width and height; a tile or scrolling column takes that width. See [Cycle size](#cycle-size). |
| `pin <left\|right> [--toggle]` | Pin the focused window's column to that side of the screen in a scrolling workspace, the other columns scrolling between. Pinned there already it stays, or with `--toggle` is unpinned. See [Pins](#pins). |
| `focus-pin <left\|right>` | Focus the column pinned to that side without scrolling; again, back to the band window focused last. |
| `unpin [left\|right]` | Unpin the column pinned to that side, or the focused window's: it goes back between the columns it was pinned from. |
| `flatten-workspace-tree` | Put every window back into the workspace's layout, in order, undoing tree edits. A scrolling workspace keeps its column widths. |
| `balance-sizes` | Give every window an equal share. |
| `rotate <90\|180\|270>` | Turn the workspace's tiles clockwise, as yabai's `space --rotate`: a quarter turn makes a row a column, its first window on top, and a column a row, its top window on the right; a half turn reverses everything. A container set to `auto` keeps the turned axis as its orientation. Not for fixed or scrolling layouts. |
| `mirror <x-axis\|y-axis>` | Flip the workspace's tiles, as yabai's `space --mirror`: `y-axis` swaps left and right, `x-axis` top and bottom. Not for fixed or scrolling layouts. |
| `retile` | Re-read windows and re-apply every layout. |
| `window-switcher` | Show the [window switcher](configuration.md#window-switcher) in the middle of the display under the pointer, for a key binding. The arrows or h, j, k, l move the pick, Tab and Shift-Tab step through, Return or Space focuses the window, a window's letter focuses it at once and Esc closes it. Run again while it shows, it steps to the next one; from a binding with modifiers, letting go of them takes the pick, as Cmd-Tab does. |
| `workspace-switcher` | Show the [workspace switcher](configuration.md#workspace-switcher) the same way; Return or Space switches to the workspace picked, and a window's letter switches to its workspace and focuses it. |
| `clear-minimum-sizes` | Forget the minimum window sizes learned for every app and re-apply every layout. |
| `mode <name>` | Switch binding mode. |
| `reload-config` | Reload the config. |
| `enable <on\|off\|toggle>` | Turn dinky on or off. Off restores windows and turns key bindings off too, so turn it back on from the menu or with `dinky enable on`. |
| `list-workspaces`, `list-windows`, `list-monitors`, `list-displays`, `list-modes` | See [Scripting](#scripting). `list-displays` = `list-monitors`. |
| `debug-state` | Tiling state as JSON, for bug reports. |
| `exec-and-forget <shell command>` | Run with `/bin/sh -c` without waiting. Output goes to the log. |

</div>

Workspaces are numbered across displays; see
[`[workspace-to-display]`](configuration.md#workspace-to-display). A full-screen
app's Space has no number, nor does the Space of a display without workspaces.

## Floating windows

The tiling bindings work on a floating window too, so the same keys move and
size it. With animations on, it glides.

| Command | On a floating window |
|---|---|
| `focus <direction>` | The nearest window on its display whose centre lies that way. |
| `move <direction> [<points>]` | Moves it that many points, or [`[floating] move-step`](configuration.md#floating) (50 by default) without a number, the same size. It stops at the edge of the display's visible area, inside the outer gaps. A tile ignores the number. |
| `resize width\|height <+n\|-n>` | Grows or shrinks it by n points along that axis, about its centre, so a centred window stays centred, or from its top-left corner with [`[floating] resize-anchor = 'top-left'`](configuration.md#floating). |
| `resize smart <+n\|-n>` | The same, in both width and height. |
| `cycle-size <percent>...` | Centres it at the next of the sizes, that share of the visible area's width and height inside the outer gaps. |
| `fullscreen` | Fills the display's visible area inside the outer gaps, as fullscreen does for a tile. Again, it goes back to where it was. The place is remembered until dinky quits. |
| `balance-sizes`, `flatten-workspace-tree` | Act on the tiles of its workspace. |
| `join-with <direction>` | An error: a floating window has no neighbour in the tree. Tile it first. On a [free](configuration.md#workspacenumber) workspace, where nothing tiles, it answers that the workspace is free. |

A resized window is no smaller than 100 by 100 points nor larger than the
visible area, and stays inside it. Apps that refuse a size, such as Safari
below its minimum width, keep the size they accept.

`--floating-only` on `move` and `resize` leaves a window that does not float
alone, so keys meant for floating windows never rearrange the tiles when a tile
has focus. A mode for adjusting floating windows can use it throughout:

```toml
[mode.main]
alt-g = ['layout floating', 'mode floating']

[mode.floating]
h = 'move left --floating-only'
l = 'move right --floating-only'
ctrl-h = 'move left 10 --floating-only'
ctrl-l = 'move right 10 --floating-only'
shift-h = 'resize width -50 --floating-only'
shift-l = 'resize width +50 --floating-only'
esc = 'mode main'
```

## Pins

In a [scrolling](configuration.md#scrolling) workspace, `pin left` or `pin right`
holds the focused window's column at that side of the screen, after SlideScroll,
while the other columns scroll in the band between. Each side holds one column,
a single window or a stack. A pinned column keeps its width, a share of the
screen inside the outer gaps, and the band keeps at least a quarter of it and
room for its widest window; a pin or a resize that would leave less is refused.

- Focusing a pin never scrolls. From the band's first column, focusing towards
  the pin focuses it; from the pin, focusing inwards goes back to the band window
  focused last. Outwards from a pin, focus goes on as at the workspace's edge:
  to the next display, or around the workspace with `wrap-around-the-workspace`.
- Columns scrolled out of the band slide under the pin and park at the screen's
  edge with only a sliver showing. The pin is raised in front of them as they
  slide under it, after a focus change, Cmd-Tab, a click in the Dock or a new
  window. The focused window of the pin's own app is raised after the pin, to
  keep its app's focus, so it can show over the pin while sliding past.
- `move` leaves a pinned column where it is; `join-with` into a pin stacks the
  window there, and out of a pin of one window unpins it. A window dragged beside
  a pin goes into the band, swapped onto it takes its place.
- A window in the band filling the workspace with [`fullscreen`](#commands) fills
  the band with `[fullscreen] scrolling = 'push'`, the default, or covers the
  screen with `'over'`; a pinned one covers the screen either way.
- `pin left` again changes nothing, so a rule can run it safely; `--toggle`
  unpins. Pinning a side another column holds sends that column back to where it
  was pinned from, and pinning the other side's column moves it across.
- `unpin` puts the column back between the columns it was pinned from.
- `focus-pin left` jumps straight to the left pin, however far the band is
  scrolled, and again goes back to where focus was in the band.

Nothing is bound by default. For example:

```toml
[mode.main]
alt-p = 'pin left --toggle'
alt-shift-p = 'pin right --toggle'
```

## Grid

`grid [--toggle] <rows>:<columns>:<x>:<y>:<width>:<height>` places the focused
window the way yabai's `window --grid` does. dinky splits the display's visible area
(without the menu bar and Dock, inside the outer gaps) into `rows` by `columns`
equal cells, with the inner gaps between them. The window takes `width` by
`height` cells, starting at column `x` and row `y`, counted from 0 at the top
left. A tiled window floats first; `layout tiling` puts it back in the layout.
With animations on, the window glides to its cells while the tiles it left
close up.

With `--toggle`, a window that already floats is tiled instead, so one key
floats a window onto the grid and the next puts it back. On a
[free](configuration.md#workspacenumber) workspace, which floats every window,
the next press puts it back where it was before the grid placed it:

```toml
[mode.main]
alt-t = 'grid --toggle 6:6:1:1:4:4'
```

| Command | Places the window |
|---|---|
| `grid 1:1:0:0:1:1` | Over the whole display. |
| `grid 1:2:0:0:1:1` | On the left half. |
| `grid 1:2:1:0:1:1` | On the right half. |
| `grid 2:2:1:0:1:1` | In the top right quarter. |
| `grid 1:3:0:0:2:1` | Across the left two thirds. |
| `grid 3:3:1:1:1:1` | In the centre ninth. |
| `grid 6:6:1:1:4:4` | In the middle, a sixth in from every edge. |

With the same gaps as the tiles, a window on a grid lines up with tiles of the
same size. `x + width` must not be more than `columns`, nor `y + height` more
than `rows`.

Bind them in a mode to keep `alt` free, or use them in a
[rule](configuration.md#rules) to open an app's windows in place:

```toml
[mode.main]
alt-g = 'mode grid'

[mode.grid]
esc = 'mode main'
h = ['grid 1:2:0:0:1:1', 'mode main']
l = ['grid 1:2:1:0:1:1', 'mode main']
f = ['grid 1:1:0:0:1:1', 'mode main']
c = ['grid 6:6:1:1:4:4', 'mode main']
t = ['layout tiling', 'mode main']
```

## Cycle size

`cycle-size <percent>...` steps the focused window through a list of sizes,
given as percentages of its display: each press picks the size after the one
the window has now, wrapping, or the first when it has none of them. A size
within 2% counts, for apps that snap to a grid or keep a minimum size.

```toml
[mode.main]
alt-c = 'cycle-size 50% 30% 60%'
```

| Window | What changes |
|---|---|
| Floating | Centred on its display at that share of the visible area's width and height, inside the outer gaps. |
| Tile | Its width, along the nearest container whose tiles sit side by side; its siblings give or take the difference as `resize width` has them. A window with no side-by-side neighbour has nothing to resize. |
| Scrolling column | The column's width, as a share of the screen. A lone column always fills the screen, or the band beside a pin. |

Heights of tiles and columns stay. A window stays floating or tiled.

## Command line

The app binary is the CLI. `dinky <command>` sends a command to the running app
and exits 1 on errors or when it isn't running. CLI-only commands:

| Command | |
|---|---|
| `app` | Run the app in the foreground, logging to the terminal. |
| `doctor [--config <path>]` | Check the config and macOS settings, and that no other tiling window manager is running. |
| `recover` | Ask the running app to restore windows a crashed session left tiled. |
| `debug events\|windows` | Print window events or windows, without the app. |
| `version`, `-v`, `--version` | Print the version and build number. |

The log is `~/Library/Logs/dinky.log`; attach it to bug reports.

Scripts can skip the CLI and talk to the socket: one command per connection,
answered with `ok` or `error` and the reply.

```sh
printf 'workspace 2\n' | nc -U "$TMPDIR/dinky.sock"
```

## Recovery

dinky journals each window's original frame and Space before tiling it. `enable
off` puts them all back. Quitting, `kill` and logging out put back the frames
but leave each window on the Space it is on, so dinky started again finds the
windows on the workspaces they were tiled on. After a crash, the
menu offers to restore them (or `dinky recover`); dinky stays off until `dinky
enable on`.

## Scripting

The queries follow [AeroSpace](https://nikitabobko.github.io/AeroSpace/commands)'s
names, flags and output, so most AeroSpace bar scripts work by swapping the
command name.

<div class="wide-table" markdown="1">

| Query | Flags | Default format |
|---|---|---|
| `list-workspaces` | `--all`, `--focused`, `--monitor <focused\|all\|n>...`, `--visible [no]`, `--empty [no]`, `--format` | `%{workspace}` |
| `list-windows` | `--all`, `--focused`, `--monitor <focused\|all\|n>...`, `--workspace <focused\|visible\|n>...`, `--app-bundle-id <id>` (or `--app-id`), `--format` | `%{window-id}%{right-padding} \| %{app-name}%{right-padding} \| %{window-title}` |
| `list-monitors` | `--focused [no]`, `--format` | `%{monitor-id}%{right-padding} \| %{monitor-name}` |
| `list-modes` | `--current` | Mode names, `main` first |

</div>

Without a display flag, `list-workspaces` and `list-windows` cover the focused
display; `list-monitors` lists every display. Format variables:

- `%{right-padding}`, `%{newline}`, `%{tab}`
- Workspaces: `workspace`, `workspace-is-focused`, `workspace-is-visible`,
  `monitor-id`, `monitor-name`, `monitor-is-main`
- Windows: `window-id`, `window-title`, `window-layout`,
  `window-parent-container-layout`, `window-is-floating`,
  `window-is-fullscreen`, `app-name`, `app-bundle-id`, `app-pid`, and the
  workspace variables

`%{monitor-is-main}` tells a bar which workspaces are on the side display.

### SketchyBar

Drive a bar from the config's [hooks](configuration.md#hooks):

```toml
[hooks]
startup = ['exec-and-forget brew services restart sketchybar']
workspace-changing = ['exec-and-forget sketchybar --trigger workspace_changing DINKY_DISPLAY=$DINKY_DISPLAY DINKY_WORKSPACE=$DINKY_WORKSPACE']
workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change WORKSPACE=$DINKY_WORKSPACE']
focus-changed = ['exec-and-forget sketchybar --trigger focus_changed']
mode-changed = ['exec-and-forget sketchybar --trigger mode_changed MODE=$DINKY_MODE']
```

The workspace hooks set `DINKY_WORKSPACE` (empty on a full-screen Space),
`DINKY_PREV_WORKSPACE` and `DINKY_DISPLAY` (1-based). `workspace-changing`
fires only for dinky's own switches, so draw the target there and the real
state on `workspace-changed`, which always follows. `mode-changed` sets
`DINKY_MODE` and `DINKY_PREV_MODE`; `dinky list-modes --current` prints the
mode at any time. `exec-and-forget` has Homebrew on `PATH`.
