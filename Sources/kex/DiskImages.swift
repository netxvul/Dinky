import AppKit
import DiskArbitration

// Whether a window comes from a mounted disk image, for the rules' `disk-image`: a Finder window showing a folder on
// one, as opening a .dmg does, or a window of an app run from one, such as an installer a .dmg carries.

enum DiskImages {
    private static let session = DASessionCreate(kCFAllocatorDefault)

    static func holds(window: Window, element: AXUIElement, title: String) -> Bool {
        if let bundle = NSRunningApplication(processIdentifier: window.pid)?.bundleURL, isOnDiskImage(bundle) {
            return true
        }
        guard window.bundleID == "com.apple.finder" else { return false }
        // Finder names a folder's window for the folder, and a volume's root for the volume, which is the window a
        // .dmg opens; it gives the folder's URL as the window's document when it can.
        if let url = document(of: element) { return isOnDiskImage(url) }
        return diskImageVolumes().contains { $0.name == title }
    }

    /// The window's document as a file URL, from its AXDocument attribute.
    private static func document(of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDocumentAttribute as CFString, &value) == .success,
              let string = value as? String, let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }

    /// Whether the volume `url` is on is a disk image, as DiskArbitration names its device model.
    static func isOnDiskImage(_ url: URL) -> Bool {
        guard let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return false }
        return isDiskImage(volume: volume)
    }

    private static func isDiskImage(volume: URL) -> Bool {
        guard let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        return description[kDADiskDescriptionDeviceModelKey] as? String == "Disk Image"
    }

    /// The mounted volumes that are disk images, by name.
    private static func diskImageVolumes() -> [(name: String, url: URL)] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.filter(isDiskImage(volume:)).compactMap { url in
            (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName.map { ($0, url) }
        }
    }
}
