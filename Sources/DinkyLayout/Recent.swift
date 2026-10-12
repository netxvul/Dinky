/// The current value and the one before it, for `recent`: noting the value already current changes nothing, so the
/// one before is always a different value, and going to it and back toggles between the two.
public struct Recent<Value: Equatable>: Equatable {
    public private(set) var current: Value?
    /// The value current before `current`, nil until there has been a change.
    public private(set) var previous: Value?

    public init() {}

    public mutating func note(_ value: Value) {
        guard value != current else { return }
        (previous, current) = (current, value)
    }

    /// Drops the values that `gone` says no longer exist, as a Space or display that went away.
    public mutating func forget(where gone: (Value) -> Bool) {
        if let previous, gone(previous) { self.previous = nil }
        if let current, gone(current) { self.current = nil }
    }
}
