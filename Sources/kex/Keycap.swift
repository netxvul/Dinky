import AppKit

// A window's letter in the switchers, drawn as a key on a keyboard: the letter in capitals on a small rounded face
// with a hairline edge, and a slightly deeper lip along its foot. On the capsule's glass it is a light key that follows
// the appearance; on a dark band or a thumbnail, a white key with a dark letter. The picked window's key takes the
// highlight colour, its letter white. Layers, in the switchers' flipped coordinates. Main thread only.
final class Keycap {
    let root = CALayer()
    let size: CGSize
    private let face = CALayer()
    private let lip = CALayer()
    private let text = CATextLayer()
    private let onDark: Bool
    /// Points the lip shows below the face.
    private static let lipDepth: CGFloat = 1

    /// A key `height` tall, its face and lip together, for `letter`; `onDark` for one over a band or a thumbnail.
    init(_ letter: Character, height: CGFloat, scale: CGFloat, onDark: Bool) {
        self.onDark = onDark
        let font = NSFont.monospacedSystemFont(ofSize: (height * 0.62).rounded(), weight: .semibold)
        let string = String(letter).uppercased()
        let faceHeight = height - Self.lipDepth
        let width = max(faceHeight + 1, ceil((string as NSString).size(withAttributes: [.font: font]).width) + 6)
        size = CGSize(width: width, height: height)
        root.bounds = CGRect(origin: .zero, size: size)
        let radius = min(4, faceHeight * 0.3)
        for layer in [lip, face] {
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            root.addSublayer(layer)
        }
        lip.frame = CGRect(x: 0, y: Self.lipDepth, width: width, height: faceHeight)
        face.frame = CGRect(x: 0, y: 0, width: width, height: faceHeight)
        face.borderWidth = 0.5
        text.string = string
        text.font = font
        text.fontSize = font.pointSize
        text.contentsScale = scale
        text.alignmentMode = .center
        let line = ceil(font.ascender - font.descender)
        // Capitals sit above the line's middle; down a little so they look centred.
        text.frame = CGRect(x: 0, y: ((faceHeight - line) / 2 + font.pointSize * 0.04).rounded(), width: width, height: line)
        face.addSublayer(text)
        if onDark {
            root.shadowOpacity = 0.35
            root.shadowRadius = 1.5
            root.shadowOffset = .zero
            // Its outline given, so the shadow needs no pass of its own to find it.
            root.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: radius,
                                     cornerHeight: radius, transform: nil)
        }
    }

    /// Colours for the current appearance, the picked window's in `highlight`.
    func applyColors(picked: Bool, highlight: NSColor) {
        if picked {
            let base = highlight.usingColorSpace(.sRGB) ?? .systemBlue
            face.backgroundColor = base.withAlphaComponent(1).cgColor
            face.borderColor = (base.blended(withFraction: 0.25, of: .white) ?? base).cgColor
            lip.backgroundColor = (base.blended(withFraction: 0.4, of: .black) ?? base).cgColor
            text.foregroundColor = NSColor.white.cgColor
        } else if onDark {
            face.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
            face.borderColor = NSColor(white: 1, alpha: 1).cgColor
            lip.backgroundColor = NSColor(white: 0.55, alpha: 1).cgColor
            text.foregroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        } else {
            face.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
            face.borderColor = NSColor.separatorColor.cgColor
            lip.backgroundColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
            text.foregroundColor = NSColor.labelColor.cgColor
        }
    }
}
