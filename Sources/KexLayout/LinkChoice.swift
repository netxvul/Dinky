/// Which display the animator's one link steps on, while trees on several glide at once.
public enum LinkChoice {
    /// Of `candidates`, the displays the gliding trees are on with their rates, one at the fastest rate: `current`
    /// where it is one of those, so the link is not made again for a display just as fast, else `preferred` (the
    /// display of the tree last set gliding), else the first. Nil with no candidates.
    public static func display<ID: Equatable>(current: ID?, preferred: ID? = nil,
                                              among candidates: [(id: ID, rate: Double)]) -> ID? {
        guard let fastest = candidates.map(\.rate).max() else { return nil }
        let best = candidates.filter { $0.rate >= fastest }
        if let current, best.contains(where: { $0.id == current }) { return current }
        if let preferred, best.contains(where: { $0.id == preferred }) { return preferred }
        return best.first?.id
    }
}
