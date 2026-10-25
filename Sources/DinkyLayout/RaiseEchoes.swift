// Raising windows into their places in the stacking (`Layout.raises`) goes window by window, back to front, and each
// raise puts its window in front of its app's other windows until the ones meant to be in front of it are raised in
// turn. The front window of the front app is what macOS reports as focused, so while dinky raises several windows of
// the app in front, focus seems to visit each of them for a moment. Followed, that would move the tree's focus to a
// window the user never chose and, with `center-focused-column = 'always'`, scroll the strip to it, which calls for
// more raises. `RaiseEchoes` remembers the windows a raise puts in order behind the one it means to end on top, so
// that focus showing on one of them while the raise is under way, or just after, is known for dinky's own doing.

/// The windows dinky is raising into order behind the one meant to end in front of them. Times are seconds on a clock
/// that only goes forward, such as `CACurrentMediaTime`.
public struct RaiseEchoes {
    /// How long after its last raise a raise's windows still count as raised: an app can reorder its windows a little
    /// after it has answered the raise, and the window server tells of the new order later still.
    public static let settle: Double = 0.1

    private var raised: Set<WindowID> = []
    private var front: WindowID?
    /// When the windows stop counting as raised: never while a raise is under way.
    private var settlesAt = -Double.infinity

    public init() {}

    /// Of the windows a raise puts in order (`ids`, with their apps in `owners`), those whose coming to the front of
    /// their app on the way can read as focus: every one but `front`, of `apps` only, the app in front as the raise
    /// begins and `front`'s, which dinky may be activating meanwhile. A window of another app shows as focused only once
    /// the user brings that app forward, which is the user's doing. With no app known, every one but `front`.
    public static func echoing(_ ids: [WindowID], front: WindowID?, owners: [WindowID: Int32], apps: Set<Int32>) -> [WindowID] {
        ids.filter { id in id != front && (apps.isEmpty || owners[id].map { apps.contains($0) } == true) }
    }

    /// A raise begins at `now`, meant to end with `front` on top, and `ids` can show as focused on the way. The windows
    /// of a raise still settling keep counting, behind the new front.
    public mutating func begin(_ ids: [WindowID], front: WindowID?, at now: Double) {
        if now >= settlesAt { raised = [] }
        raised.formUnion(ids)
        self.front = front
        settlesAt = .infinity
    }

    /// The raise begun last is over at `now`: its windows count as raised for `settle` more.
    public mutating func end(at now: Double) {
        settlesAt = now + Self.settle
    }

    /// Whether `id` in front of its app at `now` is only there because dinky is raising it on the way to putting
    /// another window on top: one of the windows recorded, not the one meant to end on top, while the raise is under
    /// way or settling.
    public func echoes(_ id: WindowID, at now: Double) -> Bool {
        now < settlesAt && id != front && raised.contains(id)
    }
}
