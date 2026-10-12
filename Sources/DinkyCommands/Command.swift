import DinkyLayout

// The one command vocabulary shared by key bindings, the CLI and the menu bar.
// Names and arguments follow AeroSpace (MIT, github.com/nikitabobko/AeroSpace) where dinky has the feature.

public enum Command: Equatable, Sendable {
    case workspace(WorkspaceTarget)
    case workspaceBackAndForth
    case moveWindowToWorkspace(WorkspaceTarget, follow: Bool)
    case moveWindowToDisplay(DisplayTarget, follow: Bool)
    /// Focus the neighbour in a direction. `boundaries` says where the search stops, `action` what happens there.
    case focus(Direction, boundaries: FocusBoundaries = .workspace, action: BoundariesAction = .stop)
    case focusMonitor(MonitorTarget)
    /// `focus-monitor N`: the display numbered N by `list-monitors`, from 1.
    case focusMonitorNumber(Int)
    case move(Direction)
    case joinWith(Direction)
    case resize(ResizeDimension, by: Int)
    /// One layout, or several to cycle through: the first that does not describe the current state wins,
    /// so `layout floating tiling` and `layout horizontal vertical` toggle between the two.
    case layout([LayoutName])
    case fullscreen
    /// Float the window and give it cells of a grid over its display, as yabai's `--grid`. With `toggle`, a
    /// floating window is tiled instead.
    case grid(GridPlacement, toggle: Bool = false)
    case flattenWorkspaceTree
    case balanceSizes
    case retile
    case clearMinimumSizes
    case mode(String)
    case reloadConfig
    case enable(Toggle)
    case listWindows(WindowQuery)
    case listWorkspaces(WorkspaceQuery)
    case listMonitors(MonitorQuery)
    /// Every mode in the config, main first, or with `current` only the mode dinky is in.
    case listModes(current: Bool)
    /// The coordinator's state as JSON: displays, trees with their expected frames, placements and windows.
    case debugState
    /// Shell text run with `/bin/sh -c`, not waited for.
    case execAndForget(String)
}

/// A 1-based workspace number on the focused display, or its neighbour.
public enum WorkspaceTarget: Equatable, Sendable {
    case number(Int)
    case prev, next
}

public enum DisplayTarget: String, Equatable, Sendable {
    case prev, next
}

/// Where `focus` looks: the focused workspace's tree, or on across displays up to their outer frame.
public enum FocusBoundaries: String, Equatable, Sendable {
    case workspace
    case allMonitorsOuterFrame = "all-monitors-outer-frame"
}

/// What `focus` does at its boundary: nothing and succeed, fail, or wrap to the far side of the
/// workspace or of all the displays.
public enum BoundariesAction: String, Equatable, Sendable {
    case stop, fail
    case wrapAroundTheWorkspace = "wrap-around-the-workspace"
    case wrapAroundAllMonitors = "wrap-around-all-monitors"
}

/// A display relative to the focused one: in a direction by frame, or next and previous in display order.
public enum MonitorTarget: String, Equatable, Sendable {
    case left, right, up, down, next, prev

    /// The direction for left, right, up and down; nil for next and prev.
    public var direction: Direction? { Direction(rawValue) }
}

public enum ResizeDimension: String, Equatable, Sendable {
    case smart, width, height
}

/// A state for `layout`, as in AeroSpace: a mode, an orientation, both, or floating or tiling for the window;
/// or scrolling for its workspace.
public enum LayoutName: String, Equatable, Sendable {
    case tiles, accordion, horizontal, vertical, auto
    case hTiles = "h_tiles", vTiles = "v_tiles", hAccordion = "h_accordion", vAccordion = "v_accordion"
    case floating, tiling, scrolling

    /// The one of `names` to apply to a window `current` describes: the one after the last that describes it,
    /// wrapping, so a list cycles and two toggle; the first when none does.
    public static func next(in names: [LayoutName], current: [LayoutName]) -> LayoutName {
        guard let last = names.lastIndex(where: current.contains) else { return names[0] }
        return names[(last + 1) % names.count]
    }

    /// The container mode this sets, nil if it leaves the mode alone.
    public var mode: LayoutMode? {
        switch self {
        case .tiles, .hTiles, .vTiles: .tiles
        case .accordion, .hAccordion, .vAccordion: .accordion
        default: nil
        }
    }

    /// The states a tiled window's container is in: its mode, the axis it runs along now, both together,
    /// and `auto` when it follows its longer side.
    public static func describing(_ mode: LayoutMode, axis: Orientation, auto: Bool) -> [LayoutName] {
        let horizontal = axis == .horizontal
        let both: LayoutName = switch mode {
        case .tiles: horizontal ? .hTiles : .vTiles
        case .accordion: horizontal ? .hAccordion : .vAccordion
        }
        return [mode == .tiles ? .tiles : .accordion, horizontal ? .horizontal : .vertical, both] + (auto ? [.auto] : [])
    }

    /// The container orientation this sets, nil if it leaves the orientation alone.
    public var orientation: ContainerOrientation? {
        switch self {
        case .horizontal, .hTiles, .hAccordion: .horizontal
        case .vertical, .vTiles, .vAccordion: .vertical
        case .auto: .auto
        default: nil
        }
    }
}

public enum Toggle: String, Equatable, Sendable {
    case on, off, toggle
}

extension Direction {
    init?(_ word: String) {
        switch word {
        case "left": self = .left
        case "right": self = .right
        case "up": self = .up
        case "down": self = .down
        default: return nil
        }
    }
}
