import AppKit
import DinkyLayout

/// A workspace as the workspace switcher shows it.
struct WorkspaceCard {
    let space: UInt64
    /// Nil for a Space that is no numbered workspace.
    let number: Int?
    let display: Display
    /// Its number and layout, such as `2 · scrolling`.
    let label: String
    /// Whether its display shows it now.
    let current: Bool
    let miniature: Miniature
    /// Each window's app icon.
    let icons: [WindowID: NSImage]
    /// The card is a fixed picture of its layout, `Schematic`'s, its windows plain blocks with a title bar.
    let schematic: Bool
}

// The workspace switcher's capsule content: per workspace, its display drawn small with each window where it is,
// filled with its thumbnail or, without one, its app's icon on a tint; on a schematic card, a fixed picture of the
// layout whatever its windows, plain blocks with a title bar, a gap apart, in the accent colour on the picked card; an accordion's covered windows faded, a fixed
// workspace's empty cells dashed, a strip's parked columns a sliver at each side with their count. Its label under
// it, a dot before the label of each display's current workspace, and with several displays each one's name over
// its group and a line between. The picked card grows a little and the others dim; the window switcher's ring and
// glow spring to it. Schematic cards are drawn as Windows draws its snap layouts: solid grey windows with a hairline
// edge on no backdrop, the picked card's all in the accent colour. Layers, in the frames the caller gives. Main thread only.
final class WorkspaceSwitcherView: NSView {
    private static let pickedScale: CGFloat = 1.05
    private static let ringOutset: CGFloat = 3
    private static let ringWidth: CGFloat = 2.5
    private static let dimmed: Float = 0.6
    private static let schematicDimmed: Float = 0.75
    private static let cardRadius: CGFloat = 6
    private static let tileRadius: CGFloat = 3
    private static let schematicRadius: CGFloat = 5
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private static let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    private var cards: [WorkspaceCard] = []
    private var layout = WorkspaceSwitcherLayout(groups: [], cardHeight: 0, maxWidth: 0)
    private var views: [CardLayers] = []
    private var chrome: [CALayer] = []
    private let glow = CALayer()
    private let ring = CALayer()
    private(set) var picked = 0
    var animates = true

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        for layer in [glow, ring] {
            layer.cornerCurve = .continuous
            layer.cornerRadius = Self.cardRadius * Self.pickedScale + Self.ringOutset
            self.layer?.addSublayer(layer)
        }
        ring.borderWidth = Self.ringWidth
        ring.zPosition = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Lays out `cards` as `layout` says for a new showing, with `picked` picked and no animation. `headers` names
    /// each group.
    func show(_ cards: [WorkspaceCard], layout: WorkspaceSwitcherLayout, headers: [String], picked: Int, scale: CGFloat) {
        self.cards = cards
        self.layout = layout
        self.picked = picked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        views.forEach {
            $0.root.removeFromSuperlayer()
            $0.label.removeFromSuperlayer()
        }
        chrome.forEach { $0.removeFromSuperlayer() }
        chrome = []
        views = zip(cards, zip(layout.frames, layout.labels)).map { card, frames in
            let view = CardLayers(card, frame: frames.0, label: frames.1, scale: scale)
            layer?.addSublayer(view.root)
            layer?.addSublayer(view.label)
            return view
        }
        for (name, frame) in zip(headers, layout.headers) {
            let text = Self.text(name, font: Self.headerFont, scale: scale)
            text.frame = frame
            text.alignmentMode = .left
            text.truncationMode = .end
            chrome.append(text)
        }
        for x in layout.dividers {
            let line = CALayer()
            let top = layout.frames.first?.minY ?? 0
            line.frame = CGRect(x: x - 0.5, y: top, width: 1, height: layout.cardHeight + WorkspaceSwitcherLayout.labelHeight)
            chrome.append(line)
        }
        chrome.forEach { layer?.addSublayer($0) }
        applyColors()
        place(animated: false)
        CATransaction.commit()
    }

