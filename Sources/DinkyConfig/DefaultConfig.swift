// The config dinky writes on first run. Apart from the rules and bindings, which it spells out, its
// values are the built-in defaults, so a key left out of a user's file means what this file says.

extension Config {
    public static let defaultTOML = """
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
    # highlight-color = '#7aa2f7'  # what every highlight left unset takes: the switchers' pick, the focused border, the noop glow, a drag's preview
    haptic = true                   # the trackpad taps for dinky; what every haptic left unset takes
    haptic-strength = 'medium'      # light | medium | strong; what every haptic-strength left unset takes

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
    center-focused-column = 'never' # focusing a column scrolls it: never (just into view) | always (to the middle) | always-fill | on-overflow

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
    noop-flash = true               # a binding that does nothing makes the focused window's edge glow once
    # noop-flash-color = '#d97757'  # '#rrggbb', '#rrggbbaa' or 'accent'; unset is highlight-color, else '#d97757'
    noop-flash-width = 2            # the ring around the window, 0 to 8 points
    noop-flash-spread = 100         # points the glow fades over inside the window, 8 to 160
    noop-flash-opacity = 0.6        # its opacity at the window's edge, 0 to 1
    pinned = true                   # a pinned column's windows get a ring, even with enabled = false
    # pinned-color = '#d97757'      # '#rrggbb', '#rrggbbaa' or 'accent'; unset is highlight-color, else '#d97757'
    pinned-width = 2                # the pinned windows' ring, 0 to 8 points

    [focus-follows-mouse]
    enabled = false
    delay-ms = 100                  # how long the pointer rests on a window before it takes focus
    accordion-edges = true          # resting on a peeking accordion edge focuses that window

    [animations]
    enabled = true                  # windows glide to their tiles; off while Reduce Motion is on
    duration-ms = 363               # roughly how long a window takes to arrive; 363 with damping 1 is SlideScroll's spring
    damping = 1                     # how the spring settles: 1 eases in without overshooting, lower overshoots; 0.5 to 1
    curve = 'spring'                # spring | linear | ease-out-cubic and the other easings.net curves

    [drag]
    placeholders = true             # windows make room for a dragged tile and a preview shows where it will go
    # preview-border-color = '#7aa2f7'  # where a drop will land; unset follows the system accent colour
    # preview-fill-color = '#7aa2f74d'  # unset is the border colour at 30%
    preview-border-width = 3        # points, for the preview and the outlines
    home-outline = true             # outline where a dragged tile goes back to while it would
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
    # haptic = true                # the trackpad taps as the pick moves; unset is the top-level haptic
    # haptic-strength = 'medium'   # unset is the top-level haptic-strength

    # Hold the modifier alone for a glass capsule of the workspace's windows at the pointer; move across to pick
    # one, release to focus it.
    [window-switcher]
    modifier = 'none'               # none (off) | alt | ctrl | cmd | shift | hyper
    layouts = ['scrolling', 'tiles']  # where it shows: scrolling | tiles | accordion | fixed | free
    tiles-style = 'map'             # tiles and fixed: map (their tiles, picked in two dimensions) | row
    show-single = true              # also show it for a workspace with a lone tiled window (free: a lone window)

    # Hold the modifier alone for a glass capsule of the workspaces at the pointer, each drawn small in its layout;
    # move across to pick one, release to switch to it.
    [workspace-switcher]
    modifier = 'none'               # none (off) | alt | ctrl | cmd | shift | hyper; not [window-switcher]'s unless the triggers differ
    displays = 'all'                # all (a group per display) | pointer (the display under the pointer)
    show-empty = true               # cards for workspaces without windows
    show-fullscreen = true          # a card for each native full-screen Space, after its display's workspaces
    exclude = []                    # workspace numbers left out
    card-height = 85                # points, 60 to 200; the width follows each display's proportions
    thumbnails = 'windows'          # windows (pictures, need Screen Recording) | icons (app icons) | schematic (a fixed picture of the layout)
    # delay-ms = 300                # any [switcher] key set here is for this switcher alone

    # Swipes on the trackpad and a Magic Mouse, each running commands as a key binding does. A swipe that shows a
    # switcher goes on picking with the same fingers, a step every `step` millimetres; lift them to take the pick.
    # [gestures.trackpad]
    # enabled = true
    # fingers = 3                   # 2 to 5
    # distance = 15                 # millimetres before it is a swipe, 6 to 40
    # step = 12                     # millimetres per step, 4 to 50
    # haptic = true                 # the trackpad taps as a swipe runs; unset is the top-level haptic
    # haptic-strength = 'medium'    # unset is the top-level haptic-strength
    # swipe-right = 'window-switcher'   # also swipe-left, swipe-up, swipe-down
    # swipe-left = 'workspace-switcher'
    # [gestures.mouse]              # the same on a Magic Mouse, off by default
    # enabled = true
    # fingers = 2                   # 2 to 4; it seldom feels a third
    # distance = 8                  # millimetres, 3 to 30
    # step = 4                      # millimetres per step, 2 to 30
    # swipe-up = 'window-switcher'  # its own swipes replace the trackpad's; none, and those run
    # [gestures.scroll]             # fingers moved across the trackpad scroll a strip with them, off by default
    # enabled = true
    # fingers = 4                   # 3 to 5; not [gestures.trackpad]'s while it binds swipe-left or swipe-right
    # speed = 1.5                   # screens the strip moves as the fingers cross the trackpad, 0.25 to 5
    # show-switcher = true          # the window switcher shows the strip once it rests
    # switcher-ms = 1000            # for this long, 100 to 5000
    # edge-flash = true             # pushed on past an end, the display's side there glows
    # haptic = true                 # the trackpad ticks as each column comes to the middle; unset is the top-level haptic
    # haptic-strength = 'medium'     # unset is the top-level haptic-strength
    # [gestures.mouse-scroll]       # the mouse scrolls a strip with a modifier held, off by default
    # enabled = true
    # modifier = 'ctrl-alt'         # held exactly; not [drag] mouse-modifier or a held switcher's modifier (a double-tapped one's can be)
    # drag = true                   # press over a window and drag across
    # wheel = true                  # a stroke with scroll phases (Magic Mouse, trackpad) scrolls; other wheels step a column a notch
    # cursor = true                 # a hand over what a press would drag, closed while it does; nothing without drag
    # speed = 1                     # how far the strip goes for each point, 0.25 to 5; 1 follows the pointer
    # show-switcher = true          # unset is [gestures.scroll]'s
    # switcher-ms = 1000            # unset is [gestures.scroll]'s
    # edge-flash = true             # unset is [gestures.scroll]'s

    # Which key of each pair bindings answer to: both | left | right. With alt = 'left',
    # right Option still types special characters.
    [modifiers]
    alt = 'both'
    ctrl = 'both'
    cmd = 'both'
    shift = 'both'
    hyper = 'alt-ctrl-cmd-shift'     # what a switcher's modifier = 'hyper' holds together, two or more, either side

    # dinky commands run on events. exec-and-forget gets $DINKY_WORKSPACE, $DINKY_PREV_WORKSPACE and $DINKY_DISPLAY
    # in the workspace hooks, $DINKY_MODE, $DINKY_PREV_MODE in mode-changed, and $DINKY_DISPLAYS,
    # $DINKY_PREV_DISPLAYS (how many displays) in display-changed.
    # [hooks]
    # startup = ['exec-and-forget brew services restart sketchybar']
    # workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
    # focus-changed = []
    # mode-changed = []
    # display-changed = []

    # Every rule whose conditions all match a new window runs, in order.
    [[rules]]
    app-id = 'com.apple.systempreferences'   # also: app-name, title (regexes), kind (normal|dialog|sheet|panel), disk-image
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
    """
}
