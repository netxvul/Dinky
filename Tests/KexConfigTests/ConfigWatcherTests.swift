import Foundation
import Testing
@testable import KexConfig

struct ConfigWatcherTests {
    // ConfigWatcher reports on the main queue after the write returns, so wait on semaphores off the main actor.
    @Test func `Fires on change`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kex-\(UUID().uuidString).toml")
        try "workspaces = 3\n".write(to: url, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let changed = DispatchSemaphore(value: 0)  // reloaded
        let broken = DispatchSemaphore(value: 0)  // error reported
        let watcher = ConfigWatcher(url: url) { result in
            switch result {
            case .success(let config) where config.workspaces == 4: changed.signal()
            case .failure(let error) where error.path == "gap": broken.signal()
            default: break
            }
        }
        defer { watcher.stop() }

        try "workspaces = 4\n".write(to: url, atomically: false, encoding: .utf8)
        #expect(changed.wait(timeout: .now() + 1) == .success, "reloaded")

        // Atomic save: a new file renamed over the old one.
        try "gap = 4\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(broken.wait(timeout: .now() + 1) == .success, "error reported")
    }
}
