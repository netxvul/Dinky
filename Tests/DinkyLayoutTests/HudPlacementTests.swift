import CoreGraphics
import Testing
@testable import DinkyLayout

struct HudPlacementTests {
    private let size = CGSize(width: 120, height: 36)
    // A 1512x982 screen with a 37 pt menu bar.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func `Above a Dock at the bottom`() {
        let visible = CGRect(x: 0, y: 76, width: 1512, height: 869)
        let frame = HudPlacement.frame(size: size, screen: screen, visible: visible, top: false, offset: 16)
        #expect(frame == CGRect(x: 696, y: 92, width: 120, height: 36))
    }

    @Test func `Near the bottom edge when the Dock hides or sits at a side`() {
        let hidden = CGRect(x: 0, y: 4, width: 1512, height: 941)
        #expect(HudPlacement.frame(size: size, screen: screen, visible: hidden, top: false, offset: 16).minY == 20)
        // Centred across what the Dock on the left leaves.
        let left = CGRect(x: 80, y: 0, width: 1432, height: 945)
        let frame = HudPlacement.frame(size: size, screen: screen, visible: left, top: false, offset: 16)
        #expect(frame == CGRect(x: 736, y: 16, width: 120, height: 36))
    }

    @Test func `Below the menu bar at the top`() {
        let visible = CGRect(x: 0, y: 76, width: 1512, height: 869)
        let frame = HudPlacement.frame(size: size, screen: screen, visible: visible, top: true, offset: 16)
        #expect(frame == CGRect(x: 696, y: 893, width: 120, height: 36))
    }

    @Test func `A display left of and below the primary`() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let frame = HudPlacement.frame(size: size, screen: screen, visible: visible, top: false, offset: 16)
        #expect(frame == CGRect(x: -1020, y: -1064, width: 120, height: 36))
    }

    @Test func `Stays on the screen and within its width`() {
        let visible = CGRect(x: 0, y: 0, width: 100, height: 60)
        let frame = HudPlacement.frame(size: size, screen: CGRect(x: 0, y: 0, width: 100, height: 60),
                                       visible: visible, top: true, offset: 200)
        #expect(frame == CGRect(x: 0, y: 0, width: 100, height: 36))
    }
}
