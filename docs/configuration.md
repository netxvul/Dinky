---
layout: default
title: Configuration
description: dinky's TOML config, every key and its default, and the key syntax.
permalink: /configuration/
---

# Configuration

`~/.config/dinky/dinky.toml`, written on first run and reloaded on save.

- Every key is optional; a missing key keeps the default below. Without
  `[mode.main]` there are no bindings, without `[[rules]]` no rules.
- Unknown keys are errors. A broken config does not load: the previous one
  stays and the error shows in the menu.
- `dinky doctor [--config <path>]` also checks commands, modes and key names.
- The [JSON Schema](schemas/dinky.json) gives completion in editors that read
  Taplo's `#:schema` line, such as Zed or VS Code with Even Better TOML.

## Top level

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `start-at-login` | `true` | Register as a login item. |
| `workspaces` | `5` | Workspaces across all displays, one native Space each. dinky creates and removes Spaces to match. |
| `default-layout` | `'tiles'` | `'tiles'` (the existing dwindle layout), `'dwindle'`, `'accordion'`, `'fixed'`, or `'scrolling'`. |
| `default-tiling` | `true` | Set `false` to leave workspaces untiled unless overridden. |
| `follow-app-activation` | `true` | Cmd-Tab and Dock clicks switch Spaces the fast way. Needs the macOS "switch to a Space with open windows" setting off. |
| `float-windows-without-fullscreen` | `true` | Float windows that can't go full screen, such as Finder's copy progress, About This Mac and Calculator. Terminals and editors that can hide their title bar still tile. A `layout tiling` rule tiles a window anyway. |

</div>

## `[workspace.<number>]`

Override the top-level `default-tiling` and `default-layout` for a globally
numbered workspace.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `tiling` | `default-tiling` | Whether the workspace tiles. |
| `layout` | `default-layout` | Its layout, with the same values. |
| `columns`, `rows` | `1` | A fixed layout's template. |
| `expand` | `'columns'` | What a fixed layout does when every cell is taken. |

</div>

 `layout = 'fixed'` reserves every cell in its template from the start.
`rows` and `columns` each default to `1`; with two columns and three rows, one
window occupies one sixth of the workspace, and an empty cell stays empty when
another window closes. New windows fill holes first, left to right, top to bottom.

When all cells are occupied, `expand` chooses what happens next: `'columns'`
(default) adds a column, `'rows'` adds a row, or `'accordion'` stacks overflow
windows in the last cell. Expansion resizes existing cells but does not rearrange
their positions. An overflow row or column disappears once empty; reserved
template cells remain. A tree command can still edit the layout; if it changes the
template structure, new windows split the focused tile instead of resetting
those edits. Changing template settings in the config rebuilds the tree once.

For example, to tile only workspace 2 (and send new Ghostty windows there using a rule):

```toml
default-tiling = false

[workspace.2]
tiling = true
layout = 'fixed'
columns = 2
rows = 3
# expand = 'columns' # or 'rows' or 'accordion'

[[rules]]
app-id = 'com.mitchellh.ghostty'
run = 'move-window-to-workspace 2'
```

`rows`, `columns`, and `expand` are only allowed with a fixed layout; with any
other they are a config error. `layout = 'accordion'`
remains available; conceptually it resembles a 1×1 fixed template with accordion
overflow, but keeps the existing accordion orientation behavior. Workspace
numbering starts at 1.

## Scrolling

`layout = 'scrolling'` lays a workspace out as a row of columns that runs past
the edges of the display, as niri and Hyprland's scrolling layout do. Each new
window opens as a column right of the focused one, `column-width` wide whatever
the number of columns. A lone column fills the display; columns that fit are
centred; focusing a column scrolls just far enough to show it whole.

macOS can't hide part of another app's window, so a column scrolled out of view
is parked: it hangs off the display edge with a sliver of at least 25 points
left on, an inner gap from the columns in view. Where another display sits beyond that edge, the column stops
at the border instead and waits behind the columns in view.

