// Which native Space each workspace is, and the one step that brings the Spaces closer to the config: a
// workspace per Space, each on its display (`[workspace-to-display]`, else the main display), in number order
// on each display, and no empty Space left over. The app runs the step, re-reads the Spaces and asks again,
// so a change macOS makes halfway (a display coming or going) is planned around rather than fought.
// Pure: no AppKit, no WindowServer. The app supplies the Spaces and carries out the steps.

/// A display as the plan sees it.
public struct PlanDisplay: Equatable {
    public var uuid: String
    public var monitor: Monitor
    /// User Spaces in Mission Control order; full-screen Spaces are left out.
    public var spaces: [UInt64]
    public var current: UInt64

    public init(uuid: String, monitor: Monitor, spaces: [UInt64], current: UInt64) {
        self.uuid = uuid
        self.monitor = monitor
        self.spaces = spaces
        self.current = current
    }
}

public enum PlanAction: Equatable {
    /// Create a user Space at the end of the display's strip.
    case create(display: String)
    /// Move every window on one Space to another.
    case move(from: UInt64, to: UInt64)
    /// Remove an empty Space no workspace is on.
    case remove(space: UInt64)
}

public struct PlanStep: Equatable {
    /// Workspace number to Space, updated for this step. The app keeps it for the next one. It assumes the
    /// action succeeds; the app reverts it when the action fails.
    public var binding: [Int: UInt64]
    /// What to do next, nil when the Spaces match the config.
    public var action: PlanAction?
}

public struct WorkspacePlan {
    public let count: Int
    public let assignments: [Int: [MonitorPattern]]
    /// The workspaces laid out as scrolling strips, which `[scrolling] span-displays` pairs across two displays.
    public var scrolling: Set<Int> = []
    /// Whether `[scrolling] span-displays` is on: see `companions`.
    public var spansDisplays = false

    public init(count: Int, assignments: [Int: [MonitorPattern]]) {
        self.count = count
        self.assignments = assignments
    }

    public init(_ config: Config) {
        self.init(count: config.workspaces, assignments: config.workspaceDisplays)
        spansDisplays = config.scrolling.spanDisplays
        scrolling = Set((1...max(config.workspaces, 1)).filter { config.settings(forWorkspace: $0).layout == .scrolling })
    }

    /// With `spansDisplays`, for `pair`, two displays side by side by UUID: how many user Spaces each needs so that every
    /// scrolling workspace on the other has a Space at the same place to run one strip across both with. Only a display
    /// with no workspace of its own has Spaces free to pair; its Spaces are companions, created as needed and never
    /// removed below that count. Empty otherwise.
    public func companions(_ displays: [PlanDisplay], binding: [Int: UInt64], pair: (left: String, right: String)?)
        -> [String: Int] {
        guard spansDisplays, let pair, let a = displays.first(where: { $0.uuid == pair.left }),
              let b = displays.first(where: { $0.uuid == pair.right }) else { return [:] }
        var needs: [String: Int] = [:]
        for (here, there) in [(a, b), (b, a)] where !binding.values.contains(where: there.spaces.contains) {
            let last = here.spaces.indices.last { i in
                binding.first { $0.value == here.spaces[i] }.map { scrolling.contains($0.key) } ?? false
            }
            if let last { needs[there.uuid] = last + 1 }
        }
        return needs
    }

    /// Workspace numbers, 1 through `count`; none when `count` is 0.
    private var numbers: StrideThrough<Int> { stride(from: 1, through: count, by: 1) }

    /// The display each workspace lives on: the display its first matching pattern names, else the main one.
    public func homes(_ displays: [PlanDisplay]) -> [Int: String] {
        guard let main = displays.first(where: \.monitor.isMain) ?? displays.first else { return [:] }
        var homes: [Int: String] = [:]
        for n in numbers {
            let assigned = assignments[n]?.lazy.compactMap { pattern in displays.first { pattern.matches($0.monitor) } }.first
            homes[n] = (assigned ?? main).uuid
        }
        return homes
    }

    /// The next step from where things stand. `binding` is the previous step's; `occupied` is the Spaces that
    /// have windows on them. Workspaces are placed display by display, in number order, each on the first free
    /// Space after the previous one's (a new Space when there is none), moving its windows along when it
    /// changes Space; windows only ever go to an empty Space, so two sets never mix. Then empty Spaces no
    /// workspace is on are removed; one is kept on a display with no workspace, which macOS requires anyway.
    /// A leftover Space with windows is left alone.
    /// With `pair`, the companions it needs are made after the workspaces are placed, and kept (`companions`).
    public func step(_ displays: [PlanDisplay], binding: [Int: UInt64], occupied: Set<UInt64>,
                     pair: (left: String, right: String)? = nil) -> PlanStep {
        let all = Set(displays.flatMap(\.spaces))
        // Forget Spaces that are gone and workspaces past the count; one workspace per Space.
        var binding = binding.filter { n, space in numbers.contains(n) && all.contains(space) }
        for n in binding.keys.sorted() where binding.contains(where: { $0.key < n && $0.value == binding[n] }) {
            binding[n] = nil
        }
        let homes = homes(displays)

        for display in displays {
            var last = -1  // position of the previous workspace's Space on this display
            for n in numbers.filter({ homes[$0] == display.uuid }) {
                if let space = binding[n], let at = display.spaces.firstIndex(of: space), at > last {
                    last = at
                    continue
                }
                let bound = Set(binding.values)
                let old = binding[n].flatMap { occupied.contains($0) ? $0 : nil }
                guard let at = display.spaces.indices.first(where: { i in
                    i > last && !bound.contains(display.spaces[i]) && (old == nil || !occupied.contains(display.spaces[i]))
                }) else {
                    return PlanStep(binding: binding, action: .create(display: display.uuid))
                }
                binding[n] = display.spaces[at]
                last = at
                if let old { return PlanStep(binding: binding, action: .move(from: old, to: display.spaces[at])) }
            }
        }

        let needs = companions(displays, binding: binding, pair: pair)
        for display in displays where display.spaces.count < needs[display.uuid] ?? 0 {
            return PlanStep(binding: binding, action: .create(display: display.uuid))
        }

        let bound = Set(binding.values)
        for display in displays {
            let hasWorkspace = display.spaces.contains(where: bound.contains)
            let keep = hasWorkspace ? nil : (display.spaces.contains(display.current) ? display.current : display.spaces.first)
            let companions = display.spaces.prefix(needs[display.uuid] ?? 0)
            if let space = display.spaces.first(where: {
                !bound.contains($0) && $0 != keep && !occupied.contains($0) && !companions.contains($0)
            }) {
                return PlanStep(binding: binding, action: .remove(space: space))
            }
        }
        return PlanStep(binding: binding, action: nil)
    }
}
