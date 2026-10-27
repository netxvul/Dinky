// A window dinky has just activated, as one a strip's let-go settles on, can have its app's other windows out of order
// around it: the passes that put the strip there could not raise them while another window of that app had focus, as
// raising one would have made it the app's key window. Activated, the window is the one focus belongs on, so they go
// into order now. But the window server can still have the app's previous window in front for a moment as the
// activation's answer comes, and the glide's last frame writes to the app can still be under way: the raise waits for
// both, trying again a little later, up to a limit.

/// What to do, at each try, to raise windows into order around a window dinky has just activated.
public enum RaiseAfterActivating {
    /// How long to wait between tries.
    public static let interval: Double = 0.025
    /// How long after the activation to stop trying.
    public static let longest: Double = 0.6

    /// Why a try was not ready.
    public struct Wait: Equatable, CustomStringConvertible {
        /// The window in front of the app in front, and its app, where that app owns a window to raise and the window
        /// is not `front`: raising would take focus from it.
        public var focused: (id: WindowID, pid: Int32)?
        /// The apps of windows to raise that are not answering or busy with writes.
        public var busy: [Int32]

        public init(focused: (id: WindowID, pid: Int32)?, busy: [Int32]) {
            self.focused = focused
            self.busy = busy
        }

        public static func == (a: Wait, b: Wait) -> Bool {
            a.focused?.id == b.focused?.id && a.focused?.pid == b.focused?.pid && a.busy == b.busy
        }

        public var description: String {
            var parts: [String] = []
            if let focused { parts.append("focus \(focused.id) of \(focused.pid)") }
            if !busy.isEmpty { parts.append("busy \(busy.map(String.init).joined(separator: " "))") }
            return parts.joined(separator: ", ")
        }
    }

    public enum Step: Equatable {
        /// Nothing out of order.
        case done
        /// Raise these, back to front.
        case raise([WindowID])
        /// Not yet, for this reason: try again after `interval`.
        case wait(Wait)
        /// Not ready by `longest`.
        case giveUp(Wait)
    }

    /// The step for a try `elapsed` seconds after the activation of `front`, `raises` being what the layout raises
    /// from the window server's order now (`Layout.raises(current:)`), `owners` their apps, `focused` the front app's
    /// front window as the window server has it (0 for none) and `focusedOwner` its app, and `busy` whether an app is
    /// not to be raised in now. Raising makes a window its app's key window, so `front` goes last when its app has
    /// another raised.
    public static func step(raises: [WindowID], front: WindowID, owners: [WindowID: Int32], focused: WindowID,
                            focusedOwner: Int32, busy: (Int32) -> Bool, elapsed: Double) -> Step {
        guard !raises.isEmpty else { return .done }
        var ids = raises
        if ids.last != front, let pid = owners[front], ids.contains(where: { owners[$0] == pid }) {
            ids = ids.filter { $0 != front } + [front]
        }
        let taking = focused != 0 && focused != front && ids.contains { owners[$0] == focusedOwner }
        var pids: [Int32] = []
        for id in ids { if let pid = owners[id], !pids.contains(pid) { pids.append(pid) } }
        let wait = Wait(focused: taking ? (focused, focusedOwner) : nil, busy: pids.filter(busy))
        guard wait.focused != nil || !wait.busy.isEmpty else { return .raise(ids) }
        return elapsed + interval > longest ? .giveUp(wait) : .wait(wait)
    }
}