Commands work on columns. `focus left` and `right` move between columns, `up`
and `down` within one. `move left` and `right` swap the column with its
neighbour, or take a window that shares its column out into a new column.
`join-with left` and `right` put the window into the neighbouring column.
`resize width` (and `smart`) changes the column's width, `resize height` the
window's share of its column; `balance-sizes` resets them all. Hover focus
leaves columns that are not wholly in view alone; a click scrolls to them.

```toml
[workspace.1]
layout = 'scrolling'
```

`layout scrolling` switches the focused window's workspace to scrolling on the fly, and
`layout tiles` or `accordion` switches it back to its tree. The switch holds
until you switch again. To cycle all three on one key:

```toml
[mode.main]
ctrl-alt-cmd-s = 'layout tiles accordion scrolling'
```

## `[scrolling]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `column-width` | `0.49` | A new column's width, as a share of the display inside the outer gaps, from `0.1` to `1`. Omarchy's `0.49` fits two columns side by side. |

</div>

## `[fullscreen]`

`fullscreen` makes the focused window fill its workspace over the tree. This
table says what happens when another window of the same workspace takes focus,
by Cmd-Tab, a click, `focus`, a new window or the fullscreen window closing.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `focus-change` | `'exit'` | `'exit'`: fullscreen ends and the window goes back to its tile. `'follow'`: the newly focused window goes fullscreen and the other goes back to its tile. `'keep'`: the newly focused window goes fullscreen too, and the other stays fullscreen behind it. |
| `follow-delay-ms` | `0` | With `'follow'`, how long the newly focused window waits in its tile before going fullscreen, from `0` to `5000`, so the window it took over from is back in its tile first. `0` swaps them at the same time. About `duration-ms` waits for the glide back; a little more lets it settle. |

</div>

With a delay, focusing yet another window while one waits hands the wait on to
that window, and `fullscreen` during the wait ends it. When the fullscreen
window closes, the next one goes fullscreen at once, since nothing has to move
back.

With `'keep'`, every window focused while one is fullscreen joins it, the
focused one in front. `fullscreen` again, or any layout command, ends
fullscreen for all of them. Floating windows and other workspaces are not
affected.

```toml
[fullscreen]
focus-change = 'follow'
follow-delay-ms = 200   # the other window glides back first
```

## `[floating]`

