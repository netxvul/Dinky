import CoreGraphics

// A window that both moves and changes size in a glide cannot be animated as one frame: its app takes the size and
// the position as two writes and shows each as it lands, a size tens of milliseconds after a move in a slow app (an
// Electron or Chromium one), and AppKit stops a size from taking a window wholly on screen past the screen's right
// edge. Stepped together, the window shows half done on every step (moved but not resized, its old place empty) or
// falls behind neighbours that only move. So such a window changes size once, where the change cannot be seen, and
// glides by moving only: growing, it takes its whole size first, where it is, the growth past the screen edge or over
// the windows below it; shrinking, it glides at the size it has and takes its new one once there.
public enum ResizeOnce {
    /// How far right a window growing past the screen edge is moved first, so its app takes the whole size: AppKit
    /// stops a size at the edge for a window whose right edge is on screen, and lets one already past it be any size.
    /// Inside the inner gap, where the move shows nothing.
    public static let nudge: CGFloat = 2

    /// How many times as long a window moving away from the columns beside it takes as they do, so it trails them.
    public static let trailing = 1.5

    /// How many times as long a window growing to the left takes, and the columns it pushes with it: its app shows each
    /// step's size a frame or so before its move, its right side out by the step meanwhile, so the steps are kept short.
    public static let drawn = 1.5

    /// Whether going from `current` to `target` changes the window's size and also moves it.
    public static func movesAndResizes(_ current: CGRect, _ target: CGRect) -> Bool {
        resizes(current, target) && (abs(current.minX - target.minX) > 1 || abs(current.minY - target.minY) > 1)
    }

    /// Whether going from `current` to `target` changes the window's size.
    public static func resizes(_ current: CGRect, _ target: CGRect) -> Bool {
        abs(current.width - target.width) > 1 || abs(current.height - target.height) > 1
    }

    /// Whether the window grows: larger one way, smaller in neither.
    public static func grows(_ current: CGRect, _ target: CGRect) -> Bool {
        target.width >= current.width - 1 && target.height >= current.height - 1 && resizes(current, target)
    }

    /// Where a window growing from `current` to `target` takes its new size before it glides there: where it is, at
    /// `target`'s size, moved right by `nudge` when the size would take it past `edge` (the display's right edge) from
    /// on screen, which its app would otherwise stop at the edge. Written as size, position, size, the first size
    /// stops at the edge, the move takes the window past it, and the second size goes through: at each step the window
    /// covers all it covered before but the nudge.
    public static func staging(from current: CGRect, to target: CGRect, edge: CGFloat) -> CGRect {
        let clamped = current.maxX <= edge + 0.5 && current.minX + target.width > edge + 0.5
        return CGRect(x: clamped ? current.minX + nudge : current.minX, y: current.minY, width: target.width,
                      height: target.height)
    }

    /// Whether a window going from `current` to `target` can change size once. Not one that moves up or down: AppKit
    /// stops a size at the bottom of the screen, or at the Dock, as it does at the right, and no small move gets past
    /// that. Nor one whose frames on the way would show where they must not: past the right edge, `edge`, onto another
    /// display beyond it (`wall`), or, staged there growing, into a Dock at that edge (`dock`), which stops a size too.
    public static func applies(from current: CGRect, to target: CGRect, edge: CGFloat, wall: Bool, dock: Bool) -> Bool {
        guard abs(current.minY - target.minY) <= 1, resizes(current, target) else { return false }
        if grows(current, target) {
            return staging(from: current, to: target, edge: edge).maxX <= edge + 0.5 || (!wall && !dock)
        }
        return !wall || target.minX + current.width <= edge + 0.5
    }

    /// Whether a window staged at `staging` shows there now, at `now`: at its position, and at its size or within
    /// `allowance` of it, as an app that snaps its size to a grid lands.
    public static func shows(_ now: CGRect, staging: CGRect, allowance: CGFloat = 16) -> Bool {
        abs(now.minX - staging.minX) <= 2 && abs(now.minY - staging.minY) <= 2
            && abs(now.width - staging.width) <= allowance && abs(now.height - staging.height) <= allowance
    }

    /// Where a window that changes size once glides to: `target`'s position, at the size it has, `size`.
    public static func glideTarget(_ target: CGRect, size: CGSize) -> CGRect {
        CGRect(origin: target.origin, size: size)
    }

    // A window growing to the left, as the right of two columns going fullscreen does, would take its whole size where
    // it is if it changed size once: its right edge out past the screen, its content laid out at the new width from the
    // old left edge, then the whole of it sliding left, so it seems to spring out to the right first. Instead it grows
    // as a window dragged by its left edge does: its right edge just past the screen's, its left edge gliding left. A
    // size grows a window from its left edge, which AppKit stops at the screen edge while the window is on screen, so
    // the right edge is first taken past it (`leadIn`), and on every step after, size first, then position, the size
    // goes through. Between the two an app shows the window wider where it was for a frame or so, its right side a
    // step further out past the screen edge, so the steps are kept short (`drawn`).

    /// How a window growing to the left glides to `target`: held past the screen's right edge, `edge`, on the way (see
    /// `anchored(_:to:edge:)`), and led past it first (see `leadIn(from:edge:)`).
    public struct Anchor: Equatable, Sendable {
        public var target: CGRect
        public var edge: CGFloat

