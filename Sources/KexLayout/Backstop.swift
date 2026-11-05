/// A periodic check that waits while something is busy, but never more than `most` times in a row: the time it comes
/// after a run of busy ones, it runs however busy things are.
public struct Backstop: Sendable {
    public let most: Int
    /// How many times in a row it has waited.
    public private(set) var waited = 0

    public init(most: Int) {
        self.most = most
    }

    /// Whether the check runs this time, `busy` saying whether it would wait.
    public mutating func due(busy: Bool) -> Bool {
        guard busy, waited < most else {
            waited = 0
            return true
        }
        waited += 1
        return false
    }
}
