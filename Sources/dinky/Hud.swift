import AppKit
import DinkyConfig
import DinkyLayout

// `[hud]`: a capsule of glass naming the new layout or binding mode, for a moment, above the Dock or below the menu
// bar of the focused display, or a workspace's number and layout on the display that moved to it, after barhider's second bar. On macOS 27 it is the window's own Liquid Glass, as
// barhider uses it, with its highlights along the top and bottom edges; its soft shadow is turned off where the
// private filter that draws it is found. Where that glass is missing, the public NSGlassEffectView on macOS 26, and
// the HUD material before. A panel that never takes focus or clicks, on every Space and over full-screen windows.
// It fades in rising a few points and fades out after `duration-ms`; another change while it shows replaces the
// text and restarts the count. Without animations it just appears and goes. Main thread only.
final class Hud {
    static let shared = Hud()

    private static let height: CGFloat = 36
    private static let padding: CGFloat = 18
    private static let rise: CGFloat = 6
    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.22

    private lazy var label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private lazy var panel = makePanel()
    /// The content, the label inside its margins, which the window glass or a fallback surface holds.
    private lazy var content: NSView = {
        let content = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.padding),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.padding),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return content
    }()
    /// Whether the panel asked for the window's own glass, and whether it fell back to a view instead.
    private var requestsWindowGlass = false
    private var usesFallbackSurface = false
    private var hideWork: DispatchWorkItem?
    /// Bumped on every show, so a fade-out that finishes after a newer show leaves the panel up.
    private var generation = 0

    private var config: DinkyConfig.Hud { AppState.shared.config.hud }

    func layoutChanged(_ name: String) {
        guard config.enabled, config.onLayoutChange else { return }
        show(name)
    }

    func modeChanged(_ mode: String) {
        guard config.enabled, config.onModeChange else { return }
        show(mode)
    }

    /// The number and layout of the workspace a display is moving to, `space`, shown as soon as the switch starts so
    /// the last workspace's text does not linger through the slide, and again where it lands; nothing off the
    /// numbered workspaces.
    func workspaceChanged(on display: Display, space: UInt64) {
        let number = AppState.shared.numbers.label(of: space)
        guard config.enabled, config.onWorkspaceChange, !number.isEmpty,
              let coordinator = AppState.shared.coordinator else { return }
        show("\(number) · \(coordinator.layoutName(ofSpace: space))", on: screen(of: display.id))
    }

    /// Shows `text` on `screen`, by default the focused display's.
    func show(_ text: String, on target: NSScreen? = nil) {
        guard let screen = target ?? focusedScreen() else { return }
        hideWork?.cancel()
        generation += 1
        label.stringValue = text
        let width = ceil(label.intrinsicContentSize.width) + Self.padding * 2
        let size = CGSize(width: max(width, Self.height * 2), height: Self.height)
        let top = config.position == .top
        let frame = HudPlacement.frame(size: size, screen: screen.frame, visible: screen.visibleFrame,
                                       top: top, offset: CGFloat(config.offset))
        // Glides in from a few points nearer the edge it sits by.
        let start = frame.offsetBy(dx: 0, dy: top ? Self.rise : -Self.rise)
        let wasShowing = panel.isVisible && panel.alphaValue > 0
        if animates && !wasShowing {
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else if animates {
            // Already up, perhaps fading out: the new text and size at once, so nothing of the old text lingers,
            // and back to full.
            panel.setFrame(frame, display: true)
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeIn / 2
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        dressGlass()
        // The glass builds its layers on its first display; catch them then too.
        DispatchQueue.main.async { [weak self] in self?.removeGlassShadow() }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.durationMs), execute: work)
    }

    private func hide() {
        hideWork = nil
        let shown = generation
        guard animates else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            self.panel.orderOut(nil)
        })
    }

    private var animates: Bool {
        AppState.shared.config.animations.enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The screen of the focused window's display, else the one under the pointer.
    private func focusedScreen() -> NSScreen? {
        if let display = AppState.shared.displays.focusedDisplay(), let screen = screen(of: display.id) { return screen }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func makePanel() -> NSPanel {
        let windowGlass = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        requestsWindowGlass = windowGlass
        var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if windowGlass { mask.formUnion([.titled, .fullSizeContentView, HudPanel.windowGlassStyle]) }
        let panel = HudPanel(contentRect: NSRect(x: 0, y: 0, width: Self.height * 2, height: Self.height),
                             styleMask: mask, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        if windowGlass {
            panel.contentView = content
        } else {
            installFallbackSurface(in: panel)
        }
        hideTitlebar(panel)
        return panel
    }

    /// Rounds the window's glass into a capsule and keeps it looking active, as a key window's glass does, without
    /// the panel taking focus. Falls back to a view of glass when the window has none.
    private func dressGlass() {
        hideTitlebar(panel)
        guard requestsWindowGlass, !usesFallbackSurface else {
            setFallbackCornerRadius(Self.height / 2)
            return
        }
        let selector = NSSelectorFromString("_glassWindowBackingGlassView")
        guard #available(macOS 26.0, *), panel.responds(to: selector),
              let glass = panel.perform(selector)?.takeUnretainedValue() as? NSGlassEffectView else {
            installFallbackSurface(in: panel)
            setFallbackCornerRadius(Self.height / 2)
            return
        }
        glass.cornerRadius = Self.height / 2
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
        removeGlassShadow()
    }

    /// Turns off the soft shadow the window's glass casts, its shadow and ring shadow in the `glassBackground` filter,
    /// keeping the edge highlights. Private Core Animation, so only where found.
    private func removeGlassShadow() {
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

    private func hideTitlebar(_ panel: NSPanel) {
        // Hiding just the traffic lights leaves a titlebar overlay over the capsule.
        if requestsWindowGlass { panel.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
    }

    private func installFallbackSurface(in panel: NSPanel) {
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

    private func setFallbackCornerRadius(_ radius: CGFloat) {
        if #available(macOS 26.0, *), let glass = panel.contentView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            panel.contentView?.layer?.cornerRadius = radius
        }
    }
}

private final class HudPanel: NSPanel {
    /// The style bit that gives a window its own Liquid Glass on macOS 27.
    static let windowGlassStyle = NSWindow.StyleMask(rawValue: UInt(1) << 36)

    override var canBecomeMain: Bool { false }

    // Placed exactly, even over the menu bar's edge, where AppKit would push a titled window down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
