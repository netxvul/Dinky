import Foundation

// `[gestures] swallow-scroll`: fingers that swipe or scroll the strip on a trackpad or a Magic Mouse also scroll, as
// far as macOS is concerned, and the app under the pointer would scroll with them: the travel before the swipe is
// known, a swipe whose commands show nothing, and the momentum after they lift. What is decided here is the pure part,
// for each scroll event as it comes: whether it goes on to the app, is swallowed, or goes on as the end of its stroke.

/// One scroll stroke at a time, from its first event, or the first heard of it, to the end of its momentum. A stroke
/// begun with the gesture's fingers down is swallowed whole, its momentum with it; one they join on the way ends there
/// for the app, the event they joined at going on as its end with nothing moved, so the app lets go of it cleanly (a
/// page pulled past its edge springs back), and the rest of it and its momentum are swallowed. A wheel without phases
/// is swallowed while they are down. Anything else goes to the app.
public struct ScrollGuard: Equatable, Sendable {
    /// What becomes of a scroll event.
    public enum Verdict: Equatable, Sendable {
        case pass
        case swallow
        /// Goes on as its stroke's end (`ScrollPhase.ended`), every delta 0.
        case end
    }

    /// `scrollWheelEventScrollPhase`'s values; `scrollWheelEventMomentumPhase`'s end is `momentumEnded`.
    public enum ScrollPhase {
        public static let began: Int64 = 1
        public static let changed: Int64 = 2
        public static let ended: Int64 = 4
        public static let cancelled: Int64 = 8
        public static let mayBegin: Int64 = 128
        public static let momentumEnded: Int64 = 3
    }

    /// With no event for this long, a stroke taken is taken no more: its end, or its momentum's, went by unheard.
    public static let stale: Double = 1

    private enum Stroke: Equatable, Sendable {
        case idle
        /// A stroke going to the app.
        case passing
        /// A stroke taken from the app: the rest of it is swallowed.
        case taking
        /// A stroke taken ended, or one that ended for the app as the fingers landed: its momentum is swallowed.
        case coasting
    }

    private var stroke = Stroke.idle
    private var lastAt = -Double.infinity

    public init() {}

    /// Whether a stroke is taken, its own events or its momentum still to swallow.
    public var holding: Bool { stroke == .taking || stroke == .coasting }

    /// Decides one scroll event with phase `phase` and momentum phase `momentum`, `fingers` saying whether the
    /// gesture's fingers are down, at `time` seconds.
    public mutating func scroll(phase: Int64, momentum: Int64, fingers: Bool, at time: Double) -> Verdict {
        if time - lastAt > Self.stale, holding { stroke = .idle }
        lastAt = time
        if momentum != 0 {
            switch stroke {
            case .taking, .coasting:
                if momentum == ScrollPhase.momentumEnded { stroke = .idle }
                return .swallow
            case .idle, .passing:
                // The momentum of a stroke that went to the app is its own, fingers landing on it or not: they stop
                // it soon enough.
                if momentum == ScrollPhase.momentumEnded { stroke = .idle }
                return .pass
            }
        }
        switch phase {
        case 0:
            // A wheel without phases: no stroke to end, each event is the app's or not.
            return fingers ? .swallow : .pass
        case ScrollPhase.mayBegin, ScrollPhase.began:
            // A new stroke, the fingers on the surface first and then moving: begun with the gesture's fingers, it is
            // theirs. Fingers landing between the two end what the app heard of it.
            let heard = stroke == .passing
            guard fingers else {
                stroke = .passing
                return .pass
            }
            stroke = .taking
            return heard ? .end : .swallow
        case ScrollPhase.changed:
            switch stroke {
            case .taking:
                return .swallow
            case .idle, .passing, .coasting:
                // A stroke going to the app, or one heard only now, as the fingers landed after it began.
                guard fingers else {
                    stroke = .passing
                    return .pass
                }
                stroke = .taking
                return .end
            }
        default:
            // Ended, or cancelled.
            switch stroke {
            case .taking:
                stroke = .coasting
                return .swallow
            case .idle, .passing, .coasting:
                // The app's end, which it must have; with the fingers down, as when macOS ends two fingers' stroke as
                // a third lands, its momentum is theirs.
                stroke = fingers ? .coasting : .idle
                return .pass
            }
        }
    }

    /// At `time`, whether a stroke taken has gone stale, and if so lets go of it.
    public mutating func expire(at time: Double) -> Bool {
        guard holding, time - lastAt > Self.stale else { return false }
        stroke = .idle
        return true
    }

    /// Forgets the stroke, as when the tap goes off and hears no more of it.
    public mutating func reset() {
        stroke = .idle
    }
}
