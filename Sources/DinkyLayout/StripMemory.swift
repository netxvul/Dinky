import CoreGraphics

// What a scrolling strip held, kept across a restart of dinky, which finds the same windows open but none of its trees.
// Each window goes back as it arrives, whenever that is: on the first pass, after its app was slow to answer, or as its
// Space first shows. It goes beside what is there of its neighbours, so anything the user did to the strip meanwhile
// stays. Only the band: pins come back by rule.

/// A strip as it was: its columns in order, their widths, and where it was scrolled to.
public struct StripMemory: Codable, Equatable, Sendable {
    public struct Column: Codable, Equatable, Sendable {
        public var windows: [WindowID]
        public var width: Double
        /// How a column of several windows stacks them; nil for a lone window.
        public var orientation: ContainerOrientation?
        public var mode: LayoutMode?
    }

    public var columns: [Column]
    /// The widths of columns away from the strip, minimized or hidden, for when they come back.
    public var departedWidths: [WindowID: Double]
    public var focused: WindowID?
    public var scrollOffset: CGFloat

    /// Every window it remembers, by its place in the strip, those away last.
    public var windows: [WindowID] {
        columns.flatMap(\.windows) + departedWidths.keys.sorted()
    }

    /// The strip with only `ids` left in it.
    public func keeping(_ ids: Set<WindowID>) -> StripMemory {
        var kept = self
        kept.columns = columns.compactMap { column in
            var column = column
            column.windows.removeAll { !ids.contains($0) }
            return column.windows.isEmpty ? nil : column
        }
        kept.departedWidths = departedWidths.filter { ids.contains($0.key) }
        if let focused, !ids.contains(focused) { kept.focused = nil }
        return kept
    }
}

extension Workspace {
    /// The strip as it is now; nil outside the scrolling layout.
    public var stripMemory: StripMemory? {
        guard isScrolling else { return nil }
        let columns = root.children.indices.map { index -> StripMemory.Column in
            var stack: Container?
            if case .container(let container) = root.children[index] { stack = container }
            return .init(windows: root.children[index].windows, width: width(ofColumn: index),
                         orientation: stack?.orientation, mode: stack?.mode)
        }
        return StripMemory(columns: columns, departedWidths: departedColumnWidths, focused: focused, scrollOffset: shownOffset)
    }

    /// `arrive` for a window `memory` remembers: back in its column if another of that column's windows is here, else
    /// in a column of its own at its width, after the nearest column before it that is here, or before the nearest after
    /// it. With none of them here it comes as any new window. Focus goes to the window that had it, and stays where it
    /// is for any other, with the strip scrolled as it was once the window that had focus is back.
    public mutating func arrive(_ id: WindowID, remembering memory: StripMemory) {
        guard isScrolling, !contains(id) else { return arrive(id) }
        if let width = memory.departedWidths[id] { departedColumnWidths[id] = width }
        guard let place = memory.columns.firstIndex(where: { $0.windows.contains(id) }) else { return arrive(id) }
        let saved = memory.columns[place]
        let before = focused
        if let column = saved.windows.compactMap({ bandIndex(of: $0) }).first {
            stack(id, into: column, like: saved)
        } else if let index = memory.slot(ofColumn: place, in: self) {
            root.insert(.window(id), at: index)
        } else {
            insert(id)
        }
        columnWidths[id] = saved.width
        if memory.focused == id {
            focus(id)
        } else if let before, focused != before {
            focus(before)
        } else if focused == nil {
            focus(id)
        }
        if focused == memory.focused { scrollOffset = memory.scrollOffset }
    }

    /// Focus back on `id` after a window came in that no one is looking at, with a strip scrolled so `id` stands at `x`
    /// as it did, whatever came in before it.
    public mutating func refocus(_ id: WindowID, standingAt x: CGFloat) {
        focus(id)
        guard isScrolling, let frame = layout().frames[id] else { return }
        scrollOffset += frame.minX - x
    }

    /// Puts `id` into the column, in the order `saved` has its windows.
    private mutating func stack(_ id: WindowID, into column: Int, like saved: StripMemory.Column) {
        let rank = { saved.windows.firstIndex(of: $0) ?? .max }
        switch root.children[column] {
        case .window(let other):
            let windows = rank(id) < rank(other) ? [id, other] : [other, id]
            root.replace(at: column, with: .container(Container(saved.orientation ?? .vertical, saved.mode ?? .tiles,
                                                                windows.map(Node.window))))
        case .container:
            root.modify(at: [column]) { container in
                let index = container.children.firstIndex { $0.windows.first.map(rank).map { $0 > rank(id) } == true }
                container.insert(.window(id), at: index ?? container.children.count)
            }
        }
    }
}

private extension StripMemory {
    /// Where in `workspace`'s root the remembered column `place` goes back, by the nearest of its neighbours in the band.
    func slot(ofColumn place: Int, in workspace: Workspace) -> Int? {
        let column = { (index: Int) in columns[index].windows.compactMap { workspace.bandIndex(of: $0) }.first }
        if let index = (0..<place).reversed().compactMap(column).first { return index + 1 }
        return (place + 1..<columns.count).compactMap(column).first
    }
}
