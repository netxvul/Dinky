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
| `move <left\|down\|up\|right>` | Move the focused window in the tree. A floating window moves `[floating] move-step` points; see [Floating windows](#floating-windows). |
| `join-with <left\|down\|up\|right>` | Put the focused window and its neighbour in a new container. |
| `resize <smart\|width\|height> <+n\|-n>` | Resize by n points. A floating window grows about its centre. |
| `layout <tiles\|accordion\|horizontal\|vertical\|auto\|h_tiles\|v_tiles\|h_accordion\|v_accordion\|floating\|tiling\|scrolling>...` | Set the container's layout, float/tile the window, or switch the workspace to [scrolling](configuration.md#scrolling); a container layout switches it back. Given several, applies the one after the current one, so `layout floating tiling` toggles and `layout tiles accordion scrolling` cycles. Acts on the focused window, tiling it first if it floats, so it does nothing on an empty workspace. |
| `fullscreen` | Toggle filling the workspace (not macOS full screen). [`[fullscreen] focus-change`](configuration.md#fullscreen) says what focusing another window does meanwhile. A floating window fills its display, then goes back. |
| `grid [--toggle] <rows>:<columns>:<x>:<y>:<width>:<height>` | Float the focused window and glide it onto a grid over its display, as yabai's `--grid`. `--toggle` tiles a floating window instead. See [Grid](#grid). |
| `flatten-workspace-tree` | Put every window back into the workspace's layout, in order, undoing tree edits. A scrolling workspace keeps its column widths. |
| `balance-sizes` | Give every window an equal share. |
| `retile` | Re-read windows and re-apply every layout. |
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
| `move <direction>` | Moves it [`[floating] move-step`](configuration.md#floating) points, 50 by default, the same size. It stops at the edge of the display's visible area, inside the outer gaps. |
| `resize width\|height <+n\|-n>` | Grows or shrinks it by n points along that axis, about its centre, so a centred window stays centred. |
| `resize smart <+n\|-n>` | The same, in both width and height. |
| `fullscreen` | Fills the display's visible area inside the outer gaps, as fullscreen does for a tile. Again, it goes back to where it was. The place is remembered until dinky quits. |
| `balance-sizes`, `flatten-workspace-tree` | Act on the tiles of its workspace. |
| `join-with <direction>` | An error: a floating window has no neighbour in the tree. Tile it first. |

A resized window is no smaller than 100 by 100 points nor larger than the
visible area, and stays inside it. Apps that refuse a size, such as Safari
below its minimum width, keep the size they accept.

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
floats a window onto the grid and the next puts it back:

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
off`, quitting, `kill` and logging out put them all back. After a crash, the
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
