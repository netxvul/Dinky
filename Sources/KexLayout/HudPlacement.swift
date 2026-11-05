import CoreGraphics

/// Where the HUD capsule goes on a screen, in AppKit coordinates (bottom-left origin), from the screen's frame and
/// visible frame: centred across the visible frame, `offset` points above the Dock at the bottom or below the menu
/// bar at the top. Where the Dock hides or sits at a side the visible frame reaches the bottom edge, so the capsule
/// sits `offset` points from it.
public enum HudPlacement {
    public static func frame(size: CGSize, screen: CGRect, visible: CGRect, top: Bool, offset: CGFloat) -> CGRect {
        let width = min(size.width, visible.width), height = size.height
        let x = (visible.midX - width / 2).rounded()
        let y = top ? visible.maxY - offset - height : visible.minY + offset
        // Stay on the screen whatever the offset.
        let clamped = min(max(y, screen.minY), screen.maxY - height)
        return CGRect(x: x, y: clamped.rounded(), width: width, height: height)
    }
}
