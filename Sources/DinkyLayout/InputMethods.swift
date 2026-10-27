/// Whether an app bundle at `path` is an input method: one installed in an Input Methods folder, the system's, the
/// local one or the user's under `home`. Such an app's windows, as its settings, are no windows to tile.
public func isInputMethodBundle(_ path: String, home: String) -> Bool {
    let folders = ["/System/Library/Input Methods/", "/Library/Input Methods/", home + "/Library/Input Methods/"]
    return folders.contains { path.hasPrefix($0) }
}
