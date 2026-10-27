import Testing
@testable import DinkyLayout

struct RaiseAfterActivatingTests {
    // A strip of one app's windows (pid 7), a let-go having activated 1: 2, the column in view at the wall, is under 3
    // and 4, which hide behind it. 9 is another app's (pid 8), 5 a pin of the strip's app.
    private let owners: [WindowID: Int32] = [1: 7, 2: 7, 3: 7, 4: 7, 5: 7, 9: 8, 10: 8]

    private func step(_ raises: [WindowID], focused: WindowID, busy: @escaping (Int32) -> Bool = { _ in false },
                      elapsed: Double = 0, retry: Bool = false,
                      pinned: Set<WindowID> = []) -> RaiseAfterActivating.Step {
        RaiseAfterActivating.step(raises: raises, front: 1, owners: owners, focused: focused,
                                  focusedOwner: owners[focused] ?? 0, pinned: pinned, busy: busy, elapsed: elapsed,
                                  retry: retry)
    }

    @Test func `Nothing out of order is done`() {
        #expect(step([], focused: 4) == .done)
    }

    @Test func `With the activated window in front, its app's others are raised and it goes last`() {
        #expect(step([2], focused: 1) == .raise([2, 1], busy: []), "1 raised again after 2, so it keeps focus")
        #expect(step([2], focused: 0) == .raise([2, 1], busy: []), "no focused window read")
    }

    @Test func `While another window of its app has focus, it waits, and gives up in the end`() {
        let wait = RaiseAfterActivating.Wait(focused: 4, pid: 7)
        #expect(step([2], focused: 4) == .wait(wait))
        #expect(step([2], focused: 4, elapsed: 0.55, retry: true) == .wait(wait))
        #expect(step([2], focused: 4, elapsed: 0.58, retry: true) == .giveUp(wait))
    }

    @Test func `Focus on another app's window does not hold it up`() {
        #expect(step([2], focused: 9) == .raise([2, 1], busy: []))
    }

    @Test func `Focus gone to another app on a retry gives up`() {
        let wait = RaiseAfterActivating.Wait(focused: 9, pid: 8)
        #expect(step([2, 10], focused: 9) == .wait(wait), "first try: 10 of the focused app would take its focus")
        #expect(step([2, 10], focused: 9, retry: true) == .giveUp(wait))
    }

    @Test func `A focused pin of the front's app does not hold it up`() {
        #expect(step([2], focused: 5, pinned: [5]) == .raise([2, 1], busy: []))
        #expect(step([2], focused: 5) == .wait(RaiseAfterActivating.Wait(focused: 5, pid: 7)), "not a pin, it waits")
    }

    @Test func `A busy app's windows are left out, the rest raised`() {
        let busy = { (pid: Int32) in pid == 8 }
        #expect(step([2, 10], focused: 1, busy: busy) == .raise([2, 1], busy: [8]))
        #expect(step([10], focused: 1, busy: busy) == .done, "only a busy app's to raise")
        #expect(step([2], focused: 1, busy: { $0 == 7 }) == .done, "front's app busy: nothing to raise")
    }

    @Test func `A wait tells why`() {
        #expect(RaiseAfterActivating.Wait(focused: 4, pid: 7).description == "focus 4 of 7")
    }
}
