import Testing
@testable import DinkyLayout

struct RecentTests {
    @Test func `Nothing before the first change`() {
        var recent = Recent<Int>()
        #expect(recent.previous == nil)
        recent.note(1)
        #expect(recent.current == 1)
        #expect(recent.previous == nil)
    }

    @Test func `The previous value is a different one`() {
        var recent = Recent<Int>()
        recent.note(1)
        recent.note(2)
        recent.note(2)
        #expect(recent.current == 2)
        #expect(recent.previous == 1)
    }

    @Test func `Going back toggles`() {
        var recent = Recent<Int>()
        recent.note(1)
        recent.note(2)
        recent.note(recent.previous!)
        #expect(recent.current == 1)
        #expect(recent.previous == 2)
    }

    @Test func `Values that went away are forgotten`() {
        var recent = Recent<String>()
        recent.note("a")
        recent.note("b")
        recent.forget { $0 == "a" }
        #expect(recent.previous == nil)
        #expect(recent.current == "b")
        recent.forget { $0 == "b" }
        #expect(recent.current == nil)
        recent.note("c")
        #expect(recent.previous == nil)
    }
}
