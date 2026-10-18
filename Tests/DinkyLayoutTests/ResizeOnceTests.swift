import CoreGraphics
import Testing
@testable import DinkyLayout

struct ResizeOnceTests {
    let edge: CGFloat = 1512

    @Test func `A window growing past the screen edge from on screen is nudged past it`() {
        // The right column of two going fullscreen: its size from where it is would stop at the edge.
        let staging = ResizeOnce.staging(from: rect(760, 41, 723, 869), to: rect(33, 41, 1471, 869), edge: edge)
        #expect(staging == rect(762, 41, 1471, 869))
    }

    @Test func `A window growing within the screen stays where it is`() {
        // The left column: 29 + 1471 stays inside the edge.
        let staging = ResizeOnce.staging(from: rect(29, 41, 723, 869), to: rect(8, 41, 1471, 869), edge: edge)
        #expect(staging == rect(29, 41, 1471, 869))
    }

    @Test func `A window already past the edge is not nudged`() {
        let staging = ResizeOnce.staging(from: rect(760, 41, 800, 869), to: rect(33, 41, 1471, 869), edge: edge)
        #expect(staging == rect(760, 41, 1471, 869))
    }

    @Test func `Changes size once only where its frames on the way stay on its display`() {
        let tile = rect(760, 41, 723, 869), full = rect(33, 41, 1471, 869)
        #expect(ResizeOnce.applies(from: tile, to: full, edge: edge, wall: false, dock: false))
        #expect(ResizeOnce.applies(from: full, to: tile, edge: edge, wall: false, dock: false))
        // Another display to the right: staged or gliding back at its whole width, it would hang onto that one.
        #expect(!ResizeOnce.applies(from: tile, to: full, edge: edge, wall: true, dock: false))
        #expect(!ResizeOnce.applies(from: full, to: tile, edge: edge, wall: true, dock: false))
        // The Dock at the right stops the size there.
        #expect(!ResizeOnce.applies(from: tile, to: full, edge: edge, wall: false, dock: true))
        // The left column grows within the screen, wall or not.
        #expect(ResizeOnce.applies(from: rect(29, 41, 723, 869), to: rect(8, 41, 1471, 869), edge: edge, wall: true, dock: true))
        // A lower tile moving up keeps to resizing as it glides.
        #expect(!ResizeOnce.applies(from: rect(8, 480, 744, 430), to: rect(8, 41, 1496, 869), edge: edge, wall: false, dock: false))
    }

    @Test func `Shows once at its staging frame, or within a snapping app's allowance`() {
        let staging = rect(762, 41, 1471, 869)
        #expect(ResizeOnce.shows(rect(762, 41, 1471, 869), staging: staging))
        #expect(ResizeOnce.shows(rect(762, 41, 1463, 862), staging: staging))
        // Clamped at the edge, before the nudge and the second size.
        #expect(!ResizeOnce.shows(rect(760, 41, 752, 869), staging: staging))
        // Moved by the nudge, not resized yet.
        #expect(!ResizeOnce.shows(rect(762, 41, 752, 869), staging: staging))
    }

    @Test func `Growing, shrinking and moving`() {
        let tile = rect(760, 41, 723, 869), full = rect(33, 41, 1471, 869)
        #expect(ResizeOnce.grows(tile, full))
        #expect(!ResizeOnce.grows(full, tile))
        #expect(ResizeOnce.movesAndResizes(tile, full))
        #expect(!ResizeOnce.movesAndResizes(rect(8, 41, 744, 869), rect(8, 41, 1496, 869)))
        #expect(!ResizeOnce.resizes(tile, rect(100, 41, 723, 869)))
    }

