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
| `default-layout` | `'tiles'` | `'tiles'` (the existing dwindle layout), `'dwindle'`, `'accordion'`, `'fixed'`, `'scrolling'`, or `'free'`, which tiles nothing (see [`[workspace.<number>]`](#workspacenumber)). |
| `default-tiling` | `true` | Set `false` to leave workspaces untiled unless overridden. |
| `follow-app-activation` | `true` | Cmd-Tab and Dock clicks switch Spaces the fast way. Needs the macOS "switch to a Space with open windows" setting off. |
| `float-windows-without-fullscreen` | `true` | Float windows that can't go full screen, such as Finder's copy progress, About This Mac and Calculator. Terminals and editors that can hide their title bar still tile. A `layout tiling` rule tiles a window anyway. |
| `menu-bar-icon` | `'blocks'` | `'blocks'` shows a block per display in the menu bar, left to right, with the workspace it shows: filled for the focused display, outlined for the others, corner marks for a full-screen Space. `'text'` shows the focused display's workspace number. `'none'` hides the menu bar item; the `dinky` CLI and key bindings still work. |
| `hide-menu-bar-icon` | `'never'` | When to hide dinky's menu bar item. `'single-display'` hides it while only one display is connected and shows it again once a second one is. `'always'` hides it, as `menu-bar-icon = 'none'` does. `'never'` leaves it to `menu-bar-icon`. Hidden, the `dinky` CLI and key bindings still work. |
| `scripting-addition` | `true` | Whether dinky may use its Dock scripting addition, which needs SIP off. Where it is injected (see [Scripting addition](scripting-addition.md)), a scrolling strip scrolls through it, its windows sliding past the screen edges; without it the strip moves its windows frame by frame. `false` never touches it, even with SIP off and the addition installed: dinky neither checks for it nor injects it, and the strip moves its windows frame by frame. Takes effect on reload. |
| `highlight-color` | unset | One highlight colour for everything that has one: `'#rrggbb'`, `'#rrggbbaa'`, or `'accent'` for the accent colour in System Settings. Each highlight a table leaves unset takes it: the pick in both switchers ([`[switcher]`](#switcher)), the focused window's border ([`[borders]`](#borders) `active-color`) and a drag's preview ([`[drag]`](#drag) `preview-border-color`). A table's own colour always wins, and its `'accent'` keeps the accent colour there. Unset, each keeps its own default. Like every top-level key, it goes above the first `[table]`. |

</div>

## `[workspace.<number>]`

Override the top-level `default-tiling` and `default-layout` for a globally
numbered workspace.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `tiling` | `default-tiling` | Whether the workspace tiles. |
| `layout` | `default-layout` | Its layout, with the same values. `'free'` lays nothing out: every window on the workspace floats where it stands, those opened there and those moved there, whatever `tiling` says, so `move`, `resize`, `fullscreen` and `cycle-size` work on them from the first press. One it floated tiles again on a workspace with another layout. There `layout` and `join-with` answer that the workspace is free instead of tiling a window, and `grid --toggle` puts a window back where it was before the grid placed it. `tiling = false` instead leaves the windows alone: dinky neither tiles nor floats them. |
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
is parked: the one nearest each edge hangs off it with a sliver of 25 points
left on, an inner gap from the columns in view, and the ones beyond it tuck
under that sliver with 2 points left on, so the edge shows a single window's
shadow rather than every parked window's piled up. Where another display sits beyond that edge, the column hides
behind the column in view nearest it instead, in the place of its biggest window, so none of it shows.

Commands work on columns. `focus left` and `right` move between columns, `up`
and `down` within one. `move left` and `right` swap the column with its
neighbour, or take a window that shares its column out into a new column.
`join-with left` and `right` put the window into the neighbouring column.
`resize width` (and `smart`) changes the column's width, `resize height` the
window's share of its column; `balance-sizes` resets them all. Hover focus
leaves columns that are not wholly in view alone; a click scrolls to them. A
click on a parked column's sliver goes to dinky rather than the app: the column
scrolls in and is focused once it rests there. A click that moves focus anywhere
else reaches the app as usual, and the strip scrolls once the button is up.

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
| `scrolling` | `'push'` | On a scrolling workspace, `'push'` widens the window's column across the screen and slides its neighbours off either side, where their edges show a gap from it, as a scrolled-away column's do; when fullscreen ends, the strip goes back to where it was. `'over'` covers the columns where they are, as on any other workspace. |

</div>

With a delay, focusing yet another window while one waits hands the wait on to
that window, and `fullscreen` during the wait ends it. When the fullscreen
window closes, the next one goes fullscreen at once, since nothing has to move
back.

With `'keep'`, every window focused while one is fullscreen joins it, the
focused one in front. `fullscreen` again, or any layout command, ends
fullscreen for all of them. Floating windows and other workspaces are not
affected. On a scrolling workspace that pushes, each of them is a column as
wide as the screen, so focusing one scrolls a whole screen to it.

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
| `move-step` | `50` | Points `move` shifts a floating window by, from `1` to `1000`, when the binding gives no number, as `move left 10` does. |
| `resize-anchor` | `'center'` | What stays put when `resize` sizes a floating window: `'center'`, so a centred window stays centred, or `'top-left'`, so it grows to the right and down and shrinks from there. Either way it stays on the display, so one against the right edge grows to the left. |

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
| `active-color` | [`highlight-color`](#top-level), else `'#e1e3e4'` | The focused window's border: `'#rrggbb'`, `'#rrggbbaa'` or `'accent'`. |
| `inactive-color` | `'#494d64'` | |
| `order` | `'below'` | `'above'` draws a click-through ring over the window. |
| `exclude-apps` | `[]` | Bundle IDs that get no border. |
| `noop-flash` | `true` | Flash the focused window's border when a key binding or gesture does nothing: a move at the edge, a resize at its limit, `focus` or `focus-monitor` with nothing that way, `workspace next` on the last workspace, `workspace N` on the one already shown, moving a window to where it already is, `fullscreen` on a window that already fills its workspace. Drawn even with `enabled = false`. |
| `noop-flash-color` | `'#ed8796'` | The flash: `'#rrggbb'`, `'#rrggbbaa'` or `'accent'`. |
| `noop-flash-count` | `2` | How many times it flashes, from `1` to `5`. |
| `noop-flash-ms` | `120` | How long each flash is on, from `50` to `1000`, with 80 ms off between them. |

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
with the window in the half on that side. A swap is filled more strongly, with
the same border, and the dragged window's own tile lights up too, where the
other window will go. In the
scrolling layout, dropping left
or right of a tile makes the window a column of its own there. A fixed layout's
grid only swaps. Dropped anywhere else, the window goes back.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `placeholders` | `true` | While you drag a tiled window, outline the tile it came from, and show over the tile under the pointer the part the window will take. |
| `preview-border-color` | [`highlight-color`](#top-level), else the accent colour | The border of the part of the tile the window will take: `'#rrggbb'`, `'#rrggbbaa'`, or `'accent'` for the accent colour in System Settings. The faint outline of the whole tile around a half is this colour at 40%. |
| `preview-fill-color` | border at 30% | The fill of that part, `'#rrggbbaa'` for a translucent one such as `'#7aa2f74d'`. |
| `preview-border-width` | `3` | Points, from `0` to `20`, for every border while you drag: the preview, a swap's, and the outlines of the tiles. |
| `home-outline` | `true` | Outline the tile the window came from in grey while you drag. `false` shows only the feedback over the tile under the pointer. |
| `mouse-modifier` | `'none'` | Hold it to drag a window from anywhere in it, not only by its title bar: `'alt'`, `'ctrl'`, `'cmd'` or `'shift'`, or several joined by `-` such as `'ctrl-cmd'`, held exactly. A tiled window drops as above; a floating one just moves. Once it is set, only a drag with it held drops onto a tile and shows where it will go: a tiled window dragged by its title bar alone goes back to its tile, and dragging its edges still resizes it. The press goes to dinky, not the app, so pick modifiers your apps don't click with: `cmd` opens links, `ctrl` is a right click. Each key's side follows [`[modifiers]`](#modifiers), and it can't be a switcher's `modifier`. `'none'` turns it off. |

</div>

## `[hud]`

After the `layout` command, or when the binding mode changes, a glass capsule
shows the new layout, such as `h_accordion` or `scrolling`, or the new mode's
name, for a moment on the focused display, then fades out. When a display moves
to another workspace, it shows there the workspace's number and layout, such as
`2 · v_accordion`: the layout of its focused tile, `scrolling`, `free` for a
workspace dinky does not tile, or the configured layout of an empty one. Another change while
it shows replaces the text and restarts the count. On macOS 26 and later it is
Liquid Glass; earlier, the HUD material.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `true` | Show the capsule. |
| `position` | `'bottom'` | `'bottom'` above the Dock, or near the bottom of the screen when the Dock hides or sits at a side; `'top'` below the menu bar. |
| `duration-ms` | `1200` | How long it stays before fading out, from `100` to `10000`. |
| `offset` | `16` | Points, from `0` to `200`, between the capsule and the Dock or menu bar. |
| `on-layout-change` | `true` | Show it after the `layout` command. |
| `on-mode-change` | `true` | Show it when the binding mode changes. |
| `on-workspace-change` | `true` | Show the workspace's layout when a display moves to another workspace. |
| `on-noop` | `false` | Show why when a key binding or gesture does nothing, such as `move left: nothing to do`. |

</div>

## `[switcher]`

What the [window switcher](#window-switcher) and the
[workspace switcher](#workspace-switcher) share. Each key here can also go in
`[window-switcher]` or `[workspace-switcher]`, where it is for that switcher
alone and wins over this one, wherever the tables are in the file.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `true` | `false` turns the switcher off: its modifier, its binding and its swipe show nothing. |
| `delay-ms` | `200` | How long the modifier is held alone before the capsule shows, `0` to `2000`. |
| `trigger` | `'hold'` | How the modifier shows the capsule: `'hold'` held on its own for `delay-ms`, releasing it takes the pick; `'double-tap'` tapped on its own twice, and the capsule stays up at the pointer for the arrows, Tab, a digit or the pointer to pick, Return, Space or a click to take the pick and Esc to close it, as from a key binding. |
| `double-tap-ms` | `300` | With `'double-tap'`, how long each tap and the gap between them may last, `100` to `1000`. |
| `corner-radius` | `52` | The capsule's corner radius in points, `0` to `80`, at most half its height. The padding around the thumbnails is the same on every side, `14` points, growing with the radius past `47` so no thumbnail is clipped. The window switcher's row and map are both about `128` points tall, so it takes about `70` for round ends. |
| `position` | `'auto'` | Where the capsule shows on the display under the pointer: `'auto'` over the pointer when the modifier is held or a swipe shows it, in the middle from a key binding; `'center'` in the middle; `'top'` below the menu bar; `'bottom'` above the Dock; `'mouse'` over the pointer, from a key binding too. Wherever it shows, the pointer picks what is under it, or on a row whatever is above or below it. |
| `show-titles` | `true` | Whether windows show their titles. In the window switcher each title sits under its card; on a map, and over a column's upper window, on a dark band along the card's foot. In the workspace switcher each window in a card has its title on a band along its foot, unless it is covered or too small to read, or `thumbnails = 'schematic'`. A window without a title shows its app's name. Titles come from the window server with Screen Recording granted, else from the app. |
| `letter-keys` | `true` | Whether each window gets a letter, drawn as a key at its title's right (alone where its title would be with `show-titles = false`). Pressing that letter while the capsule is up jumps to the window at once: the window switcher focuses it; the workspace switcher switches to its workspace and focuses it there. The letter works held, double-tapped or from a binding, whatever modifiers are down, and is not passed on to the app. In the workspace switcher only windows in front and big enough for a key get one, and schematic cards none. |
| `letters` | `'asdfgqwertyuiopzxcvbnm'` | The letters handed out, in order, to the windows as they read: left to right, a column top to bottom; in the workspace switcher card by card. Lowercase `a` to `z`, each once, without `h`, `j`, `k` and `l`, which move the pick. Windows past the last letter get none. Letters go by their place on a US keyboard, as key bindings do. |
| `highlight-color` | [`highlight-color`](#top-level), else `'accent'` | The ring around the pick and a faint glow of it under the pick, `'#rrggbb'`, `'#rrggbbaa'` or `'accent'`. On the workspace switcher with `thumbnails = 'schematic'`, the picked card's windows too. |

</div>

```toml
[switcher]
delay-ms = 50
corner-radius = 18
position = 'center'

[window-switcher]
modifier = 'alt'
position = 'auto'   # this one over the pointer when held

[workspace-switcher]
modifier = 'ctrl'
enabled = false     # off for now, its settings kept
```

## `[window-switcher]`

Hold `modifier` on its own over a workspace laid out by one of `layouts`, with
a tiled window or more (on a free workspace, any window; two or more with
`show-single = false`), and after `delay-ms` a glass capsule of the
workspace's windows appears at the pointer, with the focused one under it (on
a free workspace without it, the frontmost one there).

- On a scrolling or accordion workspace it is a row over the pointer: strip
  order, a column's windows together, or tree order, the windows of each part
  of the root together. Windows stacked in a column, or split in a part, show
  as their tiles sit on screen, one over the other; an accordion's windows sit
  side by side. Move the pointer across to pick a window, and up or down
  between stacked ones.
- On a tiles or fixed workspace it is a map of the workspace over the pointer,
  each window's tile scaled down where it is, the focused one under the
  pointer. Move the pointer onto a tile to pick it; off the map the nearest
  tile is picked. `tiles-style = 'row'` shows these as a row too.
- On a free workspace (`layout = 'free'` or `tiling = false`) it is a row of
  the windows on it, left to right by where they stand, with `'free'` in
  `layouts`. Floating windows on a tiled workspace are not in its capsule.

Release the modifier to focus the window picked, which on a scrolling
workspace scrolls the strip to it. While the capsule is up the keys drive it
too, and none of them reaches the app underneath: h, j, k, l (or the arrows)
move the pick left, down, up and right, onto the nearest tile that way on a
map and, along a row, h and k to the one before, j and l to the one after;
Tab and Shift-Tab step through; Return or Space focuses the window picked at
once; a window's letter, drawn as a key beside its title (`letter-keys`),
focuses that window at once. Esc closes the capsule without focusing anything,
and so does any other key pressed with the modifier, which goes on to the
binding it is for. One capsule serves every workspace.

A key binding to the `window-switcher` command shows the capsule from the
keyboard instead, in the middle of the display under the pointer: the arrows
or h, j, k, l move the pick (onto the nearest tile that way on a map), Tab and
Shift-Tab step through, Return or Space focuses the window picked, a window's
letter focuses it at once and Esc closes it. The binding again steps to the next window, and letting go of its
modifiers focuses the window picked, as Cmd-Tab does. The mouse works too:
move the pointer over a window in the capsule to pick it and click to focus
it. It works with `modifier = 'none'` too.

```toml
[mode.main]
alt-tab = 'window-switcher'
```

Thumbnails need Screen Recording (System Settings, Privacy & Security), asked
for the first time the capsule shows; dinky may need a restart after it is
granted. Without it each window shows as its app's icon. Thumbnails are kept
per window, so the capsule draws at once and fresh ones fade in.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `modifier` | `'none'` | `'alt'`, `'ctrl'`, `'cmd'`, `'shift'` or `'hyper'`, [`[modifiers]`](#modifiers)' `hyper` held together. `'none'` turns holding it off; a binding still shows the capsule. Which key of the pair counts follows [`[modifiers]`](#modifiers). |
| `layouts` | `['scrolling', 'tiles']` | The layouts it shows for: `'scrolling'`, `'tiles'` (dwindle), `'accordion'`, `'fixed'` and `'free'`, a workspace dinky does not tile. |
| `tiles-style` | `'map'` | How a tiles or fixed workspace shows: `'map'`, its tiles as they are, or `'row'`, a row like a scrolling workspace's. |
| `show-single` | `true` | Whether the capsule shows for a workspace with a lone tiled window (on a free workspace, a lone window), held or from a binding. `false` shows it only with two or more. |
| `enabled`, `delay-ms`, `trigger`, `double-tap-ms`, `corner-radius`, `position`, `show-titles`, `letter-keys`, `letters`, `highlight-color` | [`[switcher]`](#switcher)'s | As in `[switcher]`, for this switcher alone. |

</div>

```toml
[window-switcher]
modifier = 'alt'
layouts = ['scrolling']   # only on scrolling workspaces
corner-radius = 20

[modifiers]
alt = 'left'    # only left Option shows it; right Option types as usual
```

## `[workspace-switcher]`

Hold `modifier` on its own and after `delay-ms` a glass capsule of the
workspaces appears at the pointer, the display's current workspace under it.
Each card is its display drawn small, with the windows where the workspace's
layout puts them, and under it the workspace's number and layout as the
[HUD](#hud) names it, such as `2 · scrolling`:

- tiles and fixed workspaces show their tiles; a fixed workspace's empty cells
  are dashed.
- An accordion shows the focused window in front and its neighbours peeking
  out behind it, a little further than they do on screen so they show.
- A scrolling workspace shows the columns in view, drawn in from the sides,
  with a sliver and a count for the columns parked off screen on each side.
- A window fullscreen with `fullscreen` shows alone, floating windows over the
  rest, and a workspace with no windows as a dashed outline.

Move the pointer across to pick a workspace and release the modifier to
switch to it, as `workspace` does: on another display, that display shows it
and takes focus. While it is up, h, j, k, l, the arrows and Tab move the pick
and Return or Space switches at once, as from a key binding below. A window's
letter, drawn as a key on it (`letter-keys`), switches to its workspace and
focuses it. Esc, or any other key pressed with the modifier, closes the capsule
without switching.

A key binding to the `workspace-switcher` command shows the capsule in the
middle of the display under the pointer instead: the arrows or h, j, k, l and
Tab and Shift-Tab move the pick, Return or Space switches to it and Esc closes
it; the binding again steps to the next workspace, and letting go of its
modifiers switches to the one picked. A digit switches to the workspace with
that number at once, 0 for 10, and a window's letter to its workspace,
focusing it. The mouse works too: move the pointer over a
card to pick it and click to switch to it.

Every card has its own display's proportions. With more than one display and
`displays = 'all'`, each display's workspaces are a group, left to right as the
displays are arranged, with the display's name over it; a dot marks the
workspace each display shows. A display with no numbered workspace shows the
Space it is on, and picking it focuses that display.

Thumbnails are the [window-switcher](#window-switcher)'s and need Screen Recording too.
macOS draws no Space but the ones on screen, so a workspace's windows are
captured as they lose focus and as dinky switches away from it, and the ones
on screen as the capsule shows; a window not captured yet shows its app's icon.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `modifier` | `'none'` | `'alt'`, `'ctrl'`, `'cmd'`, `'shift'` or `'hyper'`; not the same as `[window-switcher]`'s unless their `trigger`s differ, so one key can be held for one switcher and double-tapped for the other (keep the held one's `delay-ms` at least its `double-tap-ms`, or a slow tap shows it). `'none'` turns holding it off; a binding still shows the capsule. Which key of the pair counts follows [`[modifiers]`](#modifiers). |
| `displays` | `'all'` | `'all'`: every display's workspaces, a group per display. `'pointer'`: only those of the display under the pointer. |
| `show-empty` | `true` | Cards for workspaces without windows. |
| `exclude` | `[]` | Workspace numbers left out, such as `[3]`. |
| `card-height` | `85` | Each card's height in points, `60` to `200`; its width follows its display. A row too wide for the display is scaled down. |
| `thumbnails` | `'windows'` | `'windows'` shows a picture of each window; `'icons'` only app icons; `'schematic'` a fixed picture of each workspace's layout, the same whatever windows it has: tiles one window beside two, accordion three stacked, scrolling two columns between parked slivers, fixed its template's cells, free three overlapping windows. Its windows are solid grey blocks with a hairline edge, as Windows draws its snap layouts, all in the accent colour on the card picked. Neither of the last two needs Screen Recording. |
| `enabled`, `delay-ms`, `trigger`, `double-tap-ms`, `corner-radius`, `position`, `show-titles`, `letter-keys`, `letters`, `highlight-color` | [`[switcher]`](#switcher)'s | As in `[switcher]`, for this switcher alone. |

</div>

```toml
[workspace-switcher]
modifier = 'ctrl'
exclude = [3]
```

## `[gestures]`

Swipes run commands, as key bindings do: on the trackpad in
`[gestures.trackpad]`, on a Magic Mouse in `[gestures.mouse]`. Gestures read
both through macOS's private MultitouchSupport framework.

```toml
[gestures.trackpad]
swipe-right = 'window-switcher'
swipe-left = 'workspace-switcher'
```

### `[gestures.trackpad]`

Swipe on the trackpad with `fingers` fingers and the swipe's commands run, as
a key binding's do; the trackpad ticks. A swipe is fingers that land together
moving `distance` millimetres, mostly one way, soon after they land. Fingers
that gather slowly, as when a third joins two that scroll or a thumb comes to
rest, are no swipe until they all lift.

A swipe that shows the [window-switcher](#window-switcher) or the
[workspace-switcher](#workspace-switcher) goes on with the same fingers, as
holding the modifier does: keep them down and move them across, a step of the
pick every `step` millimetres, each one felt; on a map, up and down too. One or
two of them, or one more, drive it as well, so a finger lifting or landing on
the way changes nothing. Lift them all, or press the trackpad, to take the
pick. Lifted before the pick moves, as at the end of a quick swipe, the
capsule stays up: move the pointer to pick and click to take it, or put the
fingers down again and slide them. Esc closes the capsule.

Two fingers also scroll, so three is the default. macOS swipes three fingers
across to switch Spaces and up for Mission Control unless that is off or set
to four fingers in System Settings, Trackpad, More Gestures; `dinky doctor`
says when a bound swipe clashes. The built-in trackpad and Magic Trackpads
work alike.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `true` | `false` turns swipes on the trackpad off, keeping the settings. |
| `fingers` | `3` | How many fingers swipe, `2` to `5`. |
| `distance` | `15` | Millimetres the fingers move before it is a swipe, `6` to `40`. |
| `step` | `12` | Millimetres the fingers move for each step of a switcher's pick, `4` to `50`. |
| `swipe-left`, `swipe-right`, `swipe-up`, `swipe-down` | | The command or commands the swipe runs. |

</div>

### `[gestures.mouse]`

Off by default: `enabled = true` turns on the same swipes on a Magic Mouse,
with lengths for its narrow surface, about 52 mm across and 90 front to back.
Two fingers swipe there by default: held as a mouse is, it seldom feels a
third, which lies along its edge. Fingers resting on the mouse as it is held
count: the swipe starts as the last of them lands. One finger scrolls and
macOS swipes two across the mouse between full-screen apps unless that is off
in System Settings, Mouse; `dinky doctor` says when a bound swipe clashes.
Swiping with more, two fingers move nothing while they drive a switcher.

A stroke across the mouse goes only so far, so fingers lifted off it may land
again within a moment and go on picking; lift them for longer, or click, to
take the pick, and right-click to close the capsule, as Esc does. While they
drive it, moving the mouse moves no pick. The mouse has nothing to tick. Its
own swipes replace all of `[gestures.trackpad]`'s; without any, those run on
the mouse too.

<div class="wide-table" markdown="1">

| Key | Default | |
|---|---|---|
| `enabled` | `false` | `true` turns swipes on the mouse on. |
| `fingers` | `2` | How many fingers swipe, `2` to `4`. |
| `distance` | `8` | Millimetres the fingers move before it is a swipe, `3` to `30`. |
| `step` | `4` | Millimetres the fingers move for each step of a switcher's pick, `2` to `30`. |
| `swipe-left`, `swipe-right`, `swipe-up`, `swipe-down` | | The command or commands the swipe runs on the mouse. |

</div>

```toml
[gestures.mouse]
enabled = true
swipe-up = 'window-switcher'
swipe-down = 'workspace-switcher'
```

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
| `hyper` | `'alt-ctrl-cmd-shift'` | Two or more modifiers joined by `-`, in any order: what a switcher's `modifier = 'hyper'` holds. They count from either side, whatever the keys above say; held together and nothing else, they show the capsule, and letting go of any one lets go of hyper. Not for key bindings. |

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
`layout tiling` rule tiles them. On a `free` workspace every window floats,
whatever its rules say.

Windows already open when dinky starts are not new: `layout floating`,
`layout tiling` and `grid` still float or tile them, but no other command runs,
so restarting dinky moves, resizes and follows nothing.

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
| `disk-image` | `true` for a window that comes from a mounted disk image: the Finder window opening a .dmg shows, or any other Finder window on it, and the windows of an app run from one, such as an installer a .dmg carries. `false` for every other window. External drives are not disk images. |
| `workspace-layout` | The layout of the window's workspace, or a list of them: `'scrolling'`, `'tiles'` (or `'dwindle'`), `'accordion'`, `'fixed'`, or `'free'` for a workspace that does not tile (`layout = 'free'` or `tiling = false`; `'floating'` is its old name). Its layout now, as a `layout` command may have switched it. |
| `workspace` | The number of the window's workspace, or a list of them. |
| `run` | Required. A command or a list. |

</div>

`workspace-layout` and `workspace` are about the workspace the window is on as
the rule's commands run, so a rule after one that moves the window looks at
where it went. A rule that is exactly `layout floating` or `layout tiling`
looks at the workspace the window first shows on. A rule whose workspace does
not match is skipped; the others still run.

```toml
[[rules]]
app-id = 'com.apple.Music'
run = ['layout floating', 'move-window-to-workspace 5']

# Float what a .dmg opens: its Finder window and an installer run from it.
[[rules]]
disk-image = true
run = 'layout floating'

# Open new Finder windows floating in the centre ninth of the display.
[[rules]]
app-id = 'com.apple.finder'
run = 'grid 3:3:1:1:1:1'

# Ghostty's new windows: a 70% column on a scrolling workspace, 60% of the row on a tiled one.
[[rules]]
app-id = 'com.mitchellh.ghostty'
workspace-layout = 'scrolling'
run = 'cycle-size 70%'

[[rules]]
app-id = 'com.mitchellh.ghostty'
workspace-layout = ['tiles', 'fixed']
run = 'cycle-size 60%'
```

## `[mode.<name>]`

Key bindings. dinky starts in `main`; `mode <name>` switches. Each key maps to
a command or a list of commands. Bound keys are swallowed.

### By layout

A table in a mode named for a layout, `scrolling`, `tiles` (or `dwindle`),
`accordion`, `fixed` or `free`, binds keys for a workspace laid out that way:
while the focused workspace has that layout, a key in it takes over from the
same key of the mode, and every other key of the mode stays. Its layout is the
workspace's: `layout scrolling` switches it, and a container layout (`layout
tiles`, `layout accordion` and the like) takes it back to the configured one.
`free` is also a workspace with `tiling = false`; a native full-screen Space
uses the mode's own keys. Write only the keys that should differ. The menu
shows the keys in force on the focused workspace.

```toml
[mode.main]
alt-shift-h = 'move left'
alt-shift-l = 'move right'

[mode.main.free]                # on a free workspace, halves instead of steps
alt-shift-h = 'grid 1:2:0:0:1:1'
alt-shift-l = 'grid 1:2:1:0:1:1'
```

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
default-layout = 'tiles'        # tiles (dwindle) | dwindle | accordion | fixed | scrolling | free (every window floats)
default-tiling = true           # false leaves workspaces untiled unless overridden
follow-app-activation = true    # Cmd-Tab and Dock clicks switch Spaces the fast way
float-windows-without-fullscreen = true   # progress windows, About, Calculator and the like float
menu-bar-icon = 'blocks'        # blocks (one per display, focused filled) | text (the focused display's number) | none (hidden)
hide-menu-bar-icon = 'never'    # never | always (as menu-bar-icon = 'none') | single-display (hidden while only one display is connected)
scripting-addition = true       # scroll strips through the Dock scripting addition where it is injected (SIP off);
                                # without it, or false, their windows move frame by frame
# highlight-color = '#7aa2f7'  # what every highlight left unset takes: the switchers' pick, the focused border, a drag's preview

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
move-step = 50                  # points `move` shifts a floating window by, unless the binding gives a number
resize-anchor = 'center'        # what stays put when `resize` sizes a floating window: center | top-left

[fullscreen]
focus-change = 'exit'           # focusing another window: exit | follow (it takes over) | keep (both fullscreen)
follow-delay-ms = 0             # with follow, wait this long for the other window to be back in its tile
scrolling = 'push'              # on a scrolling workspace: push (neighbours slide off) | over (cover them)

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
# active-color = '#e1e3e4'      # '#rrggbb', '#rrggbbaa' or 'accent'; unset is highlight-color, else '#e1e3e4'
inactive-color = '#494d64'
order = 'below'                 # below | above (a click-through ring over the window)
exclude-apps = []               # bundle IDs whose windows get no border
noop-flash = true               # a binding that does nothing flashes the focused window's border
noop-flash-color = '#ed8796'    # '#rrggbb', '#rrggbbaa' or 'accent'
noop-flash-count = 2            # flashes, 1 to 5
noop-flash-ms = 120             # how long each flash is on, 50 to 1000

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
# preview-border-color = '#7aa2f7'  # where a drop will land; unset follows the system accent colour
# preview-fill-color = '#7aa2f74d'  # unset is the border colour at 30%
preview-border-width = 3        # points, for the preview and the outlines
home-outline = true             # outline where a dragged tile came from; false shows only where it will go
mouse-modifier = 'none'         # held, drag a window from anywhere in it; set, only such drags drop on tiles: none (off) | alt | ctrl | cmd | shift, or joined, 'ctrl-cmd'

# A glass capsule naming the new layout or mode for a moment.
[hud]
enabled = true
position = 'bottom'             # bottom (above the Dock) | top (below the menu bar)
duration-ms = 1200              # how long it stays, 100 to 10000
offset = 16                     # points from the Dock or menu bar
on-layout-change = true         # after the layout command
on-mode-change = true           # when the binding mode changes
on-workspace-change = true      # the new workspace's layout when a display moves to another workspace
on-noop = false                 # why, when a binding does nothing

# What both switchers below share. Each of these keys can go in [window-switcher] or [workspace-switcher] too,
# for that one alone.
[switcher]
enabled = true                  # false turns both off: the modifier, the bindings and the swipes
delay-ms = 200                  # how long the modifier is held alone before the capsule shows, 0 to 2000
trigger = 'hold'                # hold (the modifier held alone) | double-tap (tapped alone twice; keys, pointer or a click pick)
double-tap-ms = 300             # with double-tap, how long each tap and the gap between them may last, 100 to 1000
corner-radius = 52              # points, 0 to 80; about 70 or more makes a row's ends round
position = 'auto'               # auto (at the pointer when held, the middle from a binding) | center | top | bottom | mouse
show-titles = true              # window titles: under each card in the window switcher, along each window's foot in a workspace card
letter-keys = true              # a letter key beside each title; press the letter to jump to that window
letters = 'asdfgqwertyuiopzxcvbnm'  # handed out left to right; a to z, each once, not h, j, k, l
# highlight-color = 'accent'    # the pick's ring and glow; unset is highlight-color, else the accent colour

# Hold the modifier alone for a glass capsule of the workspace's windows at the pointer; move across to pick
# one, release to focus it.
[window-switcher]
modifier = 'none'               # none (off) | alt | ctrl | cmd | shift | hyper
layouts = ['scrolling', 'tiles']  # where it shows: scrolling | tiles | accordion | fixed | free
tiles-style = 'map'             # tiles and fixed: map (their tiles, picked in two dimensions) | row
show-single = true              # also show it for a workspace with a lone tiled window (free: a lone window)

# Which key of each pair bindings answer to: both | left | right. With alt = 'left',
# right Option still types special characters.
[modifiers]
alt = 'both'
ctrl = 'both'
cmd = 'both'
shift = 'both'
hyper = 'alt-ctrl-cmd-shift'     # what a switcher's modifier = 'hyper' holds together, two or more, either side

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