What the tiling commands do to a floating window; see
[Floating windows](commands.md#floating-windows).

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `move-step` | `50` | Points `move` shifts a floating window by, from `1` to `1000`. |

</div>

## `[accordion]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `padding` | `30` | Points the neighbours peek out by. |
| `orientation` | `'auto'` | On switching to accordion, `'auto'` runs along the container's longer side; `'keep'` keeps its orientation. An orientation set with `layout` is always kept. |

</div>

## `[gaps]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `inner` | `8` | Between windows. Or `{ horizontal = 8, vertical = 6 }`. |
| `outer` | `8` | To the screen edge. Or `{ top = 44, bottom = 8, left = 8, right = 8 }`, or `outer.top = 44`. |

</div>

## `[workspace-to-display]`

Which display a workspace lives on, by number. A display pattern is `main`,
`secondary` (the other one, when there are two), or part of the name from
`dinky list-displays`. A list tries each in turn. Unlisted workspaces, and
listed ones whose display isn't connected, live on the main display.

```toml
[workspace-to-display]
5 = 'secondary'         # on the side display while it's connected, else a normal workspace
4 = ['dell', 'lg']
```

When a display comes or goes, dinky moves the workspace's windows, layout
included, to a Space on its display and removes the Space left behind. Empty
leftover Spaces are removed; ones with windows are left alone, unnumbered. A
display with no workspaces keeps one unnumbered Space. Windows macOS piles onto
another workspace when a display goes away, as around sleep, go back to their
own workspace once the displays settle.

## `[display.<pattern>]`

Per-display `gaps`, with the patterns above. Name patterns beat
`main`/`secondary`; longer names beat shorter.

```toml
[display.main]          # the display with the bar
gaps.outer.top = 44
```

## `[borders]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `true` | |
| `width` | `4` | Points; may be fractional. |
| `active-color` | `'#e1e3e4'` | `'#rrggbb'` or `'#rrggbbaa'`. |
| `inactive-color` | `'#494d64'` | |
| `order` | `'below'` | `'above'` draws a click-through ring over the window. |
| `exclude-apps` | `[]` | Bundle IDs that get no border. |

</div>

## `[focus-follows-mouse]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `false` | Focus the managed window the pointer rests on. Ignored while a button is down or a menu is open, and until the pointer moves to another window after Cmd-Tab or a Space change. |
| `delay-ms` | `100` | How long the pointer must rest. |
| `accordion-edges` | `true` | Resting on a peeking accordion edge focuses that window. |

</div>

## `[animations]`

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `true` | Windows glide to their tiles instead of jumping. Off while macOS's Reduce Motion is on. |
| `duration-ms` | `150` | Roughly how long a window takes to arrive on the spring, exactly how long along an easing, up to 1000. `0` jumps. |
| `curve` | `'spring'` | How windows travel; see below. |

</div>

`curve = 'spring'` puts each window on a spring that settles without bouncing.
A command pressed again mid-glide bends the motion towards the new place,
keeping its speed.

Any other value is a timing function from [easings.net](https://easings.net),
as yabai's `window_animation_easing` offers, run over exactly `duration-ms`:
`'linear'`, or `'ease-in-'`, `'ease-out-'` or `'ease-in-out-'` followed by
`sine`, `quad`, `cubic`, `quart`, `quint`, `expo` or `circ`, such as
`'ease-out-cubic'`. Ease-out curves start fast and slow down into place, which
suits windows best; ease-in curves start slowly. From `sine` to `expo` each is
steeper than the last. A command pressed again mid-glide starts the curve over
from where the window is.

```toml
[animations]
duration-ms = 250
curve = 'ease-out-quart'
```

## `[drag]`

Drag a tiled window's edge to resize it; the other tiles make room, and in the
scrolling layout its column takes the new width. Drag the window itself and
drop it on another tile, and the tile under the pointer shows where it will go,
as yabai's insert feedback does: in the middle of the tile the two swap, and
towards an edge the tile splits in two, side by side or one above the other,
with the window in the half on that side. A swap is drawn heavier, and the
dragged window's own tile lights up too, where the other window will go. In the
scrolling layout, dropping left
or right of a tile makes the window a column of its own there. A fixed layout's
grid only swaps. Dropped anywhere else, the window goes back.

With `modifier` set, holding it lets you drag a tiled window from anywhere in it,
not just its title bar, as yabai's `mouse_modifier` does. Hold the modifier and
click without moving to leave the window where it is.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `placeholders` | `true` | While you drag a tiled window, outline the tile it came from, and show over the tile under the pointer the part the window will take. |
| `modifier` | `'none'` | Modifiers that, held, drag a tiled window from anywhere in it, not just its title bar: `'alt'`, `'ctrl-alt'` or any of `alt`, `ctrl`, `cmd` and `shift` joined by `-`. The click goes to dinky, not the app. `'none'` turns it off. |
| `preview-border-color` | accent colour | The border of the part of the tile the window will take: `'#rrggbb'` or `'#rrggbbaa'`. Unset, it follows the accent colour in System Settings. The faint outline of the whole tile around a half is this colour at 40%. |
| `preview-fill-color` | border at 30% | The fill of that part, `'#rrggbbaa'` for a translucent one such as `'#7aa2f74d'`. |
| `preview-border-width` | `3` | Points, from `0` to `20`, for the preview and the outlines of the tiles. |
| `home-outline` | `true` | Outline the tile the window came from in grey while you drag. `false` shows only the feedback over the tile under the pointer. |

</div>

## `[modifiers]`

Which key of each modifier pair a binding's modifier means. Limit `alt` to one
side and the other Option key types special characters as usual: with
`alt = 'left'`, left Option-h focuses left and right Option-h types `˙`.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `alt` | `'both'` | `'both'`, `'left'` or `'right'`: which Option key is `alt` in bindings. |
| `ctrl` | `'both'` | The same for Control. |
| `cmd` | `'both'` | The same for Command. |
| `shift` | `'both'` | The same for Shift. |

</div>

## `[hooks]`

Commands run on events. See [Scripting](commands.md#scripting) for the
environment `exec-and-forget` gets.

<div class="wide-table" markdown="1">

| Key | Runs |
|---|---|
| `startup` | Once, after dinky has read the windows and displays. |
| `workspace-changing` | When a dinky switch starts, before it lands, and again when a burst of switches changes the target. |
| `workspace-changed` | When a display's workspace changes, or a switch gives up. |
| `focus-changed` | When focus changes, debounced 50 ms. |
| `mode-changed` | When the binding mode changes, including back to `main` when the config reloads. Sets `DINKY_MODE` and `DINKY_PREV_MODE`. |

</div>

## `[[rules]]`

Every rule whose conditions all match a new window runs, in order. Dialogs,
sheets, panels and fixed-size windows always float. Windows that can't go full
screen float too while `float-windows-without-fullscreen` is on, unless a
`layout tiling` rule tiles them.

A rule that is exactly `layout floating` or `layout tiling` decides before the
window is placed, the last one winning. A `grid` rule floats the window too, so
it goes straight to its cells without being tiled first. Every other rule
command runs once the window is placed, on that window.

New windows open on the focused display, whichever display the app picked. A
rule that moves the window, such as `move-window-to-workspace`, decides where
it goes instead.

<div class="wide-table" markdown="1">

| Key | |
|---|---|
| `app-id` | Bundle ID. |
| `app-name` | Case-insensitive regex. |
| `title` | Case-insensitive regex. |
| `kind` | `'normal'`, `'dialog'`, `'sheet'` or `'panel'`. |
| `run` | Required. A command or a list. |

</div>

```toml
[[rules]]
app-id = 'com.apple.Music'
run = ['layout floating', 'move-window-to-workspace 5']

# Open new Finder windows floating in the centre ninth of the display.
[[rules]]
app-id = 'com.apple.finder'
run = 'grid 3:3:1:1:1:1'
```

## `[mode.<name>]`

Key bindings. dinky starts in `main`; `mode <name>` switches. Each key maps to
a command or a list of commands. Bound keys are swallowed.

### Keys

Modifiers (`alt`, `ctrl`, `cmd`, `shift`) and one key, joined by `-`:
`alt-shift-h`, `ctrl-left`, `f5`. Names follow a US layout.

- `a`–`z`, `0`–`9`, `f1`–`f20`
- `minus` `equal` `left-bracket` `right-bracket` `backslash` `semicolon`
  `quote` `comma` `period` `slash` `backtick` `section`
- `space` `enter` `esc` `backspace` `tab` `forward-delete` `left` `down` `up`
  `right` `page-up` `page-down` `home` `end`
- `keypad-0`–`keypad-9`, `keypad-clear` `keypad-decimal` `keypad-divide`
  `keypad-enter` `keypad-equal` `keypad-minus` `keypad-multiply` `keypad-plus`

The default `alt-` bindings take over Option-letter characters; set
`[modifiers] alt = 'left'` to keep right Option for typing them.

## Default config

```toml
#:schema https://dinky.rodeo/schemas/dinky.json
# ~/.config/dinky/dinky.toml. Saved changes take effect at once.
# A key you leave out keeps the value shown here.
# Every key and command: https://dinky.rodeo/configuration/

start-at-login = true
workspaces = 5                  # across all displays, one native Space each
default-layout = 'tiles'        # tiles (dwindle) | dwindle | accordion | fixed | scrolling
default-tiling = true           # false leaves workspaces untiled unless overridden
follow-app-activation = true    # Cmd-Tab and Dock clicks switch Spaces the fast way
float-windows-without-fullscreen = true   # progress windows, About, Calculator and the like float

# Example: only tile workspace 2 in a fixed 2x3 template.
# Empty cells stay empty; a seventh window adds a column by default.
# default-tiling = false
# [workspace.2]
# tiling = true
# layout = 'fixed'
# columns = 2
# rows = 3
# expand = 'columns'           # columns | rows | accordion (overflow in last cell)

[accordion]
padding = 30                    # points the neighbours peek out by
orientation = 'auto'            # auto: run along the container's longer side | keep

[scrolling]
column-width = 0.49             # a new column's share of the display; a lone column fills it

[floating]
move-step = 50                  # points `move` shifts a floating window by

[fullscreen]
focus-change = 'exit'           # focusing another window: exit | follow (it takes over) | keep (both fullscreen)
follow-delay-ms = 0             # with follow, wait this long for the other window to be back in its tile

[gaps]
inner = 8                       # or { horizontal = 8, vertical = 8 }
outer = 8                       # or { top = 8, bottom = 8, left = 8, right = 8 }

# Display patterns: main, secondary, or part of a name as `dinky list-displays` prints it.
# A workspace lives on the first display its patterns match, else on the main display.
# [workspace-to-display]
# 5 = 'secondary'

# Overrides for one display.
# [display.main]
# gaps.outer.top = 44

[borders]
enabled = true
width = 4
active-color = '#e1e3e4'        # '#rrggbb' or '#rrggbbaa'
inactive-color = '#494d64'
order = 'below'                 # below | above (a click-through ring over the window)
exclude-apps = []               # bundle IDs whose windows get no border

[focus-follows-mouse]
enabled = false
delay-ms = 100                  # how long the pointer rests on a window before it takes focus
accordion-edges = true          # resting on a peeking accordion edge focuses that window

[animations]
enabled = true                  # windows glide to their tiles; off while Reduce Motion is on
duration-ms = 150               # roughly how long a window takes to arrive
curve = 'spring'                # spring | linear | ease-out-cubic and the other easings.net curves

[drag]
placeholders = true             # outline where a dragged tile came from and show where it will go
modifier = 'none'               # alt, ctrl-alt…: held, drag a tile from anywhere in it
# preview-border-color = '#7aa2f7'  # where a drop will land; unset follows the system accent colour
# preview-fill-color = '#7aa2f74d'  # unset is the border colour at 30%
preview-border-width = 3        # points, for the preview and the outlines
home-outline = true             # outline where a dragged tile came from; false shows only where it will go

# Which key of each pair bindings answer to: both | left | right. With alt = 'left',
# right Option still types special characters.
[modifiers]
alt = 'both'
ctrl = 'both'
cmd = 'both'
shift = 'both'

# dinky commands run on events. exec-and-forget gets $DINKY_WORKSPACE, $DINKY_PREV_WORKSPACE and $DINKY_DISPLAY
# in the workspace hooks, and $DINKY_MODE, $DINKY_PREV_MODE in mode-changed.
# [hooks]
# startup = ['exec-and-forget brew services restart sketchybar']
# workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
# focus-changed = []
# mode-changed = []

# Every rule whose conditions all match a new window runs, in order.
[[rules]]
app-id = 'com.apple.systempreferences'   # also: app-name, title (regexes), kind (normal|dialog|sheet|panel)
run = 'layout floating'

[mode.main]
ctrl-left = 'workspace prev'
ctrl-right = 'workspace next'
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'
alt-shift-1 = 'move-window-to-workspace 1'
alt-shift-2 = 'move-window-to-workspace 2'
alt-shift-3 = 'move-window-to-workspace 3'
alt-shift-4 = 'move-window-to-workspace 4'
alt-shift-5 = 'move-window-to-workspace 5'
alt-shift-6 = 'move-window-to-workspace 6'
alt-shift-7 = 'move-window-to-workspace 7'
alt-shift-8 = 'move-window-to-workspace 8'
alt-shift-9 = 'move-window-to-workspace 9'
alt-tab = 'workspace-back-and-forth'
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'
alt-minus = 'resize smart -50'
alt-equal = 'resize smart +50'
alt-f = 'fullscreen'
alt-shift-f = 'layout floating tiling'
alt-comma = 'layout accordion'
alt-slash = 'layout tiles'
alt-shift-n = 'move-window-to-display next'
alt-shift-semicolon = 'mode service'

[mode.service]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
alt-shift-h = ['join-with left', 'mode main']
alt-shift-j = ['join-with down', 'mode main']
alt-shift-k = ['join-with up', 'mode main']
alt-shift-l = ['join-with right', 'mode main']
```
