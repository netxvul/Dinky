import AppKit

// A capsule of glass that never takes focus or clicks, on every Space and over full-screen windows, as the HUD
// draws it: on macOS 27 the window's own Liquid Glass with its highlights along the top and bottom edges and its soft
// shadow turned off where the private filter that draws it is found; where that glass is missing, the public
// NSGlassEffectView on macOS 26, and the HUD material before. The switcher's capsule. Main thread only.
final class GlassPanel {
    let panel: NSPanel
    private let content: NSView
    private var cornerRadius: CGFloat
    private let requestsWindowGlass: Bool
    private var usesFallbackSurface = false

    init(content: NSView, cornerRadius: CGFloat) {
        self.content = content
        self.cornerRadius = cornerRadius
        let windowGlass = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        requestsWindowGlass = windowGlass
        var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if windowGlass { mask.formUnion([.titled, .fullSizeContentView, GlassWindow.windowGlassStyle]) }
        panel = GlassWindow(contentRect: NSRect(x: 0, y: 0, width: cornerRadius * 2, height: cornerRadius * 2),
                            styleMask: mask, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        if windowGlass {
            panel.contentView = content
        } else {
            installFallbackSurface()
        }
        hideTitlebar()
    }

    /// Rounds the glass to `radius` and keeps it looking active, as a key window's glass does, without the panel
    /// taking focus. Call after ordering the panel in, and again on the next turn of the run loop, when the glass has
    /// built its layers.
    func dress(cornerRadius radius: CGFloat) {
        cornerRadius = radius
        hideTitlebar()
        guard requestsWindowGlass, !usesFallbackSurface else { return setFallbackCornerRadius() }
        let selector = NSSelectorFromString("_glassWindowBackingGlassView")
        guard #available(macOS 26.0, *), panel.responds(to: selector),
              let glass = panel.perform(selector)?.takeUnretainedValue() as? NSGlassEffectView else {
            installFallbackSurface()
            return setFallbackCornerRadius()
        }
        glass.cornerRadius = radius
        glass.tintColor = nil
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        let active = NSSelectorFromString("_setHasActiveAppearance:")
        if panel.responds(to: active) {
            let setter = unsafeBitCast(panel.method(for: active), to: (@convention(c) (NSObject, Selector, Bool) -> Void).self)
            setter(panel, active, true)
        }
        let acquire = NSSelectorFromString("acquireKeyAppearance")
        if panel.responds(to: acquire) { panel.perform(acquire) }
        let refresh = NSSelectorFromString("_windowChangedKeyState")
        for object in [glass as NSObject, panel as NSObject] where object.responds(to: refresh) { object.perform(refresh) }
        removeShadow()
    }

    /// Turns off the soft shadow the window's glass casts, its shadow and ring shadow in the `glassBackground` filter,
    /// keeping the edge highlights. Private Core Animation, so only where found.
    func removeShadow() {
        guard requestsWindowGlass, !usesFallbackSurface,
              let glass = panel.perform(NSSelectorFromString("_glassWindowBackingGlassView"))?.takeUnretainedValue() as? NSView,
              let root = glass.layer else { return }
        func visit(_ layer: CALayer) {
            if let filters = layer.filters as? [NSObject],
               let i = filters.firstIndex(where: { "\($0)" == "glassBackground" }) {
                let filter = filters[i].copy() as! NSObject
                let keys = filter.value(forKey: "inputKeys") as? [String] ?? []
                for key in ["inputShadowOpacity", "inputRingShadowOpacity", "inputSDRShadowOpacity"] where keys.contains(key) {
                    filter.setValue(0, forKey: key)
                }
                var replaced = filters
                replaced[i] = filter
                layer.filters = replaced
            }
            for sublayer in layer.sublayers ?? [] { visit(sublayer) }
        }
        visit(root)
    }

    private func hideTitlebar() {
        // Hiding just the traffic lights leaves a titlebar overlay over the capsule.
        if requestsWindowGlass { panel.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
    }

    private func installFallbackSurface() {
        guard !usesFallbackSurface else { return }
        let frame = panel.frame
        // No window glass left behind the view's.
        if requestsWindowGlass { panel.styleMask = [.borderless, .nonactivatingPanel] }
        content.removeFromSuperview()
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = nil
            glass.contentView = content
            surface = glass
        } else {
            let material = NSVisualEffectView()
            material.blendingMode = .behindWindow
            material.material = .hudWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.masksToBounds = true
            content.frame = material.bounds
            content.autoresizingMask = [.width, .height]
            material.addSubview(content)
            surface = material
        }
        surface.autoresizingMask = [.width, .height]
        panel.contentView = surface
        panel.setFrame(frame, display: false)
        usesFallbackSurface = true
    }

    private func setFallbackCornerRadius() {
        if #available(macOS 26.0, *), let glass = panel.contentView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            panel.contentView?.layer?.cornerRadius = cornerRadius
        }
    }
}

private final class GlassWindow: NSPanel {
    /// The style bit that gives a window its own Liquid Glass on macOS 27.
    static let windowGlassStyle = NSWindow.StyleMask(rawValue: UInt(1) << 36)

    override var canBecomeMain: Bool { false }

    // Placed exactly, even over the menu bar's edge, where AppKit would push a titled window down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
