import AppKit
import DinkyConfig

extension Highlight {
    /// The colour to draw with: the accent colour in System Settings, following it as it changes, or the config's.
    var nsColor: NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .color(let color): color.nsColor
        }
    }

    /// The colour as sRGB components, for drawing outside AppKit: the accent colour as it is now, or the config's.
    var resolved: DinkyConfig.Color {
        switch self {
        case .color(let color):
            return color
        case .accent:
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return DinkyConfig.Color(red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent,
                                     alpha: accent.alphaComponent)
        }
    }
}

extension DinkyConfig.Color {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension NSColor {
    /// This colour with its alpha scaled by `fraction`, so a translucent highlight stays as translucent relative to it.
    func fading(to fraction: CGFloat) -> NSColor { withAlphaComponent(alphaComponent * fraction) }
}
