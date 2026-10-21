import Testing
@testable import DinkyLayout

struct SwitcherKeyTests {
    @Test func `h, j, k, l move the pick as vim's do, as the arrows`() {
        #expect(SwitcherKey(keyCode: 4) == .move(.left))
        #expect(SwitcherKey(keyCode: 38) == .move(.down))
        #expect(SwitcherKey(keyCode: 40) == .move(.up))
        #expect(SwitcherKey(keyCode: 37) == .move(.right))
        #expect(SwitcherKey(keyCode: 123) == .move(.left))
        #expect(SwitcherKey(keyCode: 125) == .move(.down))
        #expect(SwitcherKey(keyCode: 126) == .move(.up))
        #expect(SwitcherKey(keyCode: 124) == .move(.right))
    }

    @Test func `Along a row, h and k pick the one before, j and l the one after`() {
        func step(_ code: Int64, from index: Int) -> Int? {
            guard case .move(let direction) = SwitcherKey(keyCode: code) else { return nil }
            return SwitcherLayout.step(index, count: 4, toward: direction)
        }
        #expect(step(4, from: 1) == 0)
        #expect(step(40, from: 1) == 0)
        #expect(step(38, from: 1) == 2)
        #expect(step(37, from: 1) == 2)
        #expect(step(4, from: 0) == 3)
        #expect(step(37, from: 3) == 0)
    }

    @Test func `Return, Enter and Space take the pick, Esc closes, Tab cycles`() {
        #expect(SwitcherKey(keyCode: 36) == .confirm)
        #expect(SwitcherKey(keyCode: 76) == .confirm)
        #expect(SwitcherKey(keyCode: 49) == .confirm)
        #expect(SwitcherKey(keyCode: 53) == .dismiss)
        #expect(SwitcherKey(keyCode: 48) == .cycle(forward: true))
        #expect(SwitcherKey(keyCode: 48, shift: true) == .cycle(forward: false))
        #expect(SwitcherKey(keyCode: 18) == .number(1))
        #expect(SwitcherKey(keyCode: 29) == .number(10))
    }

    @Test func `Command leaves the moves alone, and other keys are not the switcher's`() {
        #expect(SwitcherKey(keyCode: 4, command: true) == nil)
        #expect(SwitcherKey(keyCode: 124, command: true) == nil)
        #expect(SwitcherKey(keyCode: 36, command: true) == .confirm)
        #expect(SwitcherKey(keyCode: 27) == nil)
        #expect(SwitcherKey(keyCode: 50) == nil)
    }

    @Test func `Every other letter jumps, by its place on a US keyboard, with Command too`() {
        #expect(SwitcherKey(keyCode: 0) == .letter("a"))
        #expect(SwitcherKey(keyCode: 1) == .letter("s"))
        #expect(SwitcherKey(keyCode: 46) == .letter("m"))
        #expect(SwitcherKey(keyCode: 12, command: true) == .letter("q"))
        #expect(SwitcherKey(keyCode: 4, command: true) == nil)
        #expect(SwitcherKey(keyCode: 38, command: true) == nil)
    }
}
