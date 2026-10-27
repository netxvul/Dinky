import Testing
@testable import DinkyLayout

struct LinkChoiceTests {
    @Test func `The link steps on the fastest display gliding`() {
        #expect(LinkChoice.display(current: Int?.none, among: []) == nil)
        #expect(LinkChoice.display(current: 1, among: [(id: 1, rate: 60), (id: 2, rate: 120)]) == 2)
        #expect(LinkChoice.display(current: nil, among: [(id: 3, rate: 120), (id: 2, rate: 120)]) == 3)
    }

    @Test func `One as fast as the fastest keeps the link it has`() {
        #expect(LinkChoice.display(current: 2, among: [(id: 1, rate: 120), (id: 2, rate: 120)]) == 2)
        #expect(LinkChoice.display(current: 5, among: [(id: 1, rate: 120)]) == 1, "not gliding there any more")
    }

    @Test func `Else the display of the tree last set gliding, if it is as fast`() {
        let both = [(id: 1, rate: 120.0), (id: 2, rate: 120.0)]
        #expect(LinkChoice.display(current: 5, preferred: 2, among: both) == 2)
        #expect(LinkChoice.display(current: 1, preferred: 2, among: both) == 1, "the link it has first")
        #expect(LinkChoice.display(current: nil, preferred: 2, among: [(id: 1, rate: 120), (id: 2, rate: 60)]) == 1,
                "not slower")
    }
}
