import Foundation

/// Watches a config file and reloads it when it changes, debounced. Each reload calls `onChange`
/// on the main queue with the new config or the error; the caller keeps the previous config on error.
///
/// Editors often save by writing a new file and renaming it over the old one, which leaves the
/// watched descriptor pointing at a deleted file. So after every change the file is reopened,
/// and while it is missing it is polled until it comes back.
public final class ConfigWatcher {
    private let url: URL
    private let onChange: (Result<Config, ConfigError>) -> Void
    private let queue = DispatchQueue(label: "kex.config-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(url: URL, onChange: @escaping (Result<Config, ConfigError>) -> Void) {
        self.url = url
        self.onChange = onChange
        queue.sync { watch() }
    }

    deinit {
        source?.cancel()
        pending?.cancel()
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            pending?.cancel()
        }
    }

    private func watch() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reopenIfMissing() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue
        )
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func reopenIfMissing() {
        guard source == nil else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            changed()
        } else {
            watch()
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func reload() {
        watch()
        let result = Result { () throws(ConfigError) in try Config.load(from: url) }
        DispatchQueue.main.async { [onChange] in onChange(result) }
    }
}
