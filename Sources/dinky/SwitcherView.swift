import AppKit
import DinkyLayout

/// A window as the switcher shows it.
struct SwitcherItem {
    let id: WindowID
    let app: String
    let icon: NSImage?
}

// The switcher's capsule content: a card per window, its thumbnail or, without one, its app's icon on a tint, with the
// app's icon in a corner. The picked card grows a little and the others dim; a ring of the accent colour sits over it,
// above every card so no thumbnail covers it, a few points out from its grown edges with corners about the same
// centres as its own, and a faint glow of the colour under it. Both spring to the next card. Layers, in the frames
// the caller gives. Main thread only.
final class SwitcherView: NSView {
    /// How the cards sit: a row has room around each card, a map's cells only a narrow gap.
    struct Style {
        var cardRadius: CGFloat
        var pickedScale: CGFloat

        static let row = Style(cardRadius: 10, pickedScale: 1.08)
        static let map = Style(cardRadius: 7, pickedScale: 1.03)
    }

    /// Points from the picked card's grown edge to the ring's outer edge; the ring's line lies within them.
    private static let ringOutset: CGFloat = 3
    private static let ringWidth: CGFloat = 2.5

    private static let dimmed: Float = 0.6
    private static let badgeSize: CGFloat = 20
    private static let placeholderIconSize: CGFloat = 32

    private var items: [SwitcherItem] = []
    private var frames: [CGRect] = []
    private var style = Style.row
    private var cards: [Card] = []
    private let glow = CALayer()
    private let ring = CALayer()
    private(set) var picked = 0
    var animates = true

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Hosting its own layers, laid out from the top left as the frames are.
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
        for layer in [glow, ring] {
            layer.cornerCurve = .continuous
            self.layer?.addSublayer(layer)
        }
        ring.borderWidth = Self.ringWidth
        ring.zPosition = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Lays out `items` in `frames` for a new showing, with `picked` picked and no animation.
    func show(_ items: [SwitcherItem], frames: [CGRect], style: Style, picked: Int, scale: CGFloat) {
        self.items = items
        self.frames = frames
        self.style = style
        self.picked = picked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards.forEach { $0.root.removeFromSuperlayer() }
        let radius = style.cardRadius * style.pickedScale + Self.ringOutset
        glow.cornerRadius = radius
        ring.cornerRadius = radius
        cards = zip(items, frames).map { item, frame in
            let card = Card(frame: frame, icon: item.icon, radius: style.cardRadius, scale: scale)
            card.image = Thumbnails.shared.image(of: item.id)
            layer?.addSublayer(card.root)
            return card
        }
        applyColors()
        place(animated: false)
        CATransaction.commit()
    }

    /// Picks another card, springing the ring over to it.
    func pick(_ index: Int) {
        guard index != picked, cards.indices.contains(index) else { return }
        picked = index
        place(animated: animates)
    }

    /// A fresh thumbnail for a window shown, faded in.
    func update(_ id: WindowID, image: CGImage) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animates)
        CATransaction.setAnimationDuration(0.2)
        cards[i].image = image
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func place(animated: Bool) {
        guard cards.indices.contains(picked) else { return }
        // The card as it is once grown about its centre, and the ring around it.
        let card = frames[picked]
        let grown = card.insetBy(dx: -card.width * (style.pickedScale - 1) / 2, dy: -card.height * (style.pickedScale - 1) / 2)
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
        for (i, card) in cards.enumerated() {
            card.root.transform = i == picked ? CATransform3DMakeScale(style.pickedScale, style.pickedScale, 1) : CATransform3DIdentity
            card.root.opacity = i == picked ? 1 : Self.dimmed
            // Grown, it goes over its neighbours.
            card.root.zPosition = i == picked ? 1 : 0
        }
        CATransaction.commit()
    }

    /// Resolves the dynamic colours for the current appearance.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            ring.borderColor = NSColor.controlAccentColor.cgColor
            for card in cards {
                card.thumb.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                card.thumb.borderColor = NSColor.separatorColor.cgColor
            }
            CATransaction.commit()
        }
    }

    /// One window's card: the thumbnail, clipped to its corners, and the app's icon, in the middle until there is a
    /// thumbnail and in the corner after.
    private final class Card {
        let root = CALayer()
        let thumb = CALayer()
        private let icon = CALayer()
        private let size: CGSize

        init(frame: CGRect, icon image: NSImage?, radius: CGFloat, scale: CGFloat) {
            size = frame.size
            root.frame = frame
            thumb.frame = root.bounds
            thumb.cornerRadius = radius
            thumb.cornerCurve = .continuous
            thumb.masksToBounds = true
            thumb.borderWidth = 0.5
            thumb.contentsGravity = .resizeAspectFill
            root.addSublayer(thumb)
            icon.contents = image.flatMap { $0.layerContents(forContentsScale: scale) }
            icon.contentsScale = scale
            icon.contentsGravity = .resizeAspect
            icon.shadowOpacity = 0.3
            icon.shadowRadius = 2
            icon.shadowOffset = CGSize(width: 0, height: -1)
            root.addSublayer(icon)
            placeIcon()
        }

        var image: CGImage? {
            get { thumb.contents.map { $0 as! CGImage } }
            set {
                thumb.contents = newValue
                placeIcon()
            }
        }

        private func placeIcon() {
            if thumb.contents == nil {
                let side = min(SwitcherView.placeholderIconSize, size.width - 8, size.height - 8)
                icon.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            } else {
                let side = min(SwitcherView.badgeSize, size.height / 2)
                icon.frame = CGRect(x: 4, y: size.height - side - 4, width: side, height: side)
            }
        }
    }
}
