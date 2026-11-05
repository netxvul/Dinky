import CoreGraphics

/// A press of the mouse button on a tiled window, from the first frame change the window server tells of under it till
/// the window has gone from where it was pressed, which makes the press a drag. The window server tells of a window
/// moving with the button down for more than drags: an app can tell of its window moving as a click activates it,
/// without moving it, and a hand pressing drifts a point or so, which moves a window pressed by its title bar that
/// much. So the press is a click till the window has gone more than `slack` from where it was as the button went
/// down, wherever focusing it has laid its tile out to meanwhile: a click holds any strip still till the button is up,
/// unless a window is fullscreen (`Workspace.holdsScroll`); a focus macOS tells of late scrolls its tree at once,
/// and its windows only once the button is up. A window that goes into its tile has not been dragged there: a pass has
/// put it there. The press goes on from there.
public struct WindowPress: Equatable {
    public let id: WindowID
    /// Where the window was as the button went down, or the tile a pass has put it in since.
    public let frame: CGRect
    /// When the button went down, in seconds: what tells this press from the next.
    public let at: Double

    /// How far, in points, a window can show from where it was pressed with the press still a click.
    public static let slack: CGFloat = 2
    /// How far apart, in seconds, two readings of when the button went down can be and still be one press: the button
    /// comes up between two presses, and no hand presses again this soon.
    static let sameness: Double = 0.02

    public init(id: WindowID, frame: CGRect, at: Double) {
        self.id = id
        self.frame = frame
        self.at = at
    }

    /// The press a frame change of window `id` from `before` comes under, the button having last gone down at `at`:
    /// `known`, the press last heard of, when it is on that window and is that same press; otherwise a new one, from
    /// `before`.
    public static func of(_ id: WindowID, at: Double, from before: CGRect, known: WindowPress?) -> WindowPress {
        guard let known, known.id == id, abs(known.at - at) < sameness else {
            return WindowPress(id: id, frame: before, at: at)
        }
        return known
    }

    /// The press once its window shows at `frame`, with `tile` where its tree lays it out: this one while the window is
    /// within `slack` of where it was pressed; one from there when that is its tile; nil once it has gone anywhere
    /// else, which makes the press a drag from where the window was pressed.
    public func after(_ frame: CGRect, tile: CGRect?) -> WindowPress? {
        if frame.isClose(to: self.frame, within: Self.slack) { return self }
        guard let tile, frame.isClose(to: tile, within: Self.slack) else { return nil }
        return WindowPress(id: id, frame: frame, at: at)
    }
}
