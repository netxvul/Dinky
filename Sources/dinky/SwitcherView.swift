import AppKit
import CoreImage
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
// in its place. The picked card's key takes the highlight colour. A line of the separator colour parts a row's tiled
// windows from the floating ones after them. A card being dragged lifts off the row, small and see-through so it hides
// little of what it is dragged over, and follows the pointer, the ring and glow put away, and a mark over it shows where
// it would go: a line in a gap, or what of a card it would take, in `[drag]`'s preview colours, that part of the card
// frosted below the dragged one from its picture, blurred once a drag. Layers, in the frames the caller
// gives. Main thread only.
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
    /// The lines between a row's tiled windows and its floating ones.
    private var dividers: [CALayer] = []
    private let glow = CALayer()
    private let ring = CALayer()
    /// Where a dragged card would go: a line in a gap, or what of a card it would take.
    private let marker = CALayer()
    /// That card's picture blurred, under the dragged card, and what shows of it.
    private let frost = CALayer()
    private let frostPart = CALayer()
    private var frostCard: Int?
    /// The cards' pictures blurred this drag, by card.
    private var frosted: [Int: CGImage] = [:]
    /// How `[drag]` has a mark look.
    struct DropLook {
        var border = Highlight.accent
        var fill: Color?
        var width: CGFloat = 3
        var blur = true
    }
    var dropLook = DropLook()
    /// Where a dragged card would go, in the capsule's coordinates: a line in a gap (`markerLine`), or a part of card
    /// `index`, all of it for a swap.
    enum DropMark {
        case line(CGRect)
        case card(index: Int, part: CGRect, swap: Bool)
    }
    /// The line of a well opened for a drag with no floating window to show one (`openWell`).
    private let wellLine = CALayer()
    /// The card being dragged, and where on it the pointer took it, from its middle.
    private var dragged: (index: Int, grab: CGPoint)?
    private static let markerWidth: CGFloat = 3
    /// The thickest border a mark on a card has, whatever a whole window's preview has.
    private static let markBorder: CGFloat = 3
    /// Of a picture's height, how far its frost blurs.
    private static let frostRadius: CGFloat = 0.06
    private static let frostContext = CIContext()
    /// What a dragged card fits in, its longest side at most that, and how much of it shows.
    private static let liftBox = CGSize(width: 64, height: 64)
    private static let liftOpacity: Float = 0.7
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
        marker.cornerRadius = Self.markerWidth / 2
        // Over a dragged card too, its frost under it.
        marker.zPosition = 6
        frost.zPosition = 4
        frost.isHidden = true
        frost.contentsGravity = .resizeAspectFill
        frost.masksToBounds = true
        frostPart.backgroundColor = NSColor.black.cgColor
        frost.mask = frostPart
        layer?.addSublayer(frost)
        marker.isHidden = true
        layer?.addSublayer(marker)
        wellLine.isHidden = true
        layer?.addSublayer(wellLine)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Lays out `items` in `frames` for a new showing, with `picked` picked and no animation. With `titles`, a card
    /// with no other card right below it has its title under it where there is `roomUnder` the cards, the others on a
    /// band along their foot; an item's letter goes with its title, or alone in its place. A line goes in each of
    /// `dividers`. A window in `slidingFrom` slides from that frame to its own, as after its column moved.
    func show(_ items: [SwitcherItem], frames: [CGRect], style: Style, picked: Int, scale: CGFloat, titles: Bool,
              roomUnder: Bool, dividers: [CGRect] = [], slidingFrom: [WindowID: CGRect] = [:]) {
        self.items = items
        self.frames = frames
        self.style = style
        self.picked = picked
        repicked = []
        placing = false
        dragged = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hideMark()
        frosted = [:]
        wellLine.isHidden = true
        glow.opacity = 1
        ring.opacity = 1
        cards.forEach { $0.root.removeFromSuperlayer() }
        self.dividers.forEach { $0.removeFromSuperlayer() }
        self.dividers = dividers.map { frame in
            let line = CALayer()
            line.frame = frame
            layer?.addSublayer(line)
            return line
        }
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
        guard animates else { return }
        for (item, card) in zip(items, cards) {
            guard let from = slidingFrom[item.id] else { continue }
            Self.spring(card.root, "position", from: CGPoint(x: from.midX, y: from.midY), to: card.root.position)
        }
    }

    /// Every card's frame as it shows now, by its window: a dragged one where the pointer has it.
    func shownFrames() -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        for (item, card) in zip(items, cards) {
            let layer = card.root.presentation() ?? card.root
            let size = card.root.bounds.size
            frames[item.id] = CGRect(x: layer.position.x - size.width / 2, y: layer.position.y - size.height / 2,
                                     width: size.width, height: size.height)
        }
        return frames
    }

    /// Lifts card `index` off the row to follow the pointer, taken at `point`, picked; the ring and glow go.
    func beginDrag(_ index: Int, at point: CGPoint) {
        guard cards.indices.contains(index) else { return }
        if index != picked {
            repicked.formUnion([picked, index])
            picked = index
            applyColors(only: Array(repicked))
            repicked = []
        }
        // The pointer keeps its place on the card as it shrinks.
        let scale = SwitcherReorder.dragScale(of: frames[index].size, in: Self.liftBox)
        dragged = (index, CGPoint(x: (point.x - frames[index].midX) * scale, y: (point.y - frames[index].midY) * scale))
        frosted = [:]
        CATransaction.begin()
        CATransaction.setDisableActions(!animates)
        CATransaction.setAnimationDuration(0.15)
        for (i, card) in cards.enumerated() {
            card.root.opacity = i == index ? Self.liftOpacity : Self.dimmed
            card.root.transform = i == index ? CATransform3DMakeScale(scale, scale, 1) : CATransform3DIdentity
            card.root.zPosition = i == index ? 5 : 0
        }
        let lifted = cards[index].root
        lifted.shadowColor = NSColor.black.cgColor
        lifted.shadowOpacity = 0.35
        lifted.shadowRadius = 10
        lifted.shadowOffset = CGSize(width: 0, height: 6)
        glow.opacity = 0
        ring.opacity = 0
        CATransaction.commit()
    }

    /// A line of the separator colour at `frame` while a well is open, or none.
    func showWellLine(_ frame: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wellLine.isHidden = frame == nil
        if let frame {
            wellLine.frame = frame
            wellLine.backgroundColor = NSColor.separatorColor.cgColor
        }
        CATransaction.commit()
    }

    /// The marker for a gap: a line at `x` across, `span` up and down.
    static func markerLine(x: CGFloat, span: ClosedRange<CGFloat>) -> CGRect {
        CGRect(x: (x - markerWidth / 2).rounded(), y: span.lowerBound, width: markerWidth, height: span.upperBound - span.lowerBound)
    }

    /// The dragged card follows the pointer to `point`, and the mark goes to `mark`; none where nil, as over the place it
    /// came from.
    func drag(to point: CGPoint, mark: DropMark?) {
        guard let dragged else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards[dragged.index].root.position = CGPoint(x: point.x - dragged.grab.x, y: point.y - dragged.grab.y)
        CATransaction.commit()
        guard let mark else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hideMark()
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        // Straight there when it shows, sliding from place to place after.
        CATransaction.setDisableActions(marker.isHidden || !animates)
        CATransaction.setAnimationDuration(0.12)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let border = dropLook.border.nsColor
            switch mark {
            case .line(let frame):
                marker.frame = frame
                marker.backgroundColor = border.cgColor
                marker.borderWidth = 0
                marker.cornerRadius = Self.markerWidth / 2
            case .card(_, let part, let swap):
                let fill = dropLook.fill?.nsColor ?? border.fading(to: 0.3)
                marker.frame = part
                marker.backgroundColor = (swap ? fill.swapFill : fill).cgColor
                marker.borderColor = border.cgColor
                marker.borderWidth = min(dropLook.width, Self.markBorder)
                marker.cornerRadius = style.cardRadius
            }
        }
        marker.isHidden = false
        CATransaction.commit()
        placeFrost(mark)
    }

    /// The frost of what `mark` takes of a card, if it is on one with a picture, and frost is wanted.
    private func placeFrost(_ mark: DropMark) {
        guard case .card(let index, let part, _) = mark, dropLook.blur, let image = frostImage(of: index) else {
            frostCard = nil
            frost.isHidden = true
            return
        }
        let frame = frames[index]
        CATransaction.begin()
        // Moved within a card it slides with the mark; to another, straight there.
        CATransaction.setDisableActions(true)
        if frostCard != index {
            frost.contents = image
            frost.frame = frame
            frost.cornerRadius = style.cardRadius
            frostPart.frame = part.offsetBy(dx: -frame.minX, dy: -frame.minY)
            frostPart.cornerRadius = style.cardRadius
        }
        frost.isHidden = false
        CATransaction.commit()
        guard frostCard == index else { return frostCard = index }
        CATransaction.begin()
        CATransaction.setDisableActions(!animates)
        CATransaction.setAnimationDuration(0.12)
        frostPart.frame = part.offsetBy(dx: -frame.minX, dy: -frame.minY)
        CATransaction.commit()
    }

    /// Card `index`'s picture blurred, once a drag. Nil with no picture yet, or if it will not blur.
    private func frostImage(of index: Int) -> CGImage? {
        if let image = frosted[index] { return image }
        guard cards.indices.contains(index), let image = cards[index].image else { return nil }
        let picture = CIImage(cgImage: image)
        let radius = CGFloat(image.height) * Self.frostRadius
        guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: picture.clampedToExtent(), kCIInputRadiusKey: radius,
        ])?.outputImage, let out = Self.frostContext.createCGImage(blurred, from: picture.extent) else { return nil }
        frosted[index] = out
        return out
    }

    private func hideMark() {
        marker.isHidden = true
        frost.isHidden = true
        frost.contents = nil
        frostCard = nil
    }

    /// The dragged card goes back to its place in the row, the ring and glow with it.
    func endDrag() {
        guard let dragged else { return }
        self.dragged = nil
        let card = cards[dragged.index].root
        let to = CGPoint(x: frames[dragged.index].midX, y: frames[dragged.index].midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hideMark()
        frosted = [:]
        let from = card.position
        card.position = to
        card.shadowOpacity = 0
        glow.opacity = 1
        ring.opacity = 1
        CATransaction.commit()
        if animates { Self.spring(card, "position", from: from, to: to) }
        CATransaction.begin()
        place(animated: animates)
        CATransaction.commit()
    }

    /// Springs `layer`'s point `key` from `from` to `to`, where it is set already.
    private static func spring(_ layer: CALayer, _ key: String, from: CGPoint, to: CGPoint) {
        guard from != to else { return }
        let spring = CASpringAnimation(keyPath: key)
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 26
        spring.fromValue = NSValue(point: from)
        spring.toValue = NSValue(point: to)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: key)
    }

    /// Picks another card, springing the ring over to it. Not while a card is dragged, which is the one picked.
    func pick(_ index: Int) {
        guard dragged == nil, index != picked, cards.indices.contains(index) else { return }
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
            for line in dividers where only == nil { line.backgroundColor = NSColor.separatorColor.cgColor }
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
