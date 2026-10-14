import AppKit

// The menu bar item's image for `menu-bar-icon = 'blocks'`: a rounded block per display, left to right as the
// displays are arranged, shaped like its display. The focused display's block is filled with its workspace number
// cut out, so the menu bar shows through; the others are outlined with the number drawn in. A full-screen Space
// has no workspace number and gets corner marks instead; a display without workspaces, whose Space is unnumbered,
// gets an empty block. After DeskPeek's IconCreator (MIT, Sasindu Jayasinghe).
struct MenuBarBlocks: Equatable {
    struct Block: Equatable {
        /// Nil where the Space is not a workspace, as on a display `[workspace-to-display]` gives none.
        let number: Int?
        let fullScreen: Bool
        let focused: Bool
        /// Width over height, kept between 1:2 and 2:1.
        let aspect: CGFloat
    }

    let blocks: [Block]

    init(displays: [Display], focused: Display?, number: (Display) -> Int?) {
        blocks = displays.sorted { $0.frame.minX < $1.frame.minX }.map { display in
            Block(number: number(display),
                  fullScreen: !display.userSpaces.contains(display.currentSpaceID),
                  focused: display.uuid == focused?.uuid,
                  aspect: min(max(display.frame.width / max(display.frame.height, 1), 0.5), 2))
        }
    }

    private static let height: CGFloat = 16
    private static let radius: CGFloat = 4
    private static let gap: CGFloat = 6
    private static let lineWidth: CGFloat = 1.5
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    /// A template image, so the menu bar tints it for light and dark and dims it when disabled.
    func image() -> NSImage {
        let widths = blocks.map { Self.height * $0.aspect }
        let width = widths.reduce(0, +) + Self.gap * CGFloat(max(blocks.count - 1, 0))
        let image = NSImage(size: NSSize(width: max(width, 1), height: Self.height), flipped: false) { _ in
            var x: CGFloat = 0
            for (block, width) in zip(blocks, widths) {
                Self.draw(block, in: NSRect(x: x, y: 0, width: width, height: Self.height))
                x += width + Self.gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ block: Block, in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        NSColor.black.set()
        if block.focused {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            context.compositingOperation = .destinationOut
        } else {
            let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let outline = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
            outline.lineWidth = lineWidth
            outline.stroke()
        }
        if block.fullScreen {
            drawCornerMarks(in: rect)
        } else if let number = block.number {
            drawNumber(String(number), in: rect)
        }
    }

    private static func drawNumber(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let line = NSRect(x: rect.minX, y: rect.minY + (rect.height - size.height) / 2, width: rect.width, height: size.height)
        (text as NSString).draw(in: line, withAttributes: attributes)
    }

    /// └ at the top left and ┘ at the bottom right, for a full-screen Space.
    private static func drawCornerMarks(in rect: NSRect) {
        let margin = 3.0, length = 4.0
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let top = rect.maxY - margin, left = rect.minX + margin
        path.move(to: NSPoint(x: left, y: top - length))
        path.line(to: NSPoint(x: left, y: top))
        path.line(to: NSPoint(x: left + length, y: top))
        let bottom = rect.minY + margin, right = rect.maxX - margin
        path.move(to: NSPoint(x: right - length, y: bottom))
        path.line(to: NSPoint(x: right, y: bottom))
        path.line(to: NSPoint(x: right, y: bottom + length))
        path.stroke()
    }
}
