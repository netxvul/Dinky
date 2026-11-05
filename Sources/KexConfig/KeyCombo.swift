import Carbon.HIToolbox

/// A key binding such as `alt-shift-h`: modifiers plus a key name, joined by `-`. The leading words that
/// name modifiers are the modifiers; the rest is the key, so `alt-page-up` is `alt` and `page-up`.
/// `hyper` and `meh` name the usual combinations, all four modifiers and all but `cmd`.
/// Key names map to keycodes through `keyCodes`.
public struct KeyCombo: Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let alt = Modifiers(rawValue: 1 << 0)
        public static let ctrl = Modifiers(rawValue: 1 << 1)
        public static let cmd = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// In canonical order.
        static let names: [(String, Modifiers)] = [("alt", .alt), ("ctrl", .ctrl), ("cmd", .cmd), ("shift", .shift)]

        /// Modifier names joined by `-`, such as `ctrl-cmd`, or `none` for no modifiers. Nil for anything else.
        init?(names: String) {
            self = []
            guard names != "none" else { return }
            for name in names.split(separator: "-", omittingEmptySubsequences: false) {
                guard let modifier = Self.names.first(where: { $0.0 == name })?.1 else { return nil }
                insert(modifier)
            }
        }

        /// Canonical form, such as `ctrl-cmd`, or `none`.
        public var name: String {
            isEmpty ? "none" : Self.names.filter { contains($0.1) }.map(\.0).joined(separator: "-")
        }
        /// Shorthands a binding can use, as QMK and Karabiner name them. A combo prints with the modifiers spelled out.
        static let aliases: [(String, Modifiers)] = [("hyper", [.alt, .ctrl, .cmd, .shift]), ("meh", [.alt, .ctrl, .shift])]
    }

    public var modifiers: Modifiers
    public var key: String

    /// Unchecked, so internal: outside this module combos come from `init(_:)`, which rejects unknown key names.
    init(modifiers: Modifiers = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ combo: String) throws(ConfigError) {
        var parts = combo.split(separator: "-", omittingEmptySubsequences: false).map(String.init)[...]
        var modifiers: Modifiers = []
        while let first = parts.first, parts.count > 1,
              let modifier = (Modifiers.names + Modifiers.aliases).first(where: { $0.0 == first })?.1 {
            modifiers.insert(modifier)
            parts.removeFirst()
        }
        let key = parts.joined(separator: "-")
        guard KeyCombo.keyCodes[key] != nil else {
            throw ConfigError("unknown key '\(key)' in '\(combo)', expected modifiers (alt, ctrl, cmd, shift, hyper, meh) and a key name")
        }
        self.init(modifiers: modifiers, key: key)
    }

    /// Canonical form, e.g. `alt-shift-h`, whatever order the config wrote the modifiers in.
    public var description: String {
        let names = Modifiers.names.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "-")
    }

    /// Every key name and its macOS virtual keycode, for a qwerty layout. Parsing rejects any other
    /// name, so every parsed combo has a code.
    public static let keyCodes: [String: UInt16] = {
        let codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,

            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,

            "section": kVK_ISO_Section, "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal,
            "left-bracket": kVK_ANSI_LeftBracket, "right-bracket": kVK_ANSI_RightBracket,
            "backslash": kVK_ANSI_Backslash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
            "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "backtick": kVK_ANSI_Grave,

            "keypad-0": kVK_ANSI_Keypad0, "keypad-1": kVK_ANSI_Keypad1, "keypad-2": kVK_ANSI_Keypad2,
            "keypad-3": kVK_ANSI_Keypad3, "keypad-4": kVK_ANSI_Keypad4, "keypad-5": kVK_ANSI_Keypad5,
            "keypad-6": kVK_ANSI_Keypad6, "keypad-7": kVK_ANSI_Keypad7, "keypad-8": kVK_ANSI_Keypad8,
            "keypad-9": kVK_ANSI_Keypad9, "keypad-clear": kVK_ANSI_KeypadClear,
            "keypad-decimal": kVK_ANSI_KeypadDecimal, "keypad-divide": kVK_ANSI_KeypadDivide,
            "keypad-enter": kVK_ANSI_KeypadEnter, "keypad-equal": kVK_ANSI_KeypadEquals,
            "keypad-minus": kVK_ANSI_KeypadMinus, "keypad-multiply": kVK_ANSI_KeypadMultiply,
            "keypad-plus": kVK_ANSI_KeypadPlus,

            "page-up": kVK_PageUp, "page-down": kVK_PageDown, "home": kVK_Home, "end": kVK_End,
            "forward-delete": kVK_ForwardDelete, "space": kVK_Space, "enter": kVK_Return, "esc": kVK_Escape,
            "backspace": kVK_Delete, "tab": kVK_Tab,
            "left": kVK_LeftArrow, "down": kVK_DownArrow, "up": kVK_UpArrow, "right": kVK_RightArrow,

            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
            "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
            "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
            "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
        ]
        return codes.mapValues { UInt16($0) }
    }()
}
