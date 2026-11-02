// An Accessibility raise of a window of an app in the background puts it right behind the frontmost window of the app in
// front, so one that stands over that window, as a strip Dock ordered over a floating window does, sinks behind it. A
// raise of a window of the app in front makes it key and puts it over the focused window till that is raised in turn,
// which its app can take its time over. Ordering through Dock does neither: it moves no focus, and a batch of three took
// 25 to 45 ms when measured, so a window ordered first still covers the focused one for that long.

/// Which of the windows a raise puts in order go through Dock rather than Accessibility.
public enum RaiseThroughDock {
    /// Of `ids`, back to front, those to order through Dock. `stack` is the windows on screen at the level of `focused`,
    /// the front app's front window, front to back; `owners` the apps of `ids`; `front` the window the layout puts on top.
    /// All of them where `front` is the focused window, going last with another window of its app before it: that one
    /// would otherwise cover it till it is raised. Otherwise from the first of another app standing in front of the
    /// focused window on: every one after it goes the same way, to stay in front of it. A window not in `stack` is
    /// never ordered, which would bring it back on screen if hidden. Nothing with no focused window in `stack`.
    public static func windows(_ ids: [WindowID], front: WindowID?, owners: [WindowID: Int32], focused: WindowID,
                               focusedOwner: Int32, stack: [WindowID]) -> Set<WindowID> {
        guard let focusedAt = stack.firstIndex(of: focused) else { return [] }
        let shown = ids.filter(stack.contains)
        if front == focused, ids.last == focused,
           ids.contains(where: { $0 != focused && owners[$0] == focusedOwner }) {
            return Set(shown)
        }
        guard let first = shown.firstIndex(where: { id in
            owners[id] != focusedOwner && stack.firstIndex(of: id).map { $0 < focusedAt } == true
        }) else { return [] }
        return Set(shown[first...])
    }
}
