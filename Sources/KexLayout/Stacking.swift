import CoreGraphics

extension Layout {
    /// Windows to raise, back to front, so overlapping windows (accordion, fullscreen) stack as `order` says
    /// wherever that shows. `current` is the on-screen order, front to back. Empty when it already agrees;
    /// plain tiles never overlap.
    ///
    /// Each raise briefly puts that window on top, and makes it its app's key window, before the ones meant to
    /// be in front of it are raised again: a visible flash. So raising is kept to the fewest windows from the
    /// front, only the order of two windows whose overlap shows somewhere counts (where windows above both
    /// cover it, either may be on top), and once the front window is on top nothing is raised just to fix
    /// which background window peeks out at an edge. A focus change puts the new front window on top, so
    /// switching windows in an accordion normally raises nothing.
    ///
    /// With a `screen`, only what shows on it counts, and each group of windows overlapping there is put in order on
    /// its own: a strip's parked windows pile up off the edge, and each edge's pile is put in order whatever the
    /// other edge's is. A pile at an edge is put in order even with its front window on top, since a window of its
    /// front column other than that one can have a tucked one over it; nothing there covers content in view.
    public func raises(current: [WindowID]) -> [WindowID] {
        guard let screen else { return Self.raises(order.filter { frames[$0] != nil }, frames: frames, current: current) }
        var shown: [WindowID: CGRect] = [:]
        for (id, frame) in frames {
            let rect = (narrower[id] ?? frame).intersection(screen)
            if !rect.isEmpty { shown[id] = rect }
        }
        var groups: [[WindowID]] = []
        for id in order where shown[id] != nil {
            let touching = groups.indices.filter { i in groups[i].contains { !shown[$0]!.intersection(shown[id]!).isEmpty } }
            groups = groups.enumerated().filter { !touching.contains($0.offset) }.map(\.element)
                + [touching.flatMap { groups[$0] } + [id]]
        }
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return groups.flatMap { group in
            let inView = group.contains { screen.insetBy(dx: -1, dy: -1).contains(frames[$0]!) }
            return Self.raises(group.sorted { position[$0]! < position[$1]! }, frames: shown, current: current,
                               trustingFront: inView)
        }
    }

    /// `raises(current:)` for the windows `candidates`, in stacking order, as `frames` puts them. With
    /// `trustingFront`, nothing is raised once the front window is on top.
    private static func raises(_ candidates: [WindowID], frames: [WindowID: CGRect], current: [WindowID],
                               trustingFront: Bool = true) -> [WindowID] {
        let stack = candidates.filter { id in
            candidates.contains { other in other != id && !frames[other]!.intersection(frames[id]!).isEmpty }
        }
        if trustingFront, let front = stack.first, current.first(where: stack.contains) == front { return [] }
        let position = Dictionary(current.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        // Raising the first `n` of the stack, back to front, puts them on top in order; the rest keep their
        // current order, which must already be right. With n = stack.count there is no rest, so one n fits.
        let n = (0...stack.count).first { n in
            let rest = n..<stack.count
            return rest.allSatisfy { i in
                rest.allSatisfy { j in
                    guard i < j, showsOrder(stack, i, j, frames) else { return true }
                    guard let above = position[stack[i]], let below = position[stack[j]] else { return false }
                    return above < below
                }
            }
        }!
        return Array(stack.prefix(n).reversed())
    }

    /// Whether it shows which of `stack[i]` and `stack[j]` (i < j) is on top: part of their overlap is not
    /// covered by the windows meant to be above both.
    private static func showsOrder(_ stack: [WindowID], _ i: Int, _ j: Int, _ frames: [WindowID: CGRect]) -> Bool {
        let shared = frames[stack[i]]!.intersection(frames[stack[j]]!)
        guard !shared.isEmpty else { return false }
        let above = stack[..<i].map { frames[$0]! }
        return !above.reduce([shared]) { rest, cover in rest.flatMap { $0.subtracting(cover) } }.isEmpty
    }
}

extension CGRect {
    /// The parts of this rect outside `other`, as up to four rects.
    func subtracting(_ other: CGRect) -> [CGRect] {
        let cut = intersection(other)
        guard !cut.isEmpty else { return [self] }
        var parts: [CGRect] = []
        if cut.minY > minY { parts.append(CGRect(x: minX, y: minY, width: width, height: cut.minY - minY)) }
        if cut.maxY < maxY { parts.append(CGRect(x: minX, y: cut.maxY, width: width, height: maxY - cut.maxY)) }
        if cut.minX > minX { parts.append(CGRect(x: minX, y: cut.minY, width: cut.minX - minX, height: cut.height)) }
        if cut.maxX < maxX { parts.append(CGRect(x: cut.maxX, y: cut.minY, width: maxX - cut.maxX, height: cut.height)) }
        return parts
    }
}
