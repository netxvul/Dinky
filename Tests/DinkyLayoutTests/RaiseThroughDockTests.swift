import Testing
@testable import DinkyLayout

struct RaiseThroughDockTests {
    // 1 and 2 are one app's (pid 7), 3 and 4 another's (pid 8), 9 the app's in front when it is not 7 (pid 9).
    private let owners: [WindowID: Int32] = [1: 7, 2: 7, 3: 8, 4: 8, 9: 9]

    private func windows(_ ids: [WindowID], front: WindowID?, focused: WindowID, stack: [WindowID]) -> Set<WindowID> {
        RaiseThroughDock.windows(ids, front: front, owners: owners, focused: focused, focusedOwner: owners[focused] ?? 0,
                                 stack: stack)
    }

    @Test func `A window of another app standing over the focused one goes through Dock`() {
        #expect(windows([3], front: 1, focused: 9, stack: [1, 3, 9]) == [3])
    }

    @Test func `A window behind the focused one stays with Accessibility, keeping it behind`() {
        #expect(windows([3], front: 1, focused: 9, stack: [9, 3, 1]).isEmpty)
    }

    @Test func `Those after the first over the focused one go the same way, to stay in front of it`() {
        #expect(windows([4, 3, 1], front: 1, focused: 9, stack: [3, 9, 4, 1]) == [3, 1])
    }

    @Test func `Siblings of a focused front go through Dock with it and all between, it last`() {
        #expect(windows([2, 3, 1], front: 1, focused: 1, stack: [1, 3, 2]) == [2, 3, 1])
    }

    @Test func `The focused front alone of its app raises as before`() {
        #expect(windows([3, 1], front: 1, focused: 1, stack: [1, 3]).isEmpty)
    }

    @Test func `A window not on screen is never ordered`() {
        #expect(windows([2, 4, 3, 1], front: 1, focused: 1, stack: [1, 3, 2]) == [2, 3, 1])
        #expect(windows([3, 4], front: 1, focused: 9, stack: [3, 9]) == [3])
    }

    @Test func `Nothing with no focused window on screen`() {
        #expect(windows([3], front: 1, focused: 0, stack: [3, 1]).isEmpty)
    }
}
