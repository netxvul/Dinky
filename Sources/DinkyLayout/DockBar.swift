import CoreGraphics

/// Whether the Dock's bar, as Accessibility gives it in global top-left coordinates, is shown: whole on one of
/// `displays` and within its thickness, its shorter side, of that display's bottom, left or right edge, never the
/// top. The bar's own frame stops short of the edge: 10 pt above the bottom of Netx's 1800 x 1169 display (163, 1101,
/// 1474 x 58). One sliding in or out is taken to lie further off or past the edge; what Accessibility gives for an
/// auto-hidden Dock while hidden is unmeasured, as Netx's Dock does not hide.
public func dockBarShown(_ frame: CGRect, on displays: [CGRect]) -> Bool {
    let thickness = min(frame.width, frame.height)
    return displays.contains { d in
        d.contains(frame) && (d.maxY - frame.maxY < thickness || frame.minX - d.minX < thickness
            || d.maxX - frame.maxX < thickness)
    }
}
