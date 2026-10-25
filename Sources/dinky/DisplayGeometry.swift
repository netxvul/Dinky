import AppKit
import DinkyConfig
import DinkyLayout

/// The NSScreen showing a display.
func screen(of id: CGDirectDisplayID) -> NSScreen? {
    let number = NSDeviceDescriptionKey("NSScreenNumber")
    return NSScreen.screens.first { ($0.deviceDescription[number] as? NSNumber)?.uint32Value == id }
}

/// The NSScreen under a frame's centre, or the primary one. Frames are top-left global, NSScreen frames bottom-left,
/// flipped around the primary screen.
func screen(containing frame: CGRect) -> NSScreen? {
    let screens = NSScreen.screens
    guard let primary = screens.first else { return nil }
    let center = CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
    return screens.first { $0.frame.contains(center) } ?? primary
}

/// The display's frame minus menu bar and Dock, in CG coordinates (top-left origin at the primary display);
/// `frame` when no screen shows it.
func visibleArea(of id: CGDirectDisplayID, frame: CGRect) -> CGRect {
    guard let primary = NSScreen.screens.first, let screen = screen(of: id) else { return frame }
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
}

// What the layout needs from a display: its NSScreen and name, and the config's gaps resolved for it.
extension Display {
    /// The name System Settings shows, such as "Built-in Retina Display".
    var name: String { screen(of: id)?.localizedName ?? "" }
}

extension DisplayModel {
    /// What `[display.<pattern>]` tables are matched against.
    func monitor(_ display: Display) -> Monitor {
        Monitor(name: display.name, isMain: display.isMain, count: displays.count)
    }
}

extension DinkyLayout.Gaps {
    init(_ gaps: DinkyConfig.Gaps) {
        self.init(horizontal: CGFloat(gaps.inner.horizontal), vertical: CGFloat(gaps.inner.vertical),
                  top: CGFloat(gaps.outer.top), bottom: CGFloat(gaps.outer.bottom),
                  left: CGFloat(gaps.outer.left), right: CGFloat(gaps.outer.right))
    }
}
