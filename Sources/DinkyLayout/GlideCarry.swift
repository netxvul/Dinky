// Whether a glide under way carries on into a pass instead of being taken over by it.

/// A glide under way heading for `layout`, writing every window of it but `frozen` (the windows a drag has), carries on
/// into a pass that lays out the same and writes the same windows: the pass has nothing to add. One that left a window
/// out that the pass would write, as when the button comes up on a drop that moves nothing, is taken over, so that
/// window is written too.
public struct GlideCarry: Equatable, Sendable {
    public let layout: Layout
    public let frozen: Set<WindowID>

    public init(layout: Layout, frozen: Set<WindowID>) {
        self.layout = layout
        self.frozen = frozen
    }

    public func carriesOn(into layout: Layout, frozen: Set<WindowID>) -> Bool {
        self.layout == layout && self.frozen == frozen
    }
}
