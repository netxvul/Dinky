import CoreGraphics

/// The workspace switcher's capsule, in its own coordinates with a top-left origin: a row of cards, one per
/// workspace, grouped by display, each as tall as `cardHeight` and as wide as its display's proportions give, its
/// label under it. With more than one group each has its display's name over it and a line between them. The
/// padding is the window switcher's, growing with the corner radius, and a row too wide for `maxWidth` has its cards
/// scaled down whole.
public struct WorkspaceSwitcherLayout: Equatable {
    public static let cardGap: CGFloat = 12
    /// Between groups, a line down the middle.
    public static let groupGap: CGFloat = 29
    /// Room under a card for its label.
    public static let labelHeight: CGFloat = 20
    /// Room over a group for its display's name.
    public static let headerHeight: CGFloat = 18

    public let size: CGSize
    /// Each card, groups in order.
    public let frames: [CGRect]
    /// Each card's label, under it.
    public let labels: [CGRect]
    /// Each group's name, over its first card; empty with one group.
    public let headers: [CGRect]
    /// Where the lines between groups go across.
    public let dividers: [CGFloat]
    /// The height the cards came out at.
    public let cardHeight: CGFloat

    /// `groups` holds each display's cards' width-to-height ratios, left to right.
    public init(groups: [[CGFloat]], cardHeight: CGFloat, cornerRadius: CGFloat = 0, maxWidth: CGFloat) {
        let padding = SwitcherMap.padding(cornerRadius: cornerRadius)
        let groups = groups.filter { !$0.isEmpty }
        let titled = groups.count > 1
        let gaps = CGFloat(max(groups.count - 1, 0)) * Self.groupGap
            + groups.reduce(0) { $0 + CGFloat(max($1.count - 1, 0)) } * Self.cardGap
        let natural = groups.joined().reduce(0) { $0 + cardHeight * $1 }
        let room = maxWidth - padding * 2 - gaps
        let scale = natural > room && natural > 0 ? max(room, 0) / natural : 1
        let height = (cardHeight * scale).rounded(.down)
        let top = padding + (titled ? Self.headerHeight : 0)
        var frames: [CGRect] = [], labels: [CGRect] = [], headers: [CGRect] = [], dividers: [CGFloat] = []
        var x = padding
        for (g, group) in groups.enumerated() {
            if g > 0 {
                dividers.append((x + Self.groupGap / 2).rounded())
                x += Self.groupGap
            }
            let start = x
            for (c, aspect) in group.enumerated() {
                if c > 0 { x += Self.cardGap }
                let width = max((height * aspect).rounded(.down), 1)
                frames.append(CGRect(x: x, y: top, width: width, height: height))
                labels.append(CGRect(x: x - Self.cardGap / 2, y: top + height, width: width + Self.cardGap, height: Self.labelHeight))
                x += width
            }
            if titled { headers.append(CGRect(x: start, y: padding, width: x - start, height: Self.headerHeight)) }
        }
        let tall = top + height + Self.labelHeight + padding
        size = CGSize(width: max(x + padding, tall), height: tall)
        self.frames = frames
        self.labels = labels
        self.headers = headers
        self.dividers = dividers
        self.cardHeight = height
    }

    /// The card at `x` across the capsule: the one whose span, extended halfway into the gaps beside it, holds `x`,
    /// the first or last beyond the ends. Nil with no cards.
    public func index(atX x: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        for i in frames.indices.dropLast() where x < (frames[i].maxX + frames[i + 1].minX) / 2 { return i }
        return frames.count - 1
    }

    /// Where the capsule goes in global coordinates (top-left origin): card `anchor` centred on `pointer`, kept
    /// `SwitcherLayout.screenMargin` inside `visible`.
    public func origin(anchor: Int, pointer: CGPoint, visible: CGRect) -> CGPoint {
        let centre = frames.indices.contains(anchor) ? CGPoint(x: frames[anchor].midX, y: frames[anchor].midY)
                                                     : CGPoint(x: size.width / 2, y: size.height / 2)
        let margin = SwitcherLayout.screenMargin
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(v, low), max(high, low)) }
        let x = clamp(pointer.x - centre.x, visible.minX + margin, visible.maxX - margin - size.width)
        let y = clamp(pointer.y - centre.y, visible.minY + margin, visible.maxY - margin - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
