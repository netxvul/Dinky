import CoreGraphics
import Foundation

/// When the trackpad ticks as fingers move a strip: each time the column a let-go would settle on (`heldTarget`)
/// changes, at once the first time it crosses to a column, but not for the flicker of a target at a boundary between
/// two columns, or at an end of the strip, as fingers resting there move a fraction of a point, and not more often than
/// `gap`. Going back to the column just left needs the strip `margin` from where the one it left was felt, and leaving a
/// column felt at an end needs it `margin` from where that one stayed the target; one inside the gap is checked again as
/// the gap ends (`moved` answers `.later`), so a stroke that stops on a column still ticks for it.
public struct StripTicker: Equatable, Sendable {
    /// Points the strip moves before a change back, or away from an end, is felt: about half a millimetre of finger
    /// travel.
    public static let margin: CGFloat = 8
    /// The least time between two ticks.
    public static let gap: CFTimeInterval = 0.055

    /// The target last ticked for, or held as the fingers took hold.
    public private(set) var felt: WindowID?
    /// The strip's offset as `felt` was last the target.
    public private(set) var feltOffset: CGFloat
    /// The target felt before `felt`, which going back to needs the margin.
    public private(set) var previous: WindowID?
    /// The strip's offset as `felt` was accepted.
    public private(set) var acceptedOffset: CGFloat
    /// Whether `felt` was accepted, or held as the fingers took hold, at an end of the strip.
    public private(set) var feltAtEnd: Bool
    /// When it last ticked.
    public private(set) var tickedAt: CFTimeInterval = -.infinity

    public enum Decision: Equatable, Sendable {
        /// Nothing to tick.
        case none
        /// Tick for this target now.
        case tick(WindowID)
        /// A change came inside the gap: ask again at this time.
        case later(CFTimeInterval)
    }

    /// Seeded as fingers take hold, the target and offset then, and whether the strip is at an end.
    public init(target: WindowID?, offset: CGFloat, atEnd: Bool = false) {
        felt = target
        feltOffset = offset
        acceptedOffset = offset
        feltAtEnd = atEnd
    }

    /// The strip is at `offset`, a let-go settling on `target`, at time `now`; `atEnd` where it can go no further that
    /// way, as an end's column becomes the target only there, which is always felt.
    public mutating func moved(to target: WindowID?, offset: CGFloat, at now: CFTimeInterval,
                               atEnd: Bool = false) -> Decision {
        guard let target else { return .none }
        if target == felt {
            feltOffset = offset
            return .none
        }
        let ready = atEnd ? true
            : feltAtEnd ? abs(offset - feltOffset) >= Self.margin
            : target == previous ? abs(offset - acceptedOffset) >= Self.margin
            : true
        guard ready else { return .none }
        // A millisecond's grace, so a check scheduled for the gap's end is not a hair early.
        guard now - tickedAt >= Self.gap - 0.001 else { return .later(tickedAt + Self.gap) }
        previous = felt
        felt = target
        feltOffset = offset
        acceptedOffset = offset
        feltAtEnd = atEnd
        tickedAt = now
        return .tick(target)
    }
}
