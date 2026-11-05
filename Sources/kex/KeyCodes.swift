import CoreGraphics
import KexConfig

/// A key press as the event tap sees it: keycode plus the modifiers bindings care about.
struct KeyPress: Hashable {
    var code: CGKeyCode
    var modifiers: KeyCombo.Modifiers
}

extension KeyPress {
    /// Parsing a combo guarantees its key is in `KeyCombo.keyCodes`.
    init(_ combo: KeyCombo) {
        self.init(code: KeyCombo.keyCodes[combo.key]!, modifiers: combo.modifiers)
    }

    /// Only alt, ctrl, cmd and shift count. Arrow and function keys carry the secondary-fn
    /// flag on Apple keyboards, and caps lock adds its own; both are ignored so that
    /// `ctrl-left` matches however the keyboard reports it. Nil when a modifier is held only by
    /// the key `sides` leaves out, so that key types as usual instead of matching a binding without it.
    init?(_ event: CGEvent, sides: ModifierSides) {
        var modifiers: KeyCombo.Modifiers = []
        for flag in modifierFlags where event.flags.contains(flag.mask) {
            guard flag.isHeld(by: sides, in: event.flags) else { return nil }
            modifiers.insert(flag.modifier)
        }
        self.init(code: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers)
    }
}

/// Each modifier's flag, and the left and right key bits macOS sets beside it (NX_DEVICEL…KEYMASK in IOLLEvent.h).
struct ModifierFlag {
    let mask: CGEventFlags
    let modifier: KeyCombo.Modifiers
    let setting: KeyPath<ModifierSides, ModifierSide>
    let left: UInt64
    let right: UInt64

    /// Whether a key `sides` allows holds the modifier. Events posted without the key bits, as some
    /// remappers do, can't tell the sides apart and count.
    func isHeld(by sides: ModifierSides, in flags: CGEventFlags) -> Bool {
        let bits = flags.rawValue & (left | right)
        return switch sides[keyPath: setting] {
        case .both: true
        case .left: bits == 0 || bits & left != 0
        case .right: bits == 0 || bits & right != 0
        }
    }
}

let modifierFlags: [ModifierFlag] = [
    ModifierFlag(mask: .maskAlternate, modifier: .alt, setting: \.alt, left: 0x20, right: 0x40),
    ModifierFlag(mask: .maskControl, modifier: .ctrl, setting: \.ctrl, left: 0x01, right: 0x2000),
    ModifierFlag(mask: .maskCommand, modifier: .cmd, setting: \.cmd, left: 0x08, right: 0x10),
    ModifierFlag(mask: .maskShift, modifier: .shift, setting: \.shift, left: 0x02, right: 0x04),
]
