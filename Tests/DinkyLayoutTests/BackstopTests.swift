import Testing
@testable import DinkyLayout

struct BackstopTests {
    /// Whether it runs each time, `busy` saying whether each would wait.
    private func runs(_ busy: [Bool], most: Int = 4) -> [Bool] {
        var backstop = Backstop(most: most)
        return busy.map { backstop.due(busy: $0) }
    }

    @Test func `Runs every time when nothing is busy`() {
        #expect(runs(Array(repeating: false, count: 6)) == Array(repeating: true, count: 6))
    }

    @Test func `Waits while busy, at most four times in a row`() {
        #expect(runs(Array(repeating: true, count: 10)) == [false, false, false, false, true, false, false, false, false, true])
    }

    @Test func `A time that is not busy starts the count again`() {
        #expect(runs([true, true, false, true, true, true, true, true]) == [false, false, true, false, false, false, false, true])
    }
}
