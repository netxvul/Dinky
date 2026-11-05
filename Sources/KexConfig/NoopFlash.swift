import Foundation

/// `[noop-flash]`: a binding or gesture that does nothing glows as far as what it found missing reaches. `[noop-flash]`
/// sets what `[noop-flash.window]`, `[noop-flash.workspace]` and `[noop-flash.display]` leave out, and `enabled = false`
/// there turns all three off.
public struct NoopFlash: Equatable {
    /// One level's flash as it resolves.
    public struct Look: Equatable {
        public var enabled = true
        /// The top-level `highlight-color` when the tables leave it out and that is set, else Claude's orange, as the
        /// screen's edges glow while Claude uses the computer.
        public var color = Highlight.color(try! Color(hex: "#d97757"))
        /// The ring at the edge, in points; 0 leaves it out.
        public var width = 2.0
        /// How far the glow inside the ring reaches in, fading as it goes, in points.
        public var spread = 100.0
        /// The glow's opacity at the edge, as a share of the colour's own; 0 leaves it out.
        public var opacity = 0.6

        public init() {}

        init(_ own: NoopFlashKeys, shared: NoopFlashKeys, highlight: Highlight?) {
            enabled = shared.enabled != false && own.enabled != false
            color = own.color ?? shared.color ?? highlight ?? color
            width = own.width ?? shared.width ?? width
            spread = own.spread ?? shared.spread ?? spread
            opacity = own.opacity ?? shared.opacity ?? opacity
        }
    }

    /// The focused window's edge, for what a window could not do.
    public var window = Look()
    /// The focused display's left and right sides, for no workspace to go to, and a strip's end as it is pushed past.
    public var workspace = Look()
    /// All four edges of a display, for no display to go to.
    public var display = Look()

    public init() {}

    /// `retired` is what `[borders]` still sets from before this table, which `t` goes over.
    init(_ t: Table?, retired: NoopFlashKeys, highlight: Highlight?) throws {
        let shared = try (t.map { try NoopFlashKeys($0) } ?? NoopFlashKeys()).over(retired)
        func level(_ key: String) throws -> Look {
            guard let table = try t?.table(key) else { return Look(NoopFlashKeys(), shared: shared, highlight: highlight) }
            let own = try NoopFlashKeys(table)
            try table.done()
            return Look(own, shared: shared, highlight: highlight)
        }
        window = try level("window")
        workspace = try level("workspace")
        display = try level("display")
        try t?.done()
    }
}

/// What one table of noop flash settings sets, nil where it leaves a key out. `[borders]` spells them `noop-flash`,
/// `noop-flash-color` and so on, from before `[noop-flash]`.
struct NoopFlashKeys: Equatable {
    var enabled: Bool?
    var color: Highlight?
    var width: Double?
    var spread: Double?
    var opacity: Double?

    init() {}

    init(_ t: Table, enabled enabledKey: String = "enabled", prefix: String = "") throws {
        enabled = try t.bool(enabledKey)
        color = try t.highlight(prefix + "color")
        width = try t.double(prefix + "width")
        spread = try t.double(prefix + "spread")
        opacity = try t.double(prefix + "opacity")
        if let width, !(0...8).contains(width) { throw ConfigError(path: t.path(prefix + "width"), "must be 0 to 8") }
        if let spread, !(8...160).contains(spread) { throw ConfigError(path: t.path(prefix + "spread"), "must be 8 to 160") }
        if let opacity, !(0...1).contains(opacity) { throw ConfigError(path: t.path(prefix + "opacity"), "must be 0 to 1") }
    }

    var isEmpty: Bool { self == NoopFlashKeys() }

    /// These keys, and for those left out, `other`'s.
    func over(_ other: NoopFlashKeys) -> NoopFlashKeys {
        var keys = self
        keys.enabled = enabled ?? other.enabled
        keys.color = color ?? other.color
        keys.width = width ?? other.width
        keys.spread = spread ?? other.spread
        keys.opacity = opacity ?? other.opacity
        return keys
    }
}
