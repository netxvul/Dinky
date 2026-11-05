import CoreGraphics

/// A window on screen as the window server lists it, for finding the one under the mouse.
public struct ScreenWindow: Equatable {
    public let id: UInt32
    public let pid: Int32
    public let layer: Int
    public let frame: CGRect

    public init(id: UInt32, pid: Int32, layer: Int, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.frame = frame
    }
}

/// The frontmost of `windows`, front to back, at `point`: the one a click there lands in, such as a picture in
/// picture video floating over the windows of the Space.
public func windowAt(_ point: CGPoint, in windows: [ScreenWindow]) -> ScreenWindow? {
    windows.first { $0.frame.contains(point) }
}