    /// Picks another card, springing the ring over to it.
    func pick(_ index: Int) {
        guard index != picked, views.indices.contains(index) else { return }
        picked = index
        place(animated: animates)
    }

    /// A fresh thumbnail for a window shown, faded in.
    func update(_ id: WindowID, image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animates)
        CATransaction.setAnimationDuration(0.2)
        views.forEach { $0.set(image, for: id) }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func place(animated: Bool) {
        guard views.indices.contains(picked) else { return }
        let card = layout.frames[picked]
        let grown = card.insetBy(dx: -card.width * (Self.pickedScale - 1) / 2, dy: -card.height * (Self.pickedScale - 1) / 2)
        let target = grown.insetBy(dx: -Self.ringOutset, dy: -Self.ringOutset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [glow, ring] {
            if animated, let shown = layer.presentation() {
                for (key, from, to) in [("position", NSValue(point: shown.position), NSValue(point: CGPoint(x: target.midX, y: target.midY))),
                                        ("bounds.size", NSValue(size: shown.bounds.size), NSValue(size: target.size))] {
                    let spring = CASpringAnimation(keyPath: key)
                    spring.mass = 1
                    spring.stiffness = 320
                    spring.damping = 26
                    spring.fromValue = from
                    spring.toValue = to
                    spring.duration = spring.settlingDuration
                    layer.add(spring, forKey: key)
                }
            }
            layer.frame = target
        }
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let schematic = cards.first?.schematic == true
        for (i, view) in views.enumerated() {
            view.root.transform = i == picked ? CATransform3DMakeScale(Self.pickedScale, Self.pickedScale, 1) : CATransform3DIdentity
            view.root.opacity = i == picked ? 1 : schematic ? Self.schematicDimmed : Self.dimmed
            view.root.zPosition = i == picked ? 1 : 0
            view.label.opacity = i == picked ? 1 : 0.75
        }
        CATransaction.commit()
        applyColors()
    }

    /// Resolves the dynamic colours for the current appearance.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            ring.borderColor = NSColor.controlAccentColor.cgColor
            for (i, view) in views.enumerated() { view.applyColors(picked: i == picked) }
            for layer in chrome {
                if let text = layer as? CATextLayer {
                    text.foregroundColor = NSColor.secondaryLabelColor.cgColor
                } else {
                    layer.backgroundColor = NSColor.separatorColor.cgColor
                }
            }
            CATransaction.commit()
        }
    }

    fileprivate static func text(_ string: String, font: NSFont, scale: CGFloat) -> CATextLayer {
        let text = CATextLayer()
        text.string = string
        text.font = font
        text.fontSize = font.pointSize
        text.contentsScale = scale
        text.alignmentMode = .center
        text.truncationMode = .middle
        return text
    }

    /// One workspace's card: the display, its windows, slivers and counts for a strip's parked columns, and its label.
    private final class CardLayers {
        let root = CALayer()
        private(set) var label = CATextLayer()
        private let screen = CALayer()
        private var tiles: [(id: WindowID, layer: CALayer, icon: CALayer, behind: Bool)] = []
        private let schematic: Bool
        private var slivers: [CALayer] = []
        private var counts: [(pill: CALayer, text: CATextLayer)] = []
        private var empties: [CAShapeLayer] = []
        private let dot = CALayer()
        private let current: Bool
        private let isEmpty: Bool

        init(_ card: WorkspaceCard, frame: CGRect, label labelFrame: CGRect, scale: CGFloat) {
            current = card.current
            schematic = card.schematic
            let mini = card.miniature
            isEmpty = mini.tiles.isEmpty && mini.emptyCells.isEmpty
            root.frame = frame
            // The miniature is as wide as its display; the card may have been scaled down since.
            let fit = mini.size.width > 0 && mini.size.height > 0
                ? min(frame.width / mini.size.width, frame.height / mini.size.height) : 1
            func scaled(_ r: CGRect) -> CGRect {
                CGRect(x: (r.minX * fit).rounded(), y: (r.minY * fit).rounded(), width: (r.width * fit).rounded(), height: (r.height * fit).rounded())
            }
            screen.frame = root.bounds
            screen.cornerRadius = WorkspaceSwitcherView.cardRadius
            screen.cornerCurve = .continuous
            screen.masksToBounds = true
            root.addSublayer(screen)
            for left in [true, false] {
                guard let sliver = schematic ? mini.schematicSliver(left: left) : mini.parkedSliver(left: left) else { continue }
                let layer = CALayer()
                layer.frame = scaled(sliver)
                layer.cornerRadius = 2
                if schematic {
                    // A rounded window hanging off the edge, the card clipping it.
                    let radius = WorkspaceSwitcherView.schematicRadius
                    layer.frame = layer.frame.insetBy(dx: -radius / 2, dy: 0).offsetBy(dx: left ? -radius / 2 : radius / 2, dy: 0)
                    layer.cornerRadius = radius
                    layer.borderWidth = 1
                }
                screen.addSublayer(layer)
                slivers.append(layer)
            }
            for cell in mini.emptyCells {
                let shape = CAShapeLayer()
                let rect = scaled(cell)
                shape.frame = rect
                shape.path = CGPath(roundedRect: CGRect(origin: .zero, size: rect.size).insetBy(dx: 0.5, dy: 0.5),
                                    cornerWidth: WorkspaceSwitcherView.tileRadius, cornerHeight: WorkspaceSwitcherView.tileRadius, transform: nil)
                shape.fillColor = nil
                shape.lineWidth = 1
                shape.lineDashPattern = [3, 2.5]
                screen.addSublayer(shape)
                empties.append(shape)
            }
            if isEmpty {
                let shape = CAShapeLayer()
                shape.frame = root.bounds
                shape.path = CGPath(roundedRect: root.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: WorkspaceSwitcherView.cardRadius,
                                    cornerHeight: WorkspaceSwitcherView.cardRadius, transform: nil)
                shape.fillColor = nil
                shape.lineWidth = 1
                shape.lineDashPattern = [4, 3]
                root.addSublayer(shape)
                empties.append(shape)
            }
            for tile in mini.tiles {
                let layer = CALayer()
                layer.frame = scaled(tile.frame)
                layer.cornerRadius = WorkspaceSwitcherView.tileRadius
                layer.cornerCurve = .continuous
                layer.masksToBounds = true
                layer.borderWidth = 0.5
                layer.contentsGravity = .resizeAspectFill
                layer.opacity = tile.behind && !schematic ? 0.55 : 1
                let icon = CALayer()
                screen.addSublayer(layer)
                tiles.append((tile.id, layer, icon, tile.behind))
                if schematic {
                    drawWindow(layer)
                } else {
                    icon.contents = card.icons[tile.id].flatMap { $0.layerContents(forContentsScale: scale) }
                    icon.contentsScale = scale
                    icon.contentsGravity = .resizeAspect
                    layer.addSublayer(icon)
                    set(Thumbnails.shared.image(of: tile.id), for: tile.id)
                }
            }
            // A schematic card's slivers stand for parked columns in general, not a count.
            for (left, count) in [(true, mini.parkedLeft), (false, mini.parkedRight)] where count > 0 && !card.schematic {
                let string = left ? "‹ \(count)" : "\(count) ›"
                let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
                let text = WorkspaceSwitcherView.text(string, font: font, scale: scale)
                let width = (string as NSString).size(withAttributes: [.font: font]).width + 10, height: CGFloat = 13
                let inset = (frame.width * Miniature.parkedInset).rounded()
                let pill = CALayer()
                pill.frame = CGRect(x: left ? inset + 3 : frame.width - inset - 3 - width, y: frame.height - height - 4,
                                    width: width, height: height)
                pill.cornerRadius = height / 2
                text.frame = CGRect(x: 0, y: 0.5, width: width, height: height)
                pill.addSublayer(text)
                screen.addSublayer(pill)
                counts.append((pill, text))
            }

            label = WorkspaceSwitcherView.text(card.label, font: WorkspaceSwitcherView.labelFont, scale: scale)
            let textWidth = (card.label as NSString).size(withAttributes: [.font: WorkspaceSwitcherView.labelFont]).width
            let dotSize: CGFloat = 6, dotGap: CGFloat = 5
            let shownWidth = min(textWidth + (current ? dotSize + dotGap : 0), labelFrame.width)
            let left = labelFrame.minX + (labelFrame.width - shownWidth) / 2
            label.frame = CGRect(x: left + (current ? dotSize + dotGap : 0), y: labelFrame.minY + 5,
                                 width: shownWidth - (current ? dotSize + dotGap : 0), height: 15)
            label.alignmentMode = .left
            if current {
                dot.frame = CGRect(x: left, y: labelFrame.minY + 5 + (15 - dotSize) / 2, width: dotSize, height: dotSize)
                dot.cornerRadius = dotSize / 2
                label.addSublayer(dot)
                dot.frame = dot.frame.offsetBy(dx: -label.frame.minX, dy: -label.frame.minY)
                label.masksToBounds = false
            }
        }

        /// A schematic window: a solid rounded block with a hairline edge, which also parts overlapping windows.
        private func drawWindow(_ layer: CALayer) {
            let size = layer.bounds.size
            layer.cornerRadius = min(WorkspaceSwitcherView.schematicRadius, size.width / 4, size.height / 4)
            layer.borderWidth = 1
        }

        func set(_ image: CGImage?, for id: WindowID) {
            for tile in tiles where tile.id == id && tile.icon.superlayer != nil {
                if let image { tile.layer.contents = image }
                let size = tile.layer.bounds.size
                if tile.layer.contents == nil {
                    let side = min(28, size.width - 6, size.height - 6)
                    tile.icon.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: max(side, 0), height: max(side, 0))
                } else {
                    let side = min(14, size.height / 2, size.width / 2)
                    tile.icon.frame = CGRect(x: 3, y: size.height - side - 3, width: side, height: side)
                }
            }
        }

        func applyColors(picked: Bool) {
            screen.backgroundColor = schematic ? nil : NSColor.labelColor.withAlphaComponent(0.07).cgColor
            if schematic {
                // Solid, as Windows' snap layouts: grey, the picked card's in the accent colour.
                let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
                let fill = picked ? accent : dark ? NSColor(srgbRed: 0.29, green: 0.30, blue: 0.33, alpha: 1)
                                                  : NSColor(srgbRed: 0.89, green: 0.89, blue: 0.90, alpha: 1)
                let edge = picked ? (dark ? accent.blended(withFraction: 0.25, of: .white) : accent.blended(withFraction: 0.2, of: .black)) ?? accent
                                  : dark ? NSColor(srgbRed: 0.38, green: 0.39, blue: 0.42, alpha: 1)
                                         : NSColor(srgbRed: 0.75, green: 0.75, blue: 0.78, alpha: 1)
                for tile in tiles {
                    tile.layer.backgroundColor = fill.cgColor
                    tile.layer.borderColor = edge.cgColor
                }
                for sliver in slivers {
                    sliver.backgroundColor = (picked ? accent.withAlphaComponent(0.55) : fill.withAlphaComponent(0.85)).cgColor
                    sliver.borderColor = edge.cgColor
                }
            } else {
                for tile in tiles {
                    tile.layer.backgroundColor = NSColor.windowBackgroundColor.blended(withFraction: 0.15, of: .labelColor)?.cgColor
                    tile.layer.borderColor = NSColor.separatorColor.cgColor
                }
            }
            for sliver in slivers where !schematic { sliver.backgroundColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor }
            for count in counts {
                count.pill.backgroundColor = NSColor.labelColor.withAlphaComponent(0.72).cgColor
                count.text.foregroundColor = NSColor.windowBackgroundColor.cgColor
            }
            for empty in empties { empty.strokeColor = NSColor.tertiaryLabelColor.cgColor }
            label.foregroundColor = (picked ? NSColor.labelColor : NSColor.secondaryLabelColor).cgColor
            dot.backgroundColor = (picked ? NSColor.labelColor : NSColor.secondaryLabelColor).cgColor
        }
    }
}
