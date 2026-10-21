/// What a key does to a switcher that is up: Esc closes it, Return, keypad Enter and Space take the pick, Tab and
/// Shift-Tab step through everything, the arrows and h, j, k, l move the pick as vim's do (h left, j down, k up, l
/// right; along a row, h and k the one before, j and l the one after), a digit picks what it numbers, 0 being 10, and
/// any other letter jumps to the window it is drawn on, by the key's place on a US keyboard as bindings go.
/// With Command, the arrows and h, j, k, l are left alone, for whatever they do there.
public enum SwitcherKey: Equatable, Sendable {
    case dismiss
    case confirm
    case cycle(forward: Bool)
    case move(Direction)
    case number(Int)
    case letter(Character)

    /// The key with `keyCode`, nil for one a switcher leaves alone.
    public init?(keyCode: Int64, shift: Bool = false, command: Bool = false) {
        if keyCode == 53 {
            self = .dismiss
        } else if [36, 76, 49].contains(keyCode) {
            self = .confirm
        } else if keyCode == 48 {
            self = .cycle(forward: !shift)
        } else if let direction = Self.directions[keyCode], !command {
            self = .move(direction)
        } else if let n = Self.digits[keyCode] {
            self = .number(n)
        } else if let letter = Self.letters[keyCode] {
            self = .letter(letter)
        } else {
            return nil
        }
    }

    /// The arrows, and h, j, k, l.
    private static let directions: [Int64: Direction] = [123: .left, 124: .right, 125: .down, 126: .up,
                                                         4: .left, 38: .down, 40: .up, 37: .right]
    /// The letter keys but h, j, k and l, by the letter they type on a US keyboard.
    private static let letters: [Int64: Character] = [0: "a", 1: "s", 2: "d", 3: "f", 5: "g", 6: "z", 7: "x", 8: "c",
                                                      9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y",
                                                      17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 45: "n", 46: "m"]
    /// The digit keys, the row's and the keypad's, by the number they type; 0 is 10.
    private static let digits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
                                                83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10]
}
