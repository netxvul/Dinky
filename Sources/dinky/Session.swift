import AppKit
import DinkyLayout

// What the trees hold, kept on disk for the next launch: a restart of dinky finds the same windows open and none of its
// own state. Saved a moment after anything changes, so a crash leaves it behind, and as dinky quits. Window ids last as
// long as their windows, so what is read back goes by the same test as the crash journal: same app, not launched since.
// A window that fails it is a new window. Main thread only.
struct Session: Codable {
    struct Known: Codable {
        let id: UInt32
        let pid: pid_t
        let bundleID: String?
        let firstSeen: Date
    }

    struct Strip: Codable {
        let space: UInt64
        let memory: StripMemory
    }

    struct Chosen: Codable {
        let id: UInt32
        let floating: Bool
    }

    let windows: [Known]
    let strips: [Strip]
    let chosen: [Chosen]

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/dinky/session.json")
}

extension Coordinator {
    /// The windows that float now, which quitting leaves where they are.
    var floatingWindows: Set<UInt32> {
        Set(placements.compactMap { $0.value.floating ? $0.key : nil })
    }

    /// Reads what the last session left, keeping only the windows still the same. Call once the model is seeded and
    /// before anything is tracked.
    func loadSession() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: Session.url), let session = try? decoder.decode(Session.self, from: data)
        else { return }
        let same = Set(session.windows.filter { known in
            guard let window = model.windows[known.id], window.pid == known.pid, window.bundleID == known.bundleID else { return false }
            let launched = NSRunningApplication(processIdentifier: known.pid)?.launchDate ?? .distantPast
            return launched <= known.firstSeen
        }.map(\.id))
        for strip in session.strips {
            let memory = strip.memory.keeping(same)
            guard !memory.windows.isEmpty else { continue }
            rememberedStrips[strip.space] = memory
            rememberedPending[strip.space] = Set(memory.windows)
        }
        for chosen in session.chosen where same.contains(chosen.id) { chosenFloating[chosen.id] = chosen.floating }
        print("session: \(same.count) of \(session.windows.count) windows of the last session are still open")
    }

    /// The strip `id` goes back into as it arrives on `space`, once: from then on it comes and goes as any window.
    func rememberedStrip(of id: WindowID, on space: UInt64) -> StripMemory? {
        guard rememberedPending[space]?.remove(id) != nil else { return nil }
        defer { dropRememberedIfDone(space) }
        return rememberedStrips[space]
    }

    func forgetRemembered(_ id: WindowID) {
        for space in rememberedPending.keys where rememberedPending[space]!.remove(id) != nil {
            dropRememberedIfDone(space)
        }
    }

    private func dropRememberedIfDone(_ space: UInt64) {
        guard rememberedPending[space]?.isEmpty == true else { return }
        rememberedPending[space] = nil
        rememberedStrips[space] = nil
    }

    func saveSessionSoon() {
        guard !sessionSaveScheduled else { return }
        sessionSaveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.sessionSaveScheduled = false
            self?.saveSession()
        }
    }

    /// Writes the session if it changed.
    func saveSession() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(session()), data != sessionWritten else { return }
        sessionWritten = data
        try? FileManager.default.createDirectory(at: Session.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Session.url, options: .atomic)
    }

    /// The trees as they are, with the windows yet to go back put in as they will be: those on a Space not shown since
    /// dinky started stay remembered through any number of restarts.
    private func session() -> Session {
        var strips: [UInt64: StripMemory] = [:]
        for (key, workspace) in workspaces { strips[key] = workspace.stripMemory }
        for (key, pending) in rememberedPending {
            guard let memory = rememberedStrips[key] else { continue }
            let waiting = memory.windows.filter { pending.contains($0) && model.windows[$0]?.spaceID == key }
            guard !waiting.isEmpty else { continue }
            guard var workspace = workspaces[key] else {
                strips[key] = memory
                continue
            }
            for id in waiting { workspace.arrive(id, remembering: memory) }
            strips[key] = workspace.stripMemory
        }
        strips = strips.filter { !$0.value.windows.isEmpty }
        let ids = strips.values.flatMap(\.windows) + chosenFloating.keys
        let known = Set(ids).sorted().compactMap { id in
            model.windows[id].map { Session.Known(id: id, pid: $0.pid, bundleID: $0.bundleID, firstSeen: $0.identity.firstSeen) }
        }
        return Session(windows: known,
                       strips: strips.sorted { $0.key < $1.key }.map { Session.Strip(space: $0.key, memory: $0.value) },
                       chosen: chosenFloating.sorted { $0.key < $1.key }.map { Session.Chosen(id: $0.key, floating: $0.value) })
    }
}
