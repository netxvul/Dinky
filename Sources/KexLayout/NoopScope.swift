import Foundation

/// The physical left and right sides of a screen.
public struct ScreenSides: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ScreenSides(rawValue: 1)
    public static let right = ScreenSides(rawValue: 2)
    public static let both: ScreenSides = [.left, .right]
}

/// How far what a command found missing reaches, which is how much of the screen the noop flash lights.
public enum NoopScope: Equatable {
    /// Nothing to do for the focused window: its edge glows. `toward` is the side a step ran into, left or right, for a
    /// strip across two displays, whose end is at the display's edge rather than the window's.
    case window(toward: Direction? = nil)
    /// No workspace to go to: these sides of the display with this UUID glow, the display under the pointer with none.
    case workspace(ScreenSides, display: String?)
    /// No display to go to, or none that takes a window: all four edges of the display with this UUID glow.
    case display(String)

    /// A step in `direction` from the focused window that found nothing there.
    public static func stepping(_ direction: Direction) -> NoopScope {
        .window(toward: direction.orientation == .horizontal ? direction : nil)
    }

    /// What a binding whose commands answered `scopes` flashes, once however many did nothing: the widest of them, the
    /// first of those, and among windows the first that stepped sideways, which is the one a strip's end can show.
    public static func widest(_ scopes: [NoopScope]) -> NoopScope? {
        scopes.reduce(nil) { best, scope in
            guard let best else { return scope }
            if scope.width != best.width { return scope.width > best.width ? scope : best }
            if case .window(nil) = best { return scope }
            return best
        }
    }

    private var width: Int {
        switch self {
        case .window: 0
        case .workspace: 1
        case .display: 2
        }
    }
}
