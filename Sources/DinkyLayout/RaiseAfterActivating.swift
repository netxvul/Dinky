// A window dinky has just activated, as one a strip's let-go settles on, can have its app's other windows out of order
// around it: the passes that put the strip there could not raise them while another window of that app had focus, as
// raising one would have made it the app's key window. Activated, the window is the one focus belongs on, so they go
// into order now. But the window server can still have the app's previous window in front for a moment as the
// activation's answer comes: the raise waits for that, trying again a little later, up to a limit. An app not
// answering is left out, as a raise would leave it out anyway.

/// What to do, at each try, to raise windows into order around a window dinky has just activated.
public enum RaiseAfterActivating {
    /// How long to wait between tries.
    public static let interval: Double = 0.025
    /// How long after the activation to stop trying.
    public static let longest: Double = 0.6

    /// Why a try was not ready: the window in front of the app in front, and its app, where raising would take focus
    /// from it.
    public struct Wait: Equatable, CustomStringConvertible {
        public var focused: WindowID, pid: Int32

        public init(focused: WindowID, pid: Int32) {
            self.focused = focused
            self.pid = pid
        }

        public var description: String { "focus \(focused) of \(pid)" }
    }

    public enum Step: Equatable {
        /// Nothing out of order.
        case done
        /// Out of order are only windows of these apps, not answering: nothing raised.
        case busy([Int32])
        /// Raise these, back to front, leaving out those of `busy` apps.
        case raise([WindowID], busy: [Int32])
        /// Not yet, for this reason: try again after `interval`.
        case wait(Wait)
        /// Not ready by `longest`, or focus went meanwhile to an app other than `front`'s and the one focused at the
        /// first try.
        case giveUp(Wait)
    }

    /// The step for a try `elapsed` seconds after the activation of `front`, `retry` for any but the first, `raises`
    /// being what the layout raises from the window server's order now (`Layout.raises(current:)`), `owners` their
    /// apps, `focused` the front app's front window as the window server has it (0 for none) and `focusedOwner` its
    /// app, `pinned` the strip's pins, and `busy` whether an app is not answering. Raising makes a window its app's key
    /// window, so `front` goes last when its app has another raised. Raising another window of the app whose window
    /// is focused would take focus from it, so the raise waits for `front` to be the one, except where the focused
    /// window is a pin of `front`'s app, put in front through Dock and so read as that app's frontmost: only its app
    /// counts. An app activated is in front only a moment after it was asked to be, so on the first tries the app
    /// focused before, `firstOwner` the one focused at the first try, can still be: focus gone on a retry to an app
    /// other than those two is the user's doing, and the raise gives up.
    public static func step(raises: [WindowID], front: WindowID, owners: [WindowID: Int32], focused: WindowID,
                            focusedOwner: Int32, pinned: Set<WindowID> = [], busy: (Int32) -> Bool,
                            elapsed: Double, retry: Bool = false, firstOwner: Int32? = nil) -> Step {
        let frontOwner = owners[front]
        if retry, focused != 0, focused != front, focusedOwner != frontOwner, focusedOwner != firstOwner {
            return .giveUp(Wait(focused: focused, pid: focusedOwner))
        }
        var skipped: [Int32] = []
        var ids = raises.filter { id in
            guard let pid = owners[id], busy(pid) else { return true }
            if !skipped.contains(pid) { skipped.append(pid) }
            return false
        }
        guard !ids.isEmpty else { return skipped.isEmpty ? .done : .busy(skipped) }
        if ids.last != front, let pid = frontOwner, !busy(pid), ids.contains(where: { owners[$0] == pid }) {
            ids = ids.filter { $0 != front } + [front]
        }
        let pin = pinned.contains(focused)
        let taking = focused != 0 && focused != front && ids.contains { owners[$0] == focusedOwner }
            && !(pin && focusedOwner == frontOwner)
        guard taking else { return .raise(ids, busy: skipped) }
        let wait = Wait(focused: focused, pid: focusedOwner)
        return elapsed + interval > longest ? .giveUp(wait) : .wait(wait)
    }
}
