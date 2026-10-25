import Testing
@testable import DinkyLayout

struct RaiseEchoesTests {
    @Test func `A window raised behind the front one echoes while the raise is under way`() {
        var echoes = RaiseEchoes()
        echoes.begin([6387, 251], front: 4885, at: 10)
        #expect(echoes.echoes(6387, at: 10.05))
        #expect(echoes.echoes(251, at: 10.4), "a raise into a busy app can take long; it echoes until the raise is over")
    }

    @Test func `The window a raise puts on top never echoes`() {
        var echoes = RaiseEchoes()
        echoes.begin([251, 4885], front: 4885, at: 10)
        #expect(!echoes.echoes(4885, at: 10.05))
    }

    @Test func `A window not raised never echoes`() {
        var echoes = RaiseEchoes()
        #expect(!echoes.echoes(251, at: 0), "nothing echoes before any raise")
        echoes.begin([251], front: 4885, at: 10)
        #expect(!echoes.echoes(4867, at: 10.05))
    }

    @Test func `Raised windows echo for the settle after the raise and no longer`() {
        var echoes = RaiseEchoes()
        echoes.begin([251], front: 4885, at: 10)
        echoes.end(at: 10.2)
        #expect(echoes.echoes(251, at: 10.2 + RaiseEchoes.settle / 2))
        #expect(!echoes.echoes(251, at: 10.2 + RaiseEchoes.settle))
    }

    @Test func `A raise begun while the last settles keeps its windows behind the new front`() {
        var echoes = RaiseEchoes()
        echoes.begin([251, 6387], front: 4885, at: 10)
        echoes.end(at: 10.1)
        echoes.begin([4867], front: 251, at: 10.15)
        #expect(echoes.echoes(6387, at: 10.2), "the last raise's windows still settle")
        #expect(echoes.echoes(4867, at: 10.2))
        #expect(!echoes.echoes(251, at: 10.2), "the new front, raised by the last one, no longer echoes")
        #expect(!echoes.echoes(4885, at: 10.2), "the last raise's front was never one of its echoes")
    }

    @Test func `A raise begun after the last settled forgets its windows`() {
        var echoes = RaiseEchoes()
        echoes.begin([251], front: 4885, at: 10)
        echoes.end(at: 10.1)
        echoes.begin([4867], front: 3575, at: 11)
        #expect(!echoes.echoes(251, at: 11.05))
        #expect(echoes.echoes(4867, at: 11.05))
    }

    @Test func `With no front every window recorded echoes`() {
        var echoes = RaiseEchoes()
        echoes.begin([1, 2], front: nil, at: 0)
        #expect(echoes.echoes(1, at: 0.05) && echoes.echoes(2, at: 0.05))
    }

    @Test func `Only windows of the apps whose focus a raise can move are echoes`() {
        let owners: [WindowID: Int32] = [6387: 10, 5200: 20, 251: 10, 4885: 10]
        #expect(RaiseEchoes.echoing([6387, 5200, 251, 4885], front: 4885, owners: owners, apps: [10]) == [6387, 251])
    }

    @Test func `The front window's app and the app in front both count`() {
        let owners: [WindowID: Int32] = [4867: 10, 3575: 30, 3572: 30, 5200: 20]
        #expect(RaiseEchoes.echoing([4867, 5200, 3575, 3572], front: 3572, owners: owners, apps: [10, 30]) == [4867, 3575])
    }

    @Test func `With no app known every window but the front is an echo`() {
        let owners: [WindowID: Int32] = [1: 10, 2: 20, 3: 10]
        #expect(RaiseEchoes.echoing([1, 2, 3], front: 3, owners: owners, apps: []) == [1, 2])
        #expect(RaiseEchoes.echoing([1, 2], front: nil, owners: [:], apps: []) == [1, 2])
    }

    @Test func `A window of unknown owner is no echo once apps are known`() {
        #expect(RaiseEchoes.echoing([7, 8], front: 8, owners: [8: 10], apps: [10]).isEmpty)
    }
}
