import AppKit
import DinkyConfig
import DinkyLayout

/// A window as the switcher shows it.
struct SwitcherItem {
    let id: WindowID
    let app: String
    let icon: NSImage?
    /// The window's title, the app's name when it has none; empty while not known yet.
    var title: String
    /// The letter whose key jumps to it; nil for none.
    var letter: Character? = nil
}

// The switcher's capsule content: a card per window, its thumbnail or, without one, its app's icon on a tint, with the
// app's icon in a corner. The picked card grows a little and the others dim; a ring of the accent colour sits over it,
// above every card so no thumbnail covers it, a few points out from its grown edges with corners about the same
// centres as its own, and a faint glow of the colour under it. Both spring to the next card. With titles, each card's
// window title sits under it, or along its foot on a dark band where another card sits right below it, as on a map or
// over a column's lower window. A window with a letter has it drawn as a key (`Keycap`) at the title's right: under
// the card, the title and the key centred together; on a band, the key at its right end; with no title, the key alone
// in its place. The picked card's key takes the highlight colour. Layers, in the frames the caller gives. Main thread
// only.
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
    private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// Points from a card's foot to its title under it.
    private static let titleGap: CGFloat = 4
    private static let bandHeight: CGFloat = 16
    /// A key's height under a card, and on a band or a thumbnail.
    private static let keyHeight: CGFloat = 15
    private static let bandKeyHeight: CGFloat = 13
    /// Points between a title and its key.
    private static let keyGap: CGFloat = 4

    private var items: [SwitcherItem] = []
    private var frames: [CGRect] = []
    private var style = Style.row
    private var cards: [Card] = []
    private let glow = CALayer()
    private let ring = CALayer()
    private(set) var picked = 0
    /// The cards whose pick changed since they were last placed, and whether placing them is due.
    private var repicked: Set<Int> = []
    private var placing = false
    var animates = true
    /// The ring's colour; the glow is a faint wash of it.
    var highlight = Highlight.accent

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

    /// Lays out `items` in `frames` for a new showing, with `picked` picked and no animation. With `titles`, a card
    /// with no other card right below it has its title under it where there is `roomUnder` the cards, the others on a
    /// band along their foot; an item's letter goes with its title, or alone in its place.
    func show(_ items: [SwitcherItem], frames: [CGRect], style: Style, picked: Int, scale: CGFloat, titles: Bool,
              roomUnder: Bool) {
        self.items = items
        self.frames = frames
        self.style = style
        self.picked = picked
        repicked = []
        placing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards.forEach { $0.root.removeFromSuperlayer() }
        let radius = style.cardRadius * style.pickedScale + Self.ringOutset
        glow.cornerRadius = radius
        ring.cornerRadius = radius
        cards = zip(items, frames).map { item, frame in
            let caption: Card.Caption? = !titles && item.letter == nil ? nil
                : !roomUnder || frames.contains(where: { $0.minY > frame.maxY && $0.minY - frame.maxY < 12
                                           && $0.minX < frame.maxX - 1 && $0.maxX > frame.minX + 1 }) ? .band : .under
            let card = Card(frame: frame, icon: item.icon, radius: style.cardRadius, scale: scale, caption: caption,
                            titled: titles, letter: item.letter)
            card.title = item.title
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
        repicked.formUnion([picked, index])
        picked = index
        guard !placing else { return }
        placing = true
        // Placed once per pass of the run loop, however many moves picked meanwhile: a commit can wait a frame for
        // the window server, and two for every move fell behind the pointer.
        DispatchQueue.main.async { [weak self] in self?.placePicked() }
    }

    /// Springs the ring to the card picked last and recolours the cards whose pick changed, in one commit.
    private func placePicked() {
        guard placing else { return }
        placing = false
        CATransaction.begin()
        place(animated: animates)
        // Only those cards: recolouring text redraws it.
        applyColors(only: Array(repicked))
        CATransaction.commit()
        repicked = []
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

    /// A window's title, learnt after the capsule showed.
    func update(_ id: WindowID, title: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = title
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards[i].title = title
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

    /// Resolves the dynamic colours for the current appearance: every card's, or `only` those.
    private func applyColors(only: [Int]? = nil) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let highlight = highlight.nsColor
            glow.backgroundColor = highlight.fading(to: 0.22).cgColor
            ring.borderColor = highlight.cgColor
            for (i, card) in cards.enumerated() where only?.contains(i) ?? true {
                card.thumb.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                card.thumb.borderColor = NSColor.separatorColor.cgColor
                card.label?.foregroundColor = (card.caption == .band ? NSColor.white : NSColor.labelColor).cgColor
                card.keycap?.applyColors(picked: i == picked, highlight: highlight)
            }
            CATransaction.commit()
        }
    }

    /// One window's card: the thumbnail, clipped to its corners, and the app's icon, in the middle until there is a
    /// thumbnail and in the corner after; and its title and letter key, if it has a caption.
    private final class Card {
        /// Where the title and key go: under the card, or along its foot over the thumbnail, the title on a band.
        enum Caption { case under, band }

        let root = CALayer()
        let thumb = CALayer()
        let caption: Caption?
        private(set) var label: CATextLayer?
        private(set) var keycap: Keycap?
        private let band = CALayer()
        private let icon = CALayer()
        private let size: CGSize
        private static let line = ceil(SwitcherView.titleFont.ascender - SwitcherView.titleFont.descender)

        init(frame: CGRect, icon image: NSImage?, radius: CGFloat, scale: CGFloat, caption: Caption?, titled: Bool,
             letter: Character?) {
            self.caption = caption
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
            if let caption {
                if titled {
                    let label = CATextLayer()
                    label.font = SwitcherView.titleFont
                    label.fontSize = SwitcherView.titleFont.pointSize
                    label.contentsScale = scale
                    label.truncationMode = .middle
                    label.isWrapped = false
                    label.alignmentMode = caption == .under ? .center : .left
                    if caption == .band {
                        // On the thumbnail, clipped to its lower corners.
                        let height = min(SwitcherView.bandHeight, size.height / 2)
                        band.frame = CGRect(x: 0, y: size.height - height, width: size.width, height: height)
                        band.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
                        thumb.addSublayer(band)
                        band.addSublayer(label)
                    } else {
                        root.addSublayer(label)
                    }
                    self.label = label
                }
                if let letter {
                    let height = caption == .under ? SwitcherView.keyHeight : min(SwitcherView.bandKeyHeight, size.height / 2)
                    let keycap = Keycap(letter, height: height, scale: scale, onDark: caption == .band)
                    // Over the thumbnail, outside its clip, so a corner never cuts it.
                    keycap.root.zPosition = 1
                    root.addSublayer(keycap.root)
                    self.keycap = keycap
                }
            }
            placeCaption()
            placeIcon()
        }

        var title = "" {
            didSet {
                label?.string = title
                placeCaption()
            }
        }

        var image: CGImage? {
            get { thumb.contents.map { $0 as! CGImage } }
            set {
                thumb.contents = newValue
                placeIcon()
            }
        }

        /// Under the card, the title and the key centred together, the title cut short to leave the key room; on a
        /// band, the title from its left and the key at its right end, in from the corner; with no title, the key
        /// alone where it would be.
        private func placeCaption() {
            let key = keycap?.size ?? .zero
            let gap = label != nil && keycap != nil ? SwitcherView.keyGap : 0
            switch caption {
            case .under?:
                let room = size.width + 4
                let text = ceil((title as NSString).size(withAttributes: [.font: SwitcherView.titleFont]).width)
                let width = label == nil ? 0 : min(text, max(room - key.width - gap, 0))
                let x = ((size.width - width - gap - key.width) / 2).rounded()
                let y = size.height + SwitcherView.titleGap
                label?.frame = CGRect(x: x, y: y, width: width, height: Self.line)
                keycap?.root.frame = CGRect(x: x + width + gap, y: (y + (Self.line - key.height) / 2).rounded(),
                                            width: key.width, height: key.height)
            case .band?:
                let height = min(SwitcherView.bandHeight, size.height / 2)
                // Far enough in that the card's rounded corner clears the key.
                let inset: CGFloat = 5
                label?.frame = CGRect(x: 6, y: (height - Self.line) / 2,
                                      width: max(size.width - 6 - inset - key.width - gap, 0), height: Self.line)
                let y = label == nil ? size.height - key.height - 4 : size.height - height + ((height - key.height) / 2).rounded()
                keycap?.root.frame = CGRect(x: size.width - inset - key.width, y: y, width: key.width, height: key.height)
            case nil:
                break
            }
        }

        private func placeIcon() {
            if thumb.contents == nil {
                let side = min(SwitcherView.placeholderIconSize, size.width - 8, size.height - 8)
                icon.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            } else {
                let side = min(SwitcherView.badgeSize, size.height / 2)
                // Above a band, which would cover it.
                let lift = caption == .band && label != nil ? min(SwitcherView.bandHeight, size.height / 2) : 0
                icon.frame = CGRect(x: 4, y: max(size.height - side - 4 - lift, 0), width: side, height: side)
            }
        }
    }
}
