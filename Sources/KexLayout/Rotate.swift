/// A clockwise turn for `rotate`, as yabai's `space --rotate`.
public enum Rotation: Int, Equatable, Sendable {
    case quarter = 90, half = 180, threeQuarters = 270
}

/// The axis `mirror` flips across, as yabai's `space --mirror`: across the y-axis left and right swap, across the
/// x-axis top and bottom.
public enum MirrorAxis: String, Equatable, Sendable {
    case xAxis = "x-axis", yAxis = "y-axis"
}

/// Turning and flipping the whole tree, the picture of the tiles turning or flipping with it. A container set to
/// `auto` takes the axis it runs along now and keeps it, turned, as its fixed orientation: following the longer side
/// would undo the turn. Ratios and the active child move with the children.
extension Workspace {
    /// Whether the tree can be turned and flipped: a fixed layout's template and the scrolling strip cannot.
    public var rearranges: Bool {
        if isScrolling { return false }
        if case .fixed = algorithm, isFixedTree { return false }
        return true
    }

    /// Turn the tree clockwise. A quarter turn makes a row a column in the same order, and a column a row with
    /// its top on the right; a half turn reverses every container. False when there is nothing to turn.
    @discardableResult
    public mutating func rotate(_ rotation: Rotation) -> Bool {
        guard rearranges, windows.count > 1 else { return false }
        endFullscreen()
        root = turned(root, at: [], rotation, in: tiledLayout())
        normalize()
        if let focused { focus(focused) }
        return true
    }

    /// Flip the tree across `axis`. False when no container runs across it, so nothing would move.
    @discardableResult
    public mutating func mirror(_ axis: MirrorAxis) -> Bool {
        guard rearranges, windows.count > 1 else { return false }
        let along: Orientation = axis == .yAxis ? .horizontal : .vertical
        var flipped = false
        let mirrored = flipping(root, at: [], along, in: tiledLayout(), &flipped)
        guard flipped else { return false }
        endFullscreen()
        root = mirrored
        normalize()
        if let focused { focus(focused) }
        return true
    }

    /// `container`, at `path` in the tree as it is, turned with everything below it.
    private func turned(_ container: Container, at path: [Int], _ rotation: Rotation, in layout: Layout) -> Container {
        var result = container
        let axis = axisOfContainer(at: path, in: layout)
        for (i, child) in container.children.enumerated() {
            if case .container(let inner) = child {
                result.replace(at: i, with: .container(turned(inner, at: path + [i], rotation, in: layout)))
            }
        }
        let reverses = switch rotation {
        case .half: true
        case .quarter: axis == .vertical
        case .threeQuarters: axis == .horizontal
        }
        if rotation != .half { result.orientation = ContainerOrientation(axis.opposite) }
        if reverses { result.reverse() }
        return result
    }

    /// `container`, at `path` in the tree as it is, with every container running `along` reversed.
    private func flipping(_ container: Container, at path: [Int], _ along: Orientation, in layout: Layout,
                          _ flipped: inout Bool) -> Container {
        var result = container
        for (i, child) in container.children.enumerated() {
            if case .container(let inner) = child {
                result.replace(at: i, with: .container(flipping(inner, at: path + [i], along, in: layout, &flipped)))
            }
        }
        if container.children.count > 1, axisOfContainer(at: path, in: layout) == along {
            result.reverse()
            flipped = true
        }
        return result
    }
}
