import Testing
@testable import DinkyLayout

struct RaiseAfterActivatingTests {
    // A strip of one app's windows (pid 7), a let-go having activated 1: 2, the column in view at the wall, is under 3
    // and 4, which hide behind it.
    private let owners: [WindowID: Int32] = [1: 7, 2: 7, 3: 7, 4: 7, 9: 8]
    private let free = { (_: Int32) in false }

    private func step(_ raises: [WindowID], focused: WindowID, busy: @escaping (Int32) -> Bool = { _ in false },
                      elapsed: Double = 0) -> RaiseAfterActivating.Step {
        RaiseAfterActivating.step(raises: raises, front: 1, owners: owners, focused: focused,
                                  focusedOwner: owners[focused] ?? 0, busy: busy, elapsed: elapsed)
    }

    @Test func `Nothing out of order is done`() {
        #expect(step([], focused: 4) == .done)
    }

    @Test func `With the activated window in front, its app's others are raised and it goes last`() {
        #expect(step([2], focused: 1) == .raise([2, 1]), "1 raised again after 2, so it keeps focus")
        #expect(step([2], focused: 0) == .raise([2, 1]), "no focused window read")
    }

    @Test func `While another window of its app has focus, it waits, and gives up in the end`() {
        let wait = RaiseAfterActivating.Wait(focused: (4, 7), busy: [])
        #expect(step([2], focused: 4) == .wait(wait))
        #expect(step([2], focused: 4, elapsed: 0.55) == .wait(wait))
        #expect(step([2], focused: 4, elapsed: 0.58) == .giveUp(wait))
    }

    @Test func `Focus on another app's window does not hold it up`() {
        #expect(step([2], focused: 9) == .raise([2, 1]))
    }

    @Test func `An app busy with writes holds it up`() {
        let busy = { (pid: Int32) in pid == 7 }
        #expect(step([2], focused: 1, busy: busy) == .wait(RaiseAfterActivating.Wait(focused: nil, busy: [7])))
        #expect(step([2], focused: 1, busy: free) == .raise([2, 1]))
    }

    @Test func `A wait tells why`() {
        #expect(RaiseAfterActivating.Wait(focused: (4, 7), busy: [7]).description == "focus 4 of 7, busy 7")
    }
}
