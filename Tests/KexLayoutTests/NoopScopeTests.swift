import Testing
@testable import KexLayout

struct NoopScopeTests {
    @Test func `A step sideways is kept, one up or down is not`() {
        #expect(NoopScope.stepping(.left) == .window(toward: .left))
        #expect(NoopScope.stepping(.right) == .window(toward: .right))
        #expect(NoopScope.stepping(.up) == .window())
        #expect(NoopScope.stepping(.down) == .window())
    }

    @Test func `A binding flashes the widest of what its commands found`() {
        let sides = NoopScope.workspace(.right, display: "a"), display = NoopScope.display("b")
        #expect(NoopScope.widest([]) == nil)
        #expect(NoopScope.widest([.window()]) == .window())
        #expect(NoopScope.widest([.window(), sides]) == sides)
        #expect(NoopScope.widest([sides, .window()]) == sides)
        #expect(NoopScope.widest([.window(), display, sides]) == display)
        #expect(NoopScope.widest([sides, display]) == display)
        #expect(NoopScope.widest([display, .display("c")]) == display, "the first of the widest")
        #expect(NoopScope.widest([sides, .workspace(.left, display: "a")]) == sides)
    }

    @Test func `Among windows, the first that stepped sideways`() {
        #expect(NoopScope.widest([.window(), .stepping(.up), .stepping(.left), .stepping(.right)]) == .window(toward: .left))
    }

    @Test func `Sides`() {
        #expect(ScreenSides.both.contains(.left) && ScreenSides.both.contains(.right))
        #expect(!ScreenSides.left.contains(.right))
    }
}