        public init(target: CGRect, edge: CGFloat) {
            self.target = target
            self.edge = edge
        }

        /// Where the window is written when its glide has it at `frame`.
        public func frame(_ frame: CGRect) -> CGRect { ResizeOnce.anchored(frame, to: target, edge: edge) }
    }

    /// How much wider than asked a window growing to the left is written past the screen edge once its lead-in came out
    /// short of it, as one whose app snaps its size to a grid can: a grid cell, so each size still leaves it past the edge.
    public static let snapSlack: CGFloat = 16

    /// Whether a window going from `current` to `target` grows mostly to the left: its left edge goes further left than
    /// its right edge goes right.
    public static func growsLeft(_ current: CGRect, _ target: CGRect) -> Bool {
        grows(current, target) && current.minX - target.minX > max(1, target.maxX - current.maxX)
    }

    /// Whether a window going from `current` to `target` narrows mostly from the left: its left edge goes further right
    /// than its right edge goes left.
    public static func shrinksRight(_ current: CGRect, _ target: CGRect) -> Bool {
        target.width < current.width - 1 && target.minX - current.minX > max(1, current.maxX - target.maxX)
    }

    /// What a window growing to the left from `current` is written first, before it glides: its right edge taken just
    /// past the screen's, `edge`, by `nudge`, so its app lets every size after grow it there. Written as size, position,
    /// size, the size takes it to the screen edge and the move past it, by no more than the inner gap. Nil for one already
    /// past the edge.
    public static func leadIn(from current: CGRect, edge: CGFloat) -> CGRect? {
        guard current.maxX < edge + 1 else { return nil }
        return CGRect(x: current.minX + nudge, y: current.minY, width: edge - current.minX, height: current.height)
    }

    /// Where a window growing to the left to `target` is written on its way, with its left edge where the glide has it,
    /// at `frame`'s: its right edge held past the screen's, `edge`, as `leadIn` takes it, or further where the glide
    /// already has it further. Once its left edge is within a couple of points of the target's, which a spring that
    /// overshoots does not cross back, it is where the glide has it.
    public static func anchored(_ frame: CGRect, to target: CGRect, edge: CGFloat) -> CGRect {
        guard frame.minX > target.minX + 2 else { return frame }
        let right = max(edge + nudge, frame.maxX)
        return CGRect(x: frame.minX, y: frame.minY, width: right - frame.minX, height: frame.height)
    }

    /// Strip frames part way through a glide, held so that no gap wider than `gap` opens between `lead`, a window
    /// changing size once, and the columns beside it, whichever falls behind: an app can take a frame or two longer
    /// over a move now and then, just after a resize most of all. On each side, the one moving away from the other stays
    /// at the other's edge as the window server shows it (`shown`): the columns beside `lead`, which move together so the
    /// parked ones go along, no further out than `lead` shows; `lead` no further from them than they show. Only ever
    /// pulls a window towards its neighbour, so the two never hold each other up. `left` and `right` are the columns
    /// either side, nearest first; `lead` in view, where strip and screen coordinates agree. An `anchored` lead, one
    /// resizing at an edge as it glides (see `anchored(_:to:edge:)`), is held by that edge alone, its other edge kept.
    public static func guarded(_ frames: [WindowID: CGRect], lead: WindowID, left: [[WindowID]], right: [[WindowID]],
                               gap: CGFloat, anchored: Bool = false, shown: (WindowID) -> CGRect?) -> [WindowID: CGRect] {
        guard var leadFrame = frames[lead] else { return frames }
        var out = frames
        // The lead is read only for a side that is there, at the head of the first: a read is a call to the window
        // server.
        var leadRead: CGRect??
        func leadShownFrame() -> CGRect? {
            if leadRead == nil { leadRead = .some(shown(lead)) }
            return leadRead!
        }
        func shift(_ columns: [[WindowID]], by dx: CGFloat) {
            for id in columns.joined() { if let frame = out[id] { out[id] = frame.offsetBy(dx: dx, dy: 0) } }
        }
        if let near = left.first, let nearMaxX = near.compactMap({ out[$0]?.maxX }).max() {
            if let leadShown = leadShownFrame() { shift(left, by: max(0, leadShown.minX - gap - nearMaxX)) }
            if let nearShown = near.compactMap({ shown($0)?.maxX }).max() {
                let minX = min(leadFrame.minX, nearShown + gap)
                if anchored { leadFrame.size.width = leadFrame.maxX - minX }
                leadFrame.origin.x = minX
            }
        }
        if let near = right.first, let nearMinX = near.compactMap({ out[$0]?.minX }).min() {
            if let leadShown = leadShownFrame() { shift(right, by: min(0, leadShown.maxX + gap - nearMinX)) }
            if let nearShown = near.compactMap({ shown($0)?.minX }).min() {
                let maxX = max(leadFrame.maxX, nearShown - gap)
                if anchored { leadFrame.size.width = maxX - leadFrame.minX } else { leadFrame.origin.x = maxX - leadFrame.width }
            }
        }
        out[lead] = leadFrame
        return out
    }
}
