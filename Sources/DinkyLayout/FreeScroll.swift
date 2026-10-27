import CoreGraphics

// Fingers scrolling a strip freely, as SlideScroll's do (`[gestures.scroll]`): while they hold it, the strip goes where
// they take it, no further than its ends, the focused column not scrolled back to, and nothing else changes: focus,
// stacking and the columns stay as they were. Let go, it carries on by the fling's momentum, then the column showing
// nearest the middle of the screen takes focus, scrolled to as `columnCentring` has it, so the strip settles where
// focusing that column would leave it; at an end of the strip, the column there, which the middle cannot reach.
// Anything that scrolls to focus meanwhile, as a command or a window opening, ends the free scroll and scrolls as ever.
// Fullscreen ends it as it was. Columns hold their widths under the fingers: none reaches over to a wall meanwhile.

extension Workspace {
    /// Whether fingers can scroll the strip freely: a strip whose columns do not all fit, nothing fullscreen or waiting
    /// to be, and no drop holding its scroll (`keepsScroll`).
    public var canScrollFreely: Bool {
        guard isScrolling, fullscreenWindows.isEmpty, pendingFullscreen == nil, !keepsScroll else { return false }
        let area = stripArea
        return scrollLimits(for: columnSpans(in: area), in: area) != nil
    }

    /// Whether fingers are scrolling the strip freely, from `beginFreeScroll()` till it ends.
    public var isScrollingFreely: Bool { freeScrollFrom != nil }

    /// Fingers take hold of the strip where it shows, a click's hold on it let go. False, and nothing changed, where
    /// they cannot (`canScrollFreely`). Taking hold again while they hold it keeps where they first took it.
    @discardableResult
    public mutating func beginFreeScroll() -> Bool {
        guard canScrollFreely else { return false }
        let shown = shownOffset
        scrollOffset = shown
        holdsScroll = false
        if freeScrollFrom == nil { freeScrollFrom = shown }
        return true
    }

    /// Scrolls the strip the fingers hold by `delta` points, positive to show what is right of it, no further than its
    /// ends. How far it went, 0 at an end, or while nothing holds it.
    @discardableResult
    public mutating func scrollFreely(by delta: CGFloat) -> CGFloat {
        guard freeScrollFrom != nil else { return 0 }
        let area = stripArea
        guard let limits = heldLimits(for: columnSpans(in: area), in: area) else { return 0 }
        let from = min(max(scrollOffset, limits.lowerBound), limits.upperBound)
        scrollOffset = min(max(from + delta, limits.lowerBound), limits.upperBound)
        return scrollOffset - from
    }

    /// The fingers let go: the strip carries on by `momentum` points, no further than its ends, then the window of the
    /// column showing nearest the middle takes focus, scrolled to as focusing it does. Returns that window, or nil when
    /// nothing was held, nothing is there, or a window went fullscreen meanwhile, which puts the strip back as it was.
    @discardableResult
    public mutating func endFreeScroll(momentum: CGFloat = 0) -> WindowID? {
        guard freeScrollFrom != nil else { return nil }
        guard fullscreenWindows.isEmpty, pendingFullscreen == nil else {
            cancelFreeScroll()
            return nil
        }
        scrollFreely(by: momentum)
        let target = snappedWindow
        freeScrollFrom = nil
        if let target { focus(target) }
        return target
    }

    /// The fingers' hold ends with the strip back where it showed as they took it, focus as it is.
    public mutating func cancelFreeScroll() {
        guard let start = freeScrollFrom else { return }
        scrollOffset = start
        freeScrollFrom = nil
        // Lined up with the walls it has now: a display can have come beside it while held.
        alignToWalls()
    }

    /// While fingers hold the strip, whether it is at an end of where it can scroll, as near as a let-go takes for the
    /// column there.
    public var heldAtEnd: Bool {
        guard isScrollingFreely else { return false }
        let area = stripArea
        guard let limits = heldLimits(for: columnSpans(in: area), in: area) else { return true }
        let offset = shownOffset
        return offset <= limits.lowerBound + 0.5 || offset >= limits.upperBound - 0.5
    }

    /// While fingers hold the strip, the window a let-go now, with no momentum, would settle on: what the trackpad
    /// ticks for as it changes. Nil while nothing holds it.
    public var heldTarget: WindowID? { isScrollingFreely ? snappedWindow : nil }

    /// The window to focus as the fingers let go: of the column whose middle shows nearest the middle of the strip's
    /// area, the focused one on a tie, or at an end of the strip, the column there, which the middle cannot reach once
    /// it shows whole; of a column of several, the one most recently focused. Beside a wall the strip rests lined up
    /// with it (`wallAligned`), the focused column off the middle, as far from it as its neighbour on the wall side:
    /// there the middle is where the focused column's showed as they took hold, so it keeps half a column's way either
    /// side.
    var snappedWindow: WindowID? {
        let band = bandRange
        guard isScrolling, let first = band.first, let last = band.last else { return nil }
        let area = stripArea, spans = columnSpans(in: area)
        let offset = offset(for: spans, in: area, showingFocus: false)
        let focusedColumn = focused.flatMap { bandIndex(of: $0) }
        let walled = walls.contains(.right) && pinnedIndex(.right) == nil
            || walls.contains(.left) && pinnedIndex(.left) == nil
        let middle: CGFloat
        if walled, let start = freeScrollFrom, let f = focusedColumn {
            middle = spans[f].start + spans[f].width / 2 - start
        } else {
            middle = area.width / 2
        }
        let away = { (i: Int) in abs(spans[i].start + spans[i].width / 2 - offset - middle) }
        var index = focusedColumn ?? first
        for i in band where away(i) < away(index) { index = i }
        if let limits = heldLimits(for: spans, in: area) {
            let stays = { (i: Int) in
                min(max(showing(spans[i], from: offset, in: area), limits.lowerBound), limits.upperBound) == offset
            }
            if offset <= limits.lowerBound + 0.5, stays(first) {
                index = first
            } else if offset >= limits.upperBound - 0.5, stays(last) {
                index = last
            }
        }
        switch root.children[index] {
        case .window(let id): return id
        case .container(let c): return c.mostRecentWindow
        }
    }
}