    @Test func `Glides to the target's position at the size it has`() {
        #expect(ResizeOnce.glideTarget(rect(33, 41, 1471, 869), size: CGSize(width: 1463, height: 869))
            == rect(33, 41, 1463, 869))
    }

    @Test func `Grows to the left where its left edge goes further than its right`() {
        // The right column going fullscreen.
        #expect(ResizeOnce.growsLeft(rect(760, 41, 723, 869), rect(33, 41, 1471, 869)))
        // The left column, and a middle tile growing as far either way.
        #expect(!ResizeOnce.growsLeft(rect(29, 41, 723, 869), rect(8, 41, 1471, 869)))
        #expect(!ResizeOnce.growsLeft(rect(508, 41, 496, 869), rect(8, 41, 1496, 869)))
        // Coming back is no growing.
        #expect(!ResizeOnce.growsLeft(rect(33, 41, 1471, 869), rect(760, 41, 723, 869)))
    }

    @Test func `Is led in to just past the screen edge, unless already past it`() {
        // Sized to the edge where it is, then moved past it by the nudge.
        #expect(ResizeOnce.leadIn(from: rect(760, 41, 723, 869), edge: edge) == rect(762, 41, 752, 869))
        #expect(ResizeOnce.leadIn(from: rect(760, 41, 752, 869), edge: edge) == rect(762, 41, 752, 869))
        #expect(ResizeOnce.leadIn(from: rect(760, 41, 800, 869), edge: edge) == nil)
    }

    @Test func `Glides by its left edge, its right edge held past the screen's`() {
        let target = rect(33, 41, 1471, 869)
        #expect(ResizeOnce.anchored(rect(500, 41, 900, 869), to: target, edge: edge) == rect(500, 41, 1014, 869))
        // Further past the edge already, it stays there.
        #expect(ResizeOnce.anchored(rect(500, 41, 1100, 869), to: target, edge: edge) == rect(500, 41, 1100, 869))
        // At the target's left edge, it is where the glide has it.
        #expect(ResizeOnce.anchored(rect(33, 41, 1471, 869), to: target, edge: edge) == target)
    }

    @Test func `An anchor holds a glide's frames past the edge on the way to its target`() {
        let anchor = ResizeOnce.Anchor(target: rect(33, 41, 1471, 869), edge: edge)
        #expect(anchor.frame(rect(500, 41, 900, 869)) == rect(500, 41, 1014, 869))
        #expect(anchor.frame(rect(33, 41, 1471, 869)) == rect(33, 41, 1471, 869))
    }

    @Test func `An anchored window is held by the edge beside the column, its other edge kept`() {
        // Coming back by its left edge, the window (2) gets ahead of the left column (1) its app is slow to move.
        let frames: [WindowID: CGRect] = [1: rect(-100, 41, 723, 869), 2: rect(700, 41, 804, 869)]
        let shown: [WindowID: CGRect] = [1: rect(-400, 41, 723, 869), 2: rect(650, 41, 854, 869)]
        let anchored = ResizeOnce.guarded(frames, lead: 2, left: [[1]], right: [], gap: 11, anchored: true) { shown[$0] }
        #expect(anchored[2] == rect(334, 41, 1170, 869))
        let moved = ResizeOnce.guarded(frames, lead: 2, left: [[1]], right: [], gap: 11) { shown[$0] }
        #expect(moved[2] == rect(334, 41, 804, 869))
        // On the right, its right edge waits for the column coming in, its left edge where it is.
        let right: [WindowID: CGRect] = [2: rect(8, 41, 1000, 869), 3: rect(1100, 41, 700, 869)]
        let rightShown: [WindowID: CGRect] = [3: rect(1300, 41, 700, 869)]
        let held = ResizeOnce.guarded(right, lead: 2, left: [], right: [[3]], gap: 11, anchored: true) { rightShown[$0] }
        #expect(held[2] == rect(8, 41, 1281, 869))
    }

    @Test func `A column sliding off ahead of a lagging window stays at its edge`() {
        // Going fullscreen: the left column (1) slides off left faster than the window (2) shows itself moving over it.
        let frames: [WindowID: CGRect] = [1: rect(-800, 41, 895, 869), 2: rect(150, 41, 1446, 869)]
        let shown: [WindowID: CGRect] = [1: rect(-300, 41, 895, 869), 2: rect(343, 41, 1446, 869)]
        let out = ResizeOnce.guarded(frames, lead: 2, left: [[1]], right: [], gap: 11) { shown[$0] }
        // Held so its right edge is no further than 11 from where the window shows: 343 - 11 = 332.
        #expect(out[1] == rect(332 - 895, 41, 895, 869))
        #expect(out[2] == rect(150, 41, 1446, 869))
    }

    @Test func `A window sliding back ahead of the column coming in waits for it`() {
        // Coming back: the window (2) slides right faster than the left column (1) shows itself following.
        let frames: [WindowID: CGRect] = [1: rect(-100, 41, 895, 869), 2: rect(654, 41, 1446, 869)]
        let shown: [WindowID: CGRect] = [1: rect(-870, 41, 895, 869), 2: rect(173, 41, 1446, 869)]
        let out = ResizeOnce.guarded(frames, lead: 2, left: [[1]], right: [], gap: 11) { shown[$0] }
        // The window no further right than the column shows, 25 + 11; the column already right of the window's edge.
        #expect(out[2] == rect(36, 41, 1446, 869))
        #expect(out[1] == rect(-100, 41, 895, 869))
    }

    @Test func `Columns beyond the nearest go along with it`() {
        let frames: [WindowID: CGRect] = [1: rect(-900, 41, 700, 869), 3: rect(-800, 41, 895, 869), 2: rect(150, 41, 1446, 869)]
        let shown: [WindowID: CGRect] = [3: rect(-300, 41, 895, 869), 2: rect(343, 41, 1446, 869)]
        let out = ResizeOnce.guarded(frames, lead: 2, left: [[3], [1]], right: [], gap: 11) { shown[$0] }
        let dx = (343 - 11 - 95) as CGFloat
        #expect(out[1] == rect(-900 + dx, 41, 700, 869))
    }

    @Test func `In step, nothing moves`() {
        let frames: [WindowID: CGRect] = [1: rect(-213, 41, 895, 869), 2: rect(692, 41, 1446, 869), 3: rect(2146, 41, 700, 869)]
        let out = ResizeOnce.guarded(frames, lead: 2, left: [[1]], right: [[3]], gap: 11) { frames[$0] }
        #expect(out == frames)
    }

    @Test func `The right side mirrors the left`() {
        // Growing right over the right column (3), which slides off right faster than the window shows its edge there.
        let frames: [WindowID: CGRect] = [2: rect(8, 41, 1471, 869), 3: rect(1600, 41, 723, 869)]
        let shown: [WindowID: CGRect] = [2: rect(29, 41, 1200, 869), 3: rect(1400, 41, 723, 869)]
        let out = ResizeOnce.guarded(frames, lead: 2, left: [], right: [[3]], gap: 11) { shown[$0] }
        #expect(out[3] == rect(1240, 41, 723, 869))
    }
}
