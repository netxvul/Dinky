> Superseded on 24 September 2026 by PLAN.md, which cuts this down to a minimal mechanics spike. Kept unchanged as the research archive and as the fuller plan to return to if the spike passes.

# kex

A standalone, SIP-on tiling window manager for macOS.

Created 24 September 2026. Status: research complete enough to start a feasibility spike; no implementation or live window-management validation yet.

This is the first project file. The decisions and implementation sequence below are authoritative. The appendices preserve the complete prior investigations, including alternatives considered before the direction was narrowed. Earlier references to building inside Tuna, scrolling-first layouts, capture renderers, or a privileged edition are research history, not instructions for kex.

## Goal

Find out whether native macOS Spaces, fast switching, predictable automatic tiling and accordion containers can deliver the responsive daily experience that makes Hyprland appealing, while leaving SIP enabled.

The user tried Hyprland on Linux and found it substantially better than macOS window managers. The initial question was whether newer macOS APIs could support something like Hyprland or Niri without the usual workarounds. Research shifted the proposal toward native Spaces and an on-screen accordion layout because seamless Niri-style scrolling depends on clipping windows at a viewport boundary that macOS does not generally let an ordinary process control.

Build the smallest useful experiment that can disprove the architecture before investing in a full window manager. This is not a compositor replacement or a promise of Linux-equivalent presentation control.

## Agreed decisions

| Decision | Meaning |
|---|---|
| Name and location | `kex`, at `~/dev/kex`. |
| Standalone project | Independent app, permissions, lifecycle and codebase. Not a Tuna feature, plugin or extension. |
| SIP stays enabled | No Dock injection, scripting addition or reduced system protection as a prerequisite. |
| Native Spaces own workspace visibility | Start with one native Space per workspace. Inactive workspaces do not use corner parking. |
| Fast switching | Study Tuna's existing synthetic high-velocity Dock swipe technique and implement an independent adapter. |
| Widest-local-axis insertion | Insert beside the focused tile by splitting that tile's available rectangle along its longer dimension. |
| Stable split choices | Preserve established axes until an explicit layout operation changes them; resizing should not unexpectedly rewrite the tree. |
| Accordion | An explicit container mode that overlaps children within the viewport and exposes strips for navigation. |
| One display first | The spike manages one display and two pre-existing ordinary native Spaces. |
| Immediate geometry first | Establish correctness without animation, then compare position-only animation separately. |
| Real windows remain interactive | Normal typing, menus, selection and dragging go directly to the application windows. |
| Recovery is part of the spike | Disable/quit stops pending work and restores recorded geometry where possible; crashes must not strand windows. |
| Research, then implementation | This task creates the plan only. No app scaffold, dependencies, git initialization, installation or changes to Tuna yet. |

The standalone-app correction supersedes the earlier suggestion to build the spike inside Tuna. Existing Tuna code is a reference, not a runtime dependency. No claim is made that its implementation can be copied without checking the project's ownership/license and coupling.

## What the research establishes

### Public API boundary

Accessibility supplies window discovery, events and supported position/size/focus/minimization requests. Calls cross process boundaries, may stall, fail or be constrained by the app, and do not form a documented atomic desktop-wide layout transaction. Quartz window IDs and enumeration do not confer ownership. NSWindow and SwiftUI window placement APIs control the caller's own windows. NSRunningApplication hiding is process-wide. ScreenCaptureKit provides images/streams, not foreign-window ownership or interactive reparenting.

The Apple documentation/SDK investigation through macOS 27 did not find a public third-party compositor interface or a general system-wide custom tiling-policy API. This is a bounded finding, not proof that every private operation has been exhausted. Hyprland/Niri's compositor authority is the fundamental difference, not simply implementation language.

### SIP-on native Spaces are plausible

Tuna already implements fast synthetic swipes. Current yabai, mimi and bobrwm provide source precedent for synthetic Dock gestures and private bridged window-to-Space transfers without requiring the injected scripting addition for those paths. Private calls remain version-sensitive even with SIP enabled.

On the investigated Mac, macOS 27.0 build 26A428 reported SIP enabled. Read-only SkyLight introspection found bridge classes for moving windows, setting the current Space, hiding/showing Spaces, Space transforms/shapes and creating Spaces. Class/method presence is not proof of permission, correct behavior or Dock synchronization. No such operation was exercised during that investigation. Creating/deleting Spaces is not a dependency of the spike.

### Hiding and layout are separate concerns

| Mechanism | Evidence | Decision for kex |
|---|---|---|
| Native Spaces | yabai, Amethyst, Glide, mimi, current bobrwm | Primary workspace backend. |
| Edge/corner parking | AeroSpace, Rift, Paneru, GlazeWM, komorebi and others | Avoid for normal workspaces and layout overflow. |
| Whole-app hide | FlashSpace and Tatami | Does not meet independent-window workspace needs. |
| Per-window minimize | Zonogy | Real invisibility, but changes native minimized state; not the chosen overflow behavior. |
| On-screen overlap | AeroSpace accordion and stack-oriented tools | Chosen accordion direction; focus and ordering still require validation. |
| Virtual monitors with capture | orcv | Separate future experiment, not part of this spike. |
| Capture/proxy rendering | ScreenCaptureKit; yabai's privileged proxy path | Optional research later; does not by itself conceal originals or route input. |

Native Spaces solve visibility between desktops, not partial clipping of a window within a desktop. No inspected implementation demonstrates unrestricted clipping of arbitrary external app windows with SIP on. Niri-like approximations exist, but they retain slivers, mask them, minimize windows, or place them elsewhere. Nehir's final documented fixed-Dock solution is one-point visible-frame parking plus an opaque shield; older failure conclusions in its own log were superseded by that resolution.

### Motion can improve without a compositor

Glide and Rift move real windows through AX. Glide coalesces pending frames per app and avoids continuous size animation. OmniWM also contains private SkyLight positioning paths. Thus neither “all animation needs screenshots” nor “every foreign-window move must use only AX” is a safe assumption. Private positioning is an optional optimization to validate, not required for the baseline.

### Survey coverage

The survey covered 84 products/projects, including related tools and historical references: 31 targeted source inspections, 51 documentation-level reviews and two unresolved leads. It is not an exhaustive census or benchmark. Public source, shipping releases and marketing pages can disagree. The complete catalog and revision list are preserved below so the project does not depend on this chat or its generated research directory.

## Reference implementations to read first

| Reference | Specific lesson |
|---|---|
| Tuna | `~/dev/Tuna/app/SystemExtension/SpacesRuntime.swift`: `gestureSpeed = 2_000.0`, synthetic began/changed/ended Dock swipe events, velocity scaled for distance, native Space queries and display targeting. Read only. |
| mimi | Native-Space adapter and separation between layout policy and OS frame application. |
| bobrwm | Native-Space-backed workspace model, observed-versus-requested transitions, serialized rapid switching. Do not copy its automatic exact-count Space creation/deletion policy. |
| yabai | Private bridge resolution, AX frame ordering, identity/focus and Space transfers; distinguish privileged features. |
| Glide | Per-app concurrency, frame coalescing, bounded final correction, position-versus-size animation tradeoff. |
| Rift | Combining BSP and accordion, layout/state model, event handling. Its corner hiding is not our backend. |
| OmniWM | Dwindle and container behavior; private movement capability checks and diagnostics. |
| AeroSpace | Tree structure, accordion geometry and focus behavior. |
| Nehir | Failure log: successful API returns can still fail visually; Dock/visible-frame edge cases. |
| Defi / Rectangle / Phoenix | Frame readback, bounded corrections and size-position-size patterns. |
| WindowRanger | Restore-before-hide ordering, avoiding unnecessary size writes and app-generated move animation. |
| Zonogy | Explicit handling of displaced windows and minimization-induced focus side effects. |
| Parket / other mature implementations | Native tab groups, transient-window admission and recovery deserve first-class treatment. |

The rest of the catalog is useful chiefly for interaction ideas, independent checks and known compromises. Licensing must be checked before copying code: public availability does not mean permissive reuse; KiwiDesk uses BSL and komorebi has source-available/commercial terms. No implementation license for kex has been selected.

## First spike

The first usable milestone is **three real windows, two native Spaces, one display, widest-axis insertion, one accordion container and reliable keyboard navigation**.

Suggested implementation default: a native Swift/AppKit menu-bar app, with a pure Swift layout module and a narrowly isolated native/private API adapter. This is a proposed engineering choice, not an additional user requirement. Avoid a broad framework or plugin system. Choose the minimum deployment target after checking the actual private bridge compatibility; do not infer it from a class existing on one machine.

### Phase 0 — App shell and recoverable session

- Minimal app with Accessibility onboarding, disabled/enabled status, disable-and-restore, diagnostics and quit.
- Explicitly select the managed display and two pre-existing ordinary Spaces. Full-screen Spaces remain outside scope.
- Begin disabled. On enable, snapshot identities, original Space membership and frames before moving anything.
- Provide a reliable emergency disable path. No auto-launch, hidden global settings changes, or automatic desktop creation/deletion.
- Keep an in-flight operation generation so disable invalidates queued frame writes and focus changes.

Deliverable: launching and quitting a signed development app does not rearrange windows until enabled, and permission denial is recoverable.

### Phase 1 — Native-Space capability spike

- Enumerate displays/Spaces and associate known windows with native Space IDs.
- Independently implement synthetic fast swipe switching, using Tuna/mimi/yabai/bobrwm as references.
- Implement capability-checked private window transfer between the two existing Spaces.
- Test move-without-follow and move-and-follow as distinct operations.
- Observe actual Space membership and focus after each operation. A submitted command does not update observed truth.
- Serialize or coalesce rapid destination requests. Do not replay a growing queue of obsolete swipes.
- Start with disposable windows, then test two windows of the same app on different Spaces.

Gate: transfers and rapid switching work with SIP enabled and leave Dock/Mission Control coherent. Record failure modes and OS build. If transfers fail, the backend assumption is not validated; stop expansion and investigate rather than silently replacing native Spaces with parking.

### Phase 2 — Immediate single-display tiling

- Maintain an independent tree per native Space and stable window membership.
- New windows split the focused leaf; if width exceeds height, create left/right regions; if height exceeds width, create top/bottom regions. Propose a deterministic left/right tie-break and 50/50 initial ratio.
- Preserve prior axes. Removing a leaf collapses redundant containers while preserving surviving order.
- Support directional focus, explicit floating exceptions and a retile action. Keep ordinary close behavior native.
- Reconcile creation/close/activation events and external Space moves without duplicating windows or dragging them back unexpectedly.
- Manage normal document windows. Sheets/dialogs remain associated transients; native tab groups must not turn every inactive tab into another tile.
- Read back actual geometry. Respect fixed-size/minimum-size constraints; bound corrections instead of fighting the app indefinitely.

Gate: three representative windows open, close, focus and retile predictably on either Space. Apps that reject a size do not stall unrelated windows or cause retry loops.

### Phase 3 — Explicit accordion containers

- Toggle the focused window's containing group between split and accordion. Define the exact selection rule in implementation notes before adding nested UI.
- Keep all accordion children inside the usable viewport, overlapping to preserve useful window sizes and visible navigation strips.
- Raise/expand the focused child while preserving a stable child order; retain prior split ratios for toggling back.
- Account for minimum sizes and the space consumed by strips. If the container cannot fit, report the constraint and preserve usable geometry; do not park windows as a hidden fallback.
- Test focus from both kex commands and native activation, including Cmd-Tab and Dock clicks.

Gate: cycling through a three-window accordion repeatedly produces the intended focused/frontmost window and no edge-parking artifacts. Split-to-accordion-to-split is reversible.

Automatic conversion to accordion under minimum-size pressure is intentionally undecided. First establish whether the explicit mode feels right.

### Phase 4 — Optional movement experiment

Only after the immediate version is dependable:

- Add a short, interruptible, position-only animation; keep resizing immediate initially.
- Coalesce to the newest target per window/app and correct once after settling.
- Compare actual motion and latency with animation disabled using the same workload.
- Treat direct SkyLight movement as a separate capability experiment with a validated fallback.
- Do not add screenshot proxies, live captured-window interaction or Screen Recording permission for this milestone.

Gate: animation improves perceived motion without worsening final geometry, input/focus or recovery. Keep it off if it does not.

## Proposed internal boundaries

```text
App / commands / native events
              |
       State coordinator
       observed state + intent + layout memory
              |
       Pure layout engine
       tree -> desired rectangles and focus order
              |
       Operation scheduler
       Space sequencing + per-app frame coalescing
              |
       macOS adapters
       AX / window metadata / private Spaces / input gestures
              |
       observations back to coordinator
```

One serialized coordinator owns logical state. Slow synchronous AX work runs through bounded per-app execution, not on the UI path. Keep private calls behind capability checks and narrow interfaces. Separate normal windows, floating windows and transients. Identity must include window/process lifetime considerations because numeric IDs can be reused.

Keep desired geometry, observed geometry and last accepted operation generation separate. Delayed notifications must not roll back newer intent. Do not expose mutable OS state as truth merely because a setter returned success. Use targeted observations and bounded reconciliation, rather than constant whole-desktop polling or repeated focus stealing.

## Verification and acceptance

Use Safari, Finder, a terminal and an Electron app. Record app versions, OS build, display geometry and relevant Spaces/Dock settings for each run. Geometry tests cannot prove that WindowServer displayed the intended result; live visual checks are required.

| Scenario | Observable success |
|---|---|
| Repeated fast switching, including reversals | Settles on latest requested Space; no delayed jump after input stops. |
| One app with windows on both Spaces | Moving/focusing one does not hide or relocate its sibling. |
| Move-only versus move-and-follow | Space membership and active desktop match the chosen operation. |
| Open/close during switching | Each surviving window has one correct tree entry; no lost or phantom tile. |
| Cmd-Tab, Dock activation, Mission Control | Native activation remains usable; no focus tug-of-war or desktop corruption. |
| Accordion cycling and mode toggles | Correct child is frontmost; geometry and ordering remain stable. |
| Dialogs, sheets and native tabs | Prompts remain reachable; inactive native tabs do not create duplicate tiles. |
| Minimum-size/fixed-size window | Stable bounded fallback; no persistent resize oscillation. |
| Slow/unresponsive app | Other apps and emergency disable remain responsive. |
| Disable/quit during pending operations | Queued work cannot reapply; reachable windows regain recorded frames where valid. |
| Force termination and next launch | Windows remain reachable through native Spaces; recovery offered without relying on recycled IDs. |
| Sleep/wake or managed-display disconnect | Pause/reconcile safely; never apply stale off-display coordinates. Full multi-display layout remains deferred. |

Instrument command receipt, dispatch, observed completion, Space membership, focus and requested/observed frames. Measure median/p95 end-to-end latency and failures rather than quoting API submission time or third-party performance claims. Do not invent a latency target before obtaining a baseline; the acceptance decision includes whether repeated interaction actually feels immediate and predictable.

Pure tests should cover insertion axes/ties, stable topology, removal, accordion geometry/order and size-pressure behavior. State/scheduler tests should cover stale events, latest-target coalescing, transfer sequencing and disabling mid-operation. Use live fixture apps and representative real apps to test OS behavior; mocks alone cannot validate private capabilities.

## Recovery policy

Snapshot only what kex needs for recovery. Journal original membership/frames before mutation, plus enough lifetime identity to avoid restoring another window that reused an ID. A recovery journal is not user-facing session persistence.

On normal disable/quit, cancel outstanding work and restore original frames on still-valid displays/Spaces where feasible. If explicitly moved windows are to return to their original Spaces, that action must use a confirmed transfer capability; the exact normal-exit membership policy is still open. Do not create/delete Spaces or close apps to simulate recovery. If an original display/Space is gone, preserve a reachable placement and report what could not be restored. After a crash, reconcile live identities before offering restoration.

## Out of scope for version one

- Niri-style infinite scrolling, cross-monitor clipping or a custom compositor.
- Screen-captured interaction, proxy animations, virtual monitors or opaque edge masks.
- Corner parking as the normal workspace mechanism.
- Dock injection, SIP changes or a privileged edition.
- Automatic native-Space creation/deletion/reordering or exact-count enforcement.
- Multi-display tiling, overview, saved user sessions, themes, scripting/plugins, elaborate settings or status bars.
- App Store distribution, updater and production packaging polish.
- Changes to Tuna or a requirement that Tuna be running.

## Open decisions and stop conditions

The target OS range, app build setup, keybindings, detailed accordion strip geometry/orientation, nested-container selection, focus-follows-mouse, automatic overflow policy and exit-time Space restoration policy remain open. Decide only what each phase needs. Direct distribution is the likely path if private APIs remain; signing/notarization does not make those calls public or stable.

Proceed beyond the spike only if switching, transfers, focus, frame settlement and recovery work reliably with SIP on. If animation is poor, keep immediate placement. If native-Space transfers are unreliable, report that separately from layout success and revisit the backend explicitly. A beautiful demo that fails on same-app windows, dialogs or repeated input does not validate the design.

## Research archive

The appendices below preserve findings and citations as of 24 September 2026. They are not live compatibility guarantees. Appendix A predates the decision to drop scrolling and contains superseded prototype recommendations; Appendix B predates the standalone-project correction and occasionally calls the future project Tuna. Read both as evidence and alternatives, with the kex decisions above taking precedence.

## Appendix A — API and compositor feasibility investigation

### Building a Niri-like window manager on macOS

Investigation date: September 24, 2026.

**Verdict:** A substantially better tiling experience is feasible, including an alternative to parking windows in screen corners. A fully supported replacement compositor for arbitrary Mac applications is not exposed by the APIs examined. The strongest near-term approach combines native Spaces, a small private-API adapter, Accessibility, and optional GPU-rendered transition previews. Fully continuous, interactive Niri-style scrolling remains an experiment, not an established capability of that combination.

This investigation covers Apple documentation through macOS 27, installed SDK headers, current AeroSpace and yabai source, and a read-only inspection of this Mac's SkyLight runtime. No window-management operations were executed and no system settings were changed. Source inspection and API presence are distinguished below from behavior verified by running a prototype.

**Why Linux feels different**

Hyprland and Niri operate at the compositor layer. In Wayland, applications deliver content to the compositor, which participates directly in presentation and input delivery. A compositor can change where a surface is drawn without asking the application to change its document layout every animation frame. Clients still control how quickly they render new content; compositor ownership does not make application redraw instantaneous. [Wayland architecture](https://wayland.freedesktop.org/architecture.html).

On macOS, Accessibility lets an external process request changes from applications. It does not make that process the desktop compositor. Apple documents failures for unsupported attributes, unimplemented accessibility support, and failed interprocess messaging. That creates fundamentally different latency and coordination constraints. [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue).

The missing capability is authority over other applications' presentation and input, not merely a faster implementation language or layout algorithm.

**What the newest public APIs provide**

| API family | Useful capability | Boundary relevant to this project |
|---|---|---|
| Accessibility: AXUIElement, AXObserver | Discover accessible windows; observe events; request position, size, focus, and minimization where supported | Requests depend on the target application; no documented atomic desktop-wide layout transaction |
| Quartz Window Services | Obtain WindowServer window IDs and window metadata | Enumeration does not confer ownership or arbitrary control |
| NSRunningApplication | Activate, hide, and unhide an application | Hiding is application-wide, unsuitable for splitting its windows among workspaces |
| NSWindow and SwiftUI window APIs | Control windows belonging to the implementing app | A foreign window ID cannot be turned into an owned NSWindow |
| NSWindow.CollectionBehavior | Specify participation in Spaces, full screen, and Stage Manager | Participation preferences, not a replacement Stage Manager or workspace controller |
| ScreenCaptureKit | Capture individual windows and render their content elsewhere | Produces captured content; does not transfer window ownership or input routing |
| Metal, Core Animation, CADisplayLink | Render and animate the manager's own presentation at display cadence | Cannot by themselves move or clip a foreign live window |
| CGEvent and event taps | Observe/filter supported input and synthesize events, subject to permissions | Not a documented compositor seat or arbitrary foreign-surface input mapping |

Relevant references: [Quartz Window Services](https://developer.apple.com/documentation/coregraphics/quartz-window-services), [App Windows](https://developer.apple.com/documentation/appkit/app-windows), [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication), [collection behaviors](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct), [WindowProxy](https://developer.apple.com/documentation/swiftui/windowproxy), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).

I inspected Apple's June 2026 AppKit update summary and macOS 27 release notes, plus the installed AppKit and ScreenCaptureKit headers. The new AppKit work includes gestures, Sidecar touch support, scrolling, controls, and observation. The release notes add tiling-menu support for standalone open/save panels and fix a Mission Control/full-screen window-loss issue. I found no documented third-party compositor registration or general cross-application window-management authority in these materials. This is a bounded finding, not proof that every private facility has been exhausted. [AppKit updates](https://developer.apple.com/documentation/updates/appkit), [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).

In particular, Apple's built-in tiling does not establish a public API for supplying your own system-wide tiling policy. Likewise, SwiftUI's window placement and proxy APIs concern the application's own windows.

**The important recent change: native Spaces with SIP enabled**

In May 2026, yabai incorporated an alternative way to move windows between native Spaces. Its maintainer reports it working on Tahoe 26.4; the originating report names 26.4.1. The implementation constructs `SLSBridgedMoveWindowsToManagedSpaceOperation` with `initWithWindows:spaceID:` and submits it through an internal SkyLight bridge. This is real Space reassignment, rather than moving a window beyond the screen boundary. [Issue 2788](https://github.com/asmvik/yabai/issues/2788).

The implementation locates an internal C++ symbol using Mach-O symbol lookup. It is not simply a public API that Apple forgot to advertise. A usable class name, a callable bridge, permission to execute an operation, and correct synchronization with Dock are separate requirements. [Initialization source](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/yabai.c#L149).

Fast Space switching also gained a SIP-enabled path in April 2026. The current fallback synthesizes Dock swipe events with a very large velocity. It may send multiple swipes for a nonadjacent destination and perform display-focus adjustments. This is clever and potentially useful, but should not be described as an official instant-Space-switch API. [Issue 2780](https://github.com/asmvik/yabai/issues/2780), [implementation](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space_manager.c#L927).

Consequently, historical statements that all useful Space control requires disabling SIP are too broad. Equally, SIP being enabled does not make an API public, stable, sandbox-compatible, or App Store eligible.

**What was verified locally**

The inspected machine reports macOS 27.0, build 26A428, with SIP enabled. A small read-only program loaded SkyLight into its own process and enumerated Objective-C classes and method metadata. It found:

| Runtime class | Interesting method | Evidence strength |
|---|---|---|
| SLSBridgedMoveWindowsToManagedSpaceOperation | initWithWindows:spaceID: | Present locally; operational precedent in yabai on 26.4 |
| SLSBridgedManagedDisplaySetCurrentSpaceOperation | initWithDisplayIdentifier:spaceID: | Present; execution rights and Dock coordination untested |
| SLSBridgedHideSpacesOperation / SLSBridgedShowSpacesOperation | initWithSpaces: | Present; execution rights and semantics untested |
| SLSBridgedSpaceSetTransformOperation | initWithSpaceID:transform:options: | Present; permissions and presentation/input behavior untested |
| SLSBridgedSpaceSetShapeOperation | initWithSpaceID:shape: | Present; clipping meaning and permissions untested |
| SLSBridgedSpaceCreateOperation | initWithOptions:values: | Present; not proof of ordinary Mission Control desktop creation |

These are promising targets for a controlled prototype. None of the latter entries establishes that we can build a compositor without privileges. A generic internal Space may differ from a Dock-managed desktop, and bypassing Dock state maintenance could produce inconsistent desktop behavior.

**Alternatives to AeroSpace's corner trick**

AeroSpace deliberately implements its own workspaces to avoid limitations of native Spaces. It moves inactive windows to bottom corners and documents visible slivers and constraints on monitor arrangement. This is a deliberate compromise, not evidence that macOS has no other internal hiding mechanism. [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide).

| Approach | Advantage | Principal cost |
|---|---|---|
| One real Space per workspace | WindowServer handles visibility; no corner slivers | Native desktop lifecycle, switching, and activation behavior remain involved |
| Dedicated inactive Space for parked windows | Potentially supports many logical workspaces using a small number of native Spaces | Batch transfers, focus, transient windows, and interruption recovery need validation |
| Minimize individual windows | Supported through Accessibility on compatible windows | Changes user minimization state; animation/restoration behavior; capture pauses when minimized |
| Hide applications | Public API and simple | Hides every window of that application, including ones wanted elsewhere |
| Occlude windows behind a manager-owned backdrop | Can conceal layout changes without foreign-window alpha control | Windows still exist in that Space; popups, focus, stacking, Mission Control can reveal the illusion |
| Put windows on a virtual display | Gives windows genuine offscreen display coordinates | Introduces display lifecycle, scale, focus, resource, and recovery problems; not ownership of surfaces |
| Privileged WindowServer operations through Dock | More direct foreign-window presentation controls | Injection, reduced SIP protections, and OS-specific maintenance |

The parked-Space approach is a design hypothesis. It should be compared with one-native-Space-per-workspace before committing. It could replace spatial hiding with actual workspace membership while retaining custom logical workspaces, but may trade corner artifacts for movement and activation races.

**Can ScreenCaptureKit provide the smoothness?**

It can supply the visual part. Apple documents that a single-window capture can include the complete window while it is occluded or offscreen. Minimizing pauses the stream. Therefore an overview or animated transition can render window textures without moving every real window on every display frame. Capture permission is an additional product requirement. [Apple's ScreenCaptureKit deep dive](https://developer.apple.com/videos/play/wwdc2022/10155/).

The practical design is to animate previews during navigation, then hand control back to real windows when the viewport settles. GPU clipping can make previews appear to scroll beyond a monitor edge. The actual windows must already be concealed or occluded underneath; capture alone does not solve that.

Continuously operating applications through captured replicas is much harder. A screenshot or video surface is not an interactive NSWindow. Input forwarding has to reconcile coordinate mapping, app activation, menus, sheets, drag-and-drop, input methods, accessibility geometry, and pointer gestures. Capturing a window does not give an API to reparent it into a new interactive scene.

Capture behavior for windows parked on inactive Spaces, protected content, interruption, and application throttling should be measured explicitly. Do not generalize the documented offscreen-window behavior into a guarantee that every hidden or inactive window supplies continuously fresh frames.

There is precedent for separating presentation from layout: yabai builds image-backed proxy windows for its animations. Its privileged component hides originals during the proxy animation. Final application geometry still uses Accessibility. This demonstrates both the value of the technique and why hiding the originals is a separate capability. [Proxy implementation](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/window_manager.c#L462), [privileged swap](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/osax/payload.m#L813).

**What disabling SIP would change**

yabai's scripting addition injects into Dock, whose WindowServer connection has special authority over windows belonging to other applications. This enables controls such as foreign-window alpha, ordering, transforms, and other desktop operations unavailable through ordinary ownership. Running an arbitrary helper as root is not the same as possessing that connection. [Maintainer's explanation](https://github.com/asmvik/yabai/issues/1863).

This route is much closer to the desired presentation control, but still does not replace the application's own resizing and drawing behavior. It also depends on private system implementation details. The relevant product choice is whether such a privileged edition is acceptable; it should not be silently made the prerequisite for the normal edition.

**Architecture I would prototype**

Keep the layout model independent of the operating-system implementation: ordered columns, window widths, workspace membership, floating exceptions, viewport offset, and desired focus. Compute the desired visible set before asking macOS to change anything.

Use one serialized state coordinator, with bounded per-application Accessibility work so an unresponsive app does not freeze the manager. Separate requested geometry from observed geometry; delayed notifications must not undo newer requests. Reconcile after interruptions and avoid retry loops that continuously fight application size constraints. Native sheets, dialogs, and utility panels need explicit relationships rather than being treated as ordinary tiles.

Put all private operations behind a small capability-checked adapter. The initial implementation should use the demonstrated window-to-Space operation. Compare native-workspace switching with a parked-Space implementation. Pre-created desktops avoid making reliable desktop creation a prerequisite. Each successful operation should be confirmed by observed state, not inferred from submission alone.

Add a renderer only after visibility and focus work reliably. Capture previews around a transition, animate them with Metal or Core Animation, commit final real-window geometry, then reveal the real windows. Keep normal typing, selection, menus, and dragging directed at the actual application windows once the transition ends.

Recovery belongs in the initial design: persist original Space membership and geometry before moving anything; identify windows with process/window lifetime in mind; restore reachable windows after a crash or disable action; rebuild after display changes. Windows parked in native Spaces remain discoverable through native desktop navigation, which is preferable to an invisible, unrecoverable state.

For distribution, plan a directly distributed macOS app with the required user-granted permissions. Private APIs conflict with App Store guideline 2.5.1. Signing/notarization and permission compatibility must be tested for the actual build; they do not convert private behavior into a compatibility guarantee. [App Review guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

**Experiments that decide whether this is worth building**

1. **Window-to-Space transfer:** On SIP-enabled macOS 27, move disposable test-app windows into an existing inactive Space and back. Test a batch, multiple windows of one application, and sheets. Confirm membership and focus; class existence is insufficient.
2. **Visibility and handoff:** Compare per-workspace Spaces, a parked Space, and a temporary backdrop. Record flashes, unexpected Space switches, ordering, and app reactivation. Test Cmd-Tab and clicking Dock icons.
3. **Native operation candidates:** In a disposable test session, investigate bridged current-Space, show/hide, transform, and shape operations independently. Verify privileges, WindowServer outcome, Dock consistency, and input alignment. Reject partial successes that corrupt normal desktop behavior.
4. **Frame delivery:** Capture visible, occluded, inactive-Space, and minimized windows. Include native apps, Electron, browsers with video, and modal panels. Measure frame freshness, latency, memory, and energy.
5. **Scrolling prototype:** Implement a small column layout with interruptible preview animation and real-window handoff. Validate reversed gestures and input during transitions. At 120 Hz the presentation budget is about 8.3 ms, but do not require Accessibility or application redraw to finish within each frame.
6. **Recovery:** Terminate the manager during transfers; disconnect displays; sleep and wake; restart Dock; open Mission Control. Every managed window must remain reachable or recoverable.

Proceed if Space transfers, focus, and handoff are stable enough to remove visible glitches. If previews are smooth but interaction is fragile, ship discrete keyboard navigation and an overview first. If continuous scrolling with live interaction is essential, budget for the privileged route or conclude that the current macOS boundary prevents the desired fidelity.

**Recommendation**

Build a small feasibility prototype around the new bridged Space operation before implementing a full manager. The key question is no longer whether corner parking is avoidable: there is credible implementation evidence that it is. The unresolved question is whether hiding, capture, final geometry, and focus can be coordinated well enough to reproduce the experience you liked in Niri or Hyprland.

Source snapshots inspected: yabai `dd845723416f5fe92af49fad5ebab00369e07edd`; AeroSpace `5f08f9c0c9daea6bb0f652da71d80a02e0b3f6cf`. The runtime inspection established API metadata presence only, not execution success or performance.

## Appendix B — Complete window-manager survey and catalog

### macOS window-manager approaches

Research date: 24 September 2026. Scope: native macOS application windows, with SIP enabled as the design constraint.

This survey catalogs **84 projects/products**, including adjacent utilities and historical references. **31 have targeted implementation inspection**; the others have publisher documentation or are explicitly marked unresolved leads. This is a broad best-effort inventory, not a claim that every small repository or discontinued Mac utility has been found. Nothing was installed or run as a window manager, and Tuna was not changed. Source inspection establishes what code attempts, not that every private call works on every macOS release.

The useful result is that dozens of products reduce to a few window-control strategies. Your proposed **native Spaces + Tuna's fast swipe switching + widest-axis BSP + accordion** remains a credible SIP-on architecture. Several existing projects supply parts of it already. There is no demonstrated general-purpose foreign-window clipping primitive in the implementations inspected.

#### The six approaches

| Strategy | Representative projects | What actually happens | Consequence for Tuna |
|---|---|---|---|
| Native Spaces | yabai, Amethyst, Glide, mimi, current bobrwm; KiwiDesk is Space-aware | macOS owns which desktop a window belongs to. The manager arranges visible windows and may use private Space queries/transfers. | Best fit for your fast-swiping backend; no need to park whole inactive workspaces at screen corners. |
| Virtual workspaces by parking | AeroSpace, Rift, GlazeWM, komorebi, Yashiki, Parket, HyprMac, WinMux, WindowRanger | Retain ordinary windows but move them mostly beyond an edge/corner. | Fast and independently configurable, but inherits slivers, display geometry and activation complications. |
| Whole-application hiding | FlashSpace, Tatami | Hide/unhide a running application, typically affecting all its windows. | Clean when apps belong to workspaces; unsuitable as a general way to isolate two windows from the same app. |
| Per-window minimization | Zonogy | Use actual native minimized state, then restore/raise the chosen window. | Real disappearance with native minimization semantics, focus side effects and possible animation—not continuous scrolling. |
| Overlapping windows/stacks | AeroSpace accordion; fixed-region stack products | Keep windows in the viewport and control their geometry and ordering. Product-specific tab implementations may additionally park or minimize extras. | Good fit for avoiding Niri's clipping requirement; minimum sizes and focus ordering remain. |
| Virtual displays + capture | orcv | Create actual virtual monitors, place windows there, and display captured desktops in a canvas. | A possible laboratory for a custom viewport, but materially changes input, display topology and rendering. |

The categories can coexist in one application. Scrolling is a layout policy, not a seventh hiding primitive. A manager can scroll visible windows while parking completely hidden columns; native Spaces only solve invisibility between desktops, not partial clipping within one desktop.

#### What changed our understanding

**There are already much closer peers than the usual three.** Rift includes both accordion and BSP alongside scrolling; OmniWM already offers Niri-style columns and Hyprland-style Dwindle. The missing piece is not discovering a splitting algorithm. It is choosing the workspace backend and making focus, geometry and transitions reliable.

**SIP-on native-Space control deserves serious consideration.** mimi and bobrwm contain synthetic Dock gesture implementations and private bridged window transfer paths. The current yabai code also matters; old comparisons saying all Space control requires its injected scripting addition are too broad. These remain private, version-sensitive mechanisms, not newly documented Apple APIs.

**Animations do not automatically require screenshot proxies.** Glide and Rift send position updates to real application windows through AX. Glide coalesces writes per app and deliberately avoids continuous resize animation. OmniWM additionally has direct SkyLight movement paths. Owning WindowServer is still different from asking it—or the application—to move a window.

**The offscreen constraint is real, but “Niri impossible” is too coarse.** Several usable approximations exist. What remains unproven here is seamless partial clipping of arbitrary app windows, without visible remnants, opaque masks, native minimization, moving to other Spaces, or moving onto other displays.

**Directory classifications are unreliable.** bobrwm's current native-Space implementation contradicts its directory description. Tiles officially supports drag snapping despite a directory claim to the contrary. HyprSpace/Hiro links redirect to OmniWM; these are not three independent engines. The two products called HyprMac/hyprmac have different publishers. A public GitHub releases repository also does not imply open application source.

#### Detailed implementation notes

##### Native Spaces: mimi, bobrwm and yabai

mimi is the clearest separation of mechanism and policy: its Objective-C Space layer synthesizes Dock gestures and resolves the private asynchronous bridged window-management operation; an optional daemon sends a window description to a user-supplied layout program and applies the returned rectangles. Its example layouts include Dwindle/BSP and scrolling. This closely matches keeping Tuna's existing Space switching while adding a layout engine.

bobrwm's current architecture binds logical workspaces to native Space IDs. Its code uses a swipe velocity of 2000 and waits for observed Space transitions rather than treating a request as completed. It also contains private native-Space create/destroy implementations. Those are valuable research leads, **not runtime-verified promises for your Mac**. Its exact-count Space reconciliation is a product choice we should not copy implicitly.

yabai remains the reference for AX frame setting, private window identity/focus and Space bridging. Its privileged scripting addition is a separate capability tier; sophisticated foreign-window effects should not be assumed available just because its ordinary tiling works with SIP enabled.

[mimi Space backend](https://github.com/y3owk1n/mimi/blob/1107d3e16d4e699537e2229844f5c894d3180b04/internal/native/space.m#L425) · [bobrwm Space backend](https://github.com/bobrwm/bobrwm/blob/537627f83f7d3a7ac645fc60303c1d4bc558b4e4/src/skylight.zig#L170) · [bobrwm model](https://github.com/bobrwm/bobrwm/blob/537627f83f7d3a7ac645fc60303c1d4bc558b4e4/ARCHITECTURE.md) · [yabai Space manager](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space_manager.c)

##### Glide: latency architecture worth borrowing

Glide keeps native Spaces and distributes app interaction into per-app actors. Animation frames are coalesced so a slow app does not accumulate every obsolete intermediate rectangle. The inspected path writes positions through AX, defers expensive sizing, and performs a final fixup/readback. Its animation code explicitly explains why it does not continuously animate size.

The lesson is practical: move-only animation can be worthwhile even without compositor control. A responsive layout model plus bounded asynchronous writes may matter more than the language chosen. Tuna would still need to decide how to handle an app that rejects sizes or stops responding.

[Animation policy](https://github.com/glide-wm/glide/blob/3a92f97d2b20167b26f9274cdd6a90ca504def53/src/actor/reactor/animation.rs#L175) · [Coalesced frame writer](https://github.com/glide-wm/glide/blob/3a92f97d2b20167b26f9274cdd6a90ca504def53/src/actor/app.rs#L345)

##### Rift: the most relevant broad layout comparison

Rift builds on Glide and expands the layout choices to include i3-style layouts, BSP, master-stack, scrolling and accordion. Its hidden-window placement chooses between bottom corners, retains a one-point reveal and considers adjacent screens. Its AX layer still writes AXPosition and AXSize for foreign windows.

For us, it is a reference for combining layout policies and for state/event handling, not evidence that edge parking has been eliminated. Private transaction code used for manager-owned surfaces must not be mistaken for arbitrary control over other apps' windows.

[Layouts and features](https://github.com/acsandmann/rift/blob/c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1/README.md) · [Hidden placement](https://github.com/acsandmann/rift/blob/c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1/src/model/hidden_window_placement.rs) · [AX writes](https://github.com/acsandmann/rift/blob/c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1/src/sys/axuielement.rs#L308)

##### OmniWM: our layout combination already exists

OmniWM offers both scrolling containers and Dwindle, with tabs/groups and its own workspace shell. It includes private transaction-based movement of foreign-window IDs, frame-readback/diagnostic machinery, AX sizing and parking-edge masks. Thus “every foreign-window move must take the slowest AX route” is too strong; some implementations try faster private positioning.

That does not make it a compositor. The parking mask and multi-monitor guidance are evidence of the remaining visibility problem. We should compare the Dwindle policy and animation scheduler, while keeping native-Space ownership as a separate architectural decision.

[Frame positioning](https://github.com/OmniNull/OmniWM/blob/df8890ebd26f0b92f774f93449906dc1f79bd6e0/Sources/OmniWM/Core/Ax/AXManager+FrameVisibility.swift#L144) · [Private symbols](https://github.com/OmniNull/OmniWM/blob/df8890ebd26f0b92f774f93449906dc1f79bd6e0/Sources/OmniWM/Core/SkyLight/SkyLightTransactionFunctions.swift) · [Project documentation](https://github.com/OmniNull/OmniWM/blob/df8890ebd26f0b92f774f93449906dc1f79bd6e0/README.md)

##### Nehir: read the final resolution, not just the failed experiments

Nehir's investigation records failed ordering, transform and clipping attempts on foreign windows, including calls returning success without producing the desired visual effect. Its July resolution says the fixed-Dock case was addressed by retaining at least one point inside the usable visible frame and covering the remaining strip/Dock band with an opaque panel behind the Dock.

This is an important correction to earlier passages in the same document that describe the Dock edge as unbeatable and propose virtual-display parking. The final shipping explanation is **parking plus a shield**, not a virtual display or true order-out. The result can look clean, but the opaque band is a product compromise. The trace/visual testing is the maintainer's reported evidence; I did not reproduce it.

[Failure log and final resolution](https://github.com/apphane-dev/nehir/blob/f097f35a22c463b343c16e29327bd317b7573171/docs/offscreen-clamp-fix.md)

##### Scrolling alternatives: Paneru, PaperWM, Defi, KiwiDesk, TrimWM and ScrollWM

These illustrate different policies around the same physical boundary. Paneru exposes sliver width/height. PaperWM documents retained left/right margins. Defi verifies parked AX positions and retries a bounded number of times instead of trusting a successful setter. KiwiDesk's scrolling layout explicitly models visible slivers. TrimWM uses a simple one-point left-edge reveal and removes animation complexity. ScrollWM uses teleport-style navigation and maintains separate strip state per native Space, explicitly avoiding native-Space transfers.

None supplies evidence that we can feed unrestricted Niri coordinates to macOS and obtain a properly clipped viewport. Their useful contributions are interaction policy, repair strategy, and how much complexity they accept.

[Paneru configuration](https://github.com/karinushka/paneru/blob/f79b66ca34c217af1dbf779c9e2fd7a475277c99/CONFIGURATION.md) · [PaperWM limitation](https://github.com/mogenson/PaperWM.spoon/blob/82f5dde20d40cf1bdef18ab92b2b847f16f368a3/README.md) · [Defi writer](https://github.com/qeude/Defi/blob/7b3cf52a58d7a60c717a0d5d3954b0059b784747/Sources/DefiMacOS/AXFrameAccessibilityWriter.swift) · [KiwiDesk scroll geometry](https://github.com/KiwiCanopy/KiwiDesk/blob/dda1fd77b7b220c0277085dc2ab8a94df3560cc3/Sources/KiwiDeskCore/Layouts/ScrollingLayout.swift) · [TrimWM geometry](https://github.com/cornz/TrimWM/blob/8432cab1c5b779fd790474a0d735961500f5f557/Sources/TrimWM/Geometry.swift) · [ScrollWM Space invariant](https://github.com/1jehuang/scrollwm/blob/9dc7668d2ef1e7e0a8a85390ca49061ea8e4c296/Sources/WindowLab/TeleportEngine.swift#L127)

##### FlashSpace and Tatami: a different compromise

FlashSpace switches app-based workspaces with NSRunningApplication hide/unhide. Tatami adds BSP tiling to an app-oriented workspace model and also uses process-wide hide calls. That removes an application's windows cleanly without trying to park each one, but hiding one process affects its other windows too. Shared-app/multi-display behavior therefore needs explicit rules.

FlashSpace also contains corner handling for special PiP windows, so even it is not a universal “hide every individual window” solution. For Tuna, app-based workspaces would be a deliberate restriction compared with native Spaces that can contain different windows of the same app.

[FlashSpace workspace manager](https://github.com/wojciech-kulik/FlashSpace/blob/968015308d8d284a98831f90f365538a63456ee9/FlashSpace/Features/Workspaces/WorkspaceManager.swift) · [Tatami workspace manager](https://github.com/PangMo5/Tatami/blob/85633969af7f26be47ebe4211826b9713eec17ea/TatamiKit/Sources/Dependencies/WorkspaceManagerClient.swift)

##### Zonogy: minimize instead of park

Zonogy maintains persistent regions rather than dividing the whole screen whenever a new window appears. A selected region receives the next window; displaced occupants can be minimized. The source sets kAXMinimizedAttribute and restores it for activation. Its replacement code explicitly discusses focus flashes caused by minimizing a non-frontmost window.

This proves that per-window invisibility is available if we accept native minimization semantics. It does not solve a partially visible scrolling column. It is nevertheless a useful overflow option to compare against accordion, because windows keep meaningful working sizes and fixed regions remain stable.

[Window operations](https://github.com/david-soloveichik/Zonogy/blob/1c00ab41336edc14a53f7334e6b3dd3c55f11546/Sources/WindowController/WindowController+WindowOps.swift) · [Replacement behavior](https://github.com/david-soloveichik/Zonogy/blob/1c00ab41336edc14a53f7334e6b3dd3c55f11546/Sources/WindowLifecycle/SingleOccupantReplacement.swift)

##### WindowRanger and WinMux: useful refinements to parking

WindowRanger restores the destination before parking the source, only touches the involved workspaces and uses position-only writes for workspace visibility. It suppresses participating applications' own move animations during the batch. Those are concrete ways to avoid resize cost and desktop flashes, although parking remains.

WinMux builds a project/sidebar/tabbed shell around AeroSpace-derived machinery. Its layout code still calls hideInCorner for hidden content. Cross-app tabs should be understood as manager-owned UI coordinating separate native windows, not a new public API for embedding arbitrary NSWindows inside another app.

[WindowRanger design](https://github.com/AppRanger/windowranger/blob/9ffe127cc3c5e96365f401d94fbe3026240e9b66/README.md#L82) · [WinMux hidden layout](https://github.com/zimengxiong/winmux/blob/470eedbf9e6a1bfe78e8cf199053df434af77c81/Sources/AppBundle/layout/layoutRecursive.swift#L266)

##### orcv: the genuinely different experiment

orcv creates CGVirtualDisplay objects, arranges them as real displays in the macOS desktop topology and shows their contents in a zoomable canvas. Its capture path uses CGDisplayStream; it also teleports the mouse and windows between desktops. This is not merely a screenshot of a corner-parked window.

It suggests an experimental route to keeping windows entirely outside physical displays while still on a valid desktop. But a Niri-like front end would then need capture composition, input-coordinate mapping, focus/IME/popup handling and reliable recovery when virtual displays disappear. Those are inferred engineering requirements, not demonstrated solutions supplied by orcv. It is a separate research branch, not the simplest backend for the proposed accordion tiler.

[Virtual display creation](https://github.com/jasonjmcghee/orcv/blob/1e7ccf193b0dff5e7904dc9640bc45127c2d682e/orcv/VirtualDisplayManager.swift#L123) · [Display capture](https://github.com/jasonjmcghee/orcv/blob/1e7ccf193b0dff5e7904dc9640bc45127c2d682e/orcv/DisplayStreamManager.swift#L133) · [Interaction model](https://github.com/jasonjmcghee/orcv/blob/1e7ccf193b0dff5e7904dc9640bc45127c2d682e/README.md)

##### Commercial products: what the evidence can and cannot show

Moom, Swish, StackWM, Ordinary Space, Tangrid, Split and BetterStage contain useful interaction ideas: jointly resized panes, stable workareas, cross-app tabs, visual stack selection and restoration. Spencer and Lattix show native Spaces can participate in a polished workspace product. Their documentation does not expose enough implementation detail to infer a superior per-window hiding API.

Marketing words such as “native,” “instant,” “tabs,” and “workspace” are not API descriptions. “Native” may describe a Swift/AppKit UI; “workspace” may mean saved rectangles, a set of applications, a virtual parked group or an actual Mission Control Desktop. The catalog preserves those distinctions and leaves undisclosed mechanisms unknown.

[Moom](https://manytricks.com/moom/) · [Swish](https://highlyopinionated.co/swish/) · [Ordinary Space](https://wzordinaryventures.com/products/ordinary-space) · [BetterStage](https://betterstage.app/) · [Spencer](https://macspencer.app/)
#### What I would carry into the Tuna design

1. **Native Spaces remain the visibility backend.** Keep Tuna's fast swipe path. Build an explicit Space/window observation model and confirm transitions; investigate mimi/yabai/bobrwm transfers as optional private capabilities. Do not make unverified create/delete operations a requirement for the first implementation.
2. **Separate the layout tree from the backend.** A pure engine computes rectangles and focus order. On insertion, split the focused leaf along its longer dimension, with configurable ratios. Preserve existing split choices unless the user explicitly rotates/rebalances; that avoids surprise reshuffling as proportions change.
3. **Accordion is a container policy, not just another global layout.** A tree node can overlap its children and expose strips while giving the active child useful space. We need an explicit decision about whether the user chooses it or minimum-size pressure triggers it automatically; the latter is not implied by widest-axis insertion.
4. **Use real-window movement with restrained animation.** Learn from Glide's per-app concurrency/coalescing. Avoid animation queues growing behind a slow application. Resize sparingly, reconcile at the end, and provide immediate/nonanimated operation as a baseline.
5. **Model native constraints instead of repeatedly fighting them.** Distinguish requested frames from readback, recognize fixed-size windows and native tab groups, and treat dialogs as transients. Minimum-size overflow should select a defined layout behavior, not cause an endless resize loop.
6. **Keep parking out of the normal workspace path.** It might still be useful for a narrowly defined scratchpad, but native Spaces can own ordinary workspace invisibility. Accordion keeps ordinary layout overflow inside the viewport.

The next useful work would be a small behavioral prototype—not a new full WM: native-Space switching and window transfer, pure widest-axis insertion, one accordion container, and frame application across a few representative apps. The hardest acceptance criteria are rapid repeated switching, two windows of the same app on different Spaces, dialogs/native tabs, app minimum sizes, display reconnects and recovery after the controller exits. Nothing in this survey substitutes for those live tests.

#### Complete catalog

**Source** means targeted relevant implementation was inspected, not a comprehensive audit. **Docs** means publisher documentation/README only, even if source is available. **Lead** means found but insufficient primary detail was retrievable. No row should be read as a verified macOS 27 compatibility claim. Proprietary APIs are unknown unless explicitly documented or traced in source.

##### Automatic tilers and workspace managers

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace/blob/5f08f9c0c9daea6bb0f652da71d80a02e0b3f6cf/README.md) — Source | i3-style tree; tiles and overlapping accordion; virtual workspaces using corner parking. | Excellent tree and accordion reference; virtual workspaces retain visible-edge compromises. |
| [yabai](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space_manager.c) — Source | Native Spaces; BSP, stack and float. AX frames; private Space bridge and swipe paths; optional injected scripting addition. | Separate SIP-on core and newer Space operations from privileged effects and scripting-addition features. |
| [Amethyst](https://github.com/ianyh/Amethyst/blob/6508ee2cacf8f9b357e1a3249a8f28ba5c94db2a/Amethyst/Model/Window.swift) — Source | Native Spaces with xmonad-style layout selection; AX/Silica frame operations and private focus assistance. | A native-Space tiler need not replace the workspace system; layout switching is independent of it. |
| [Glide](https://github.com/glide-wm/glide/blob/3a92f97d2b20167b26f9274cdd6a90ca504def53/src/actor/app.rs) — Source | Native-Space tiler; per-app actors, coalesced AX writes, animated positions with deferred final correction. | Useful concurrency and latency design; avoids continuously animating expensive size changes. |
| [Rift](https://github.com/acsandmann/rift/blob/c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1/src/model/hidden_window_placement.rs) — Source | Glide-derived Rust tiler; multiple layouts including BSP, scrolling and accordion; virtual-workspace corner parking. | Closest broad layout toolbox; still uses one-point reveal placement for hidden windows. |
| [OmniWM](https://github.com/OmniNull/OmniWM/blob/df8890ebd26f0b92f774f93449906dc1f79bd6e0/Sources/OmniWM/Core/Ax/AXManager+FrameVisibility.swift) — Source | Niri columns plus Dwindle BSP, tabs, private SkyLight positioning, AX geometry, parking masks. | Already combines scrolling and widest-axis splitting; the masks are concealment, not foreign-window clipping. |
| [Nehir](https://github.com/apphane-dev/nehir/blob/f097f35a22c463b343c16e29327bd317b7573171/docs/offscreen-clamp-fix.md) — Source | OmniWM-derived scrolling; visible-frame sliver parking and an opaque shield behind a fixed Dock. | Most useful published failure log for offscreen hiding; its final resolution supersedes earlier failed attempts. |
| [Paneru](https://github.com/karinushka/paneru/blob/f79b66ca34c217af1dbf779c9e2fd7a475277c99/CONFIGURATION.md) — Source | Rust scrolling strip with gestures; configurable edge-sliver dimensions. | Treats retained edges as part of the implementation rather than solving true clipping. |
| [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon/blob/82f5dde20d40cf1bdef18ab92b2b847f16f368a3/README.md) — Source | Hammerspoon/Lua scrolling columns and vertical stacks; native-Space integration; visible margins. | Explicitly documents inability to place windows wholly offscreen. |
| [Defi](https://github.com/qeude/Defi/blob/7b3cf52a58d7a60c717a0d5d3954b0059b784747/Sources/DefiMacOS/AXFrameAccessibilityWriter.swift) — Source | Swift scrolling columns, per-display virtual workspaces and overview; AX parking with readback and bounded retry. | Distinguishes requested positions from achieved ones; preview capture is optional, not the tiling backend. |
| [KiwiDesk](https://github.com/KiwiCanopy/KiwiDesk/blob/dda1fd77b7b220c0277085dc2ab8a94df3560cc3/Sources/KiwiDeskCore/Layouts/ScrollingLayout.swift) — Source | Native-Space-aware layouts and profiles with Lua; scrolling edge slivers and AX-backed window control. | Useful layout variety and degradation design; public source is BSL, not unrestricted permissive reuse. |
| [TrimWM](https://github.com/cornz/TrimWM/blob/8432cab1c5b779fd790474a0d735961500f5f557/Sources/TrimWM/Geometry.swift) — Source | Small BSP/scrolling tiler; no animation; logical workspaces park at left edge with one-point reveal. | A deliberately small implementation exposes the basic tradeoffs; current management is main-display-only. |
| [ScrollWM](https://github.com/1jehuang/scrollwm/blob/9dc7668d2ef1e7e0a8a85390ca49061ea8e4c296/Sources/WindowLab/TeleportEngine.swift) — Source | AX scrolling with teleport navigation, virtual workspace strips inside independent native-Space layers. | It explicitly does not transfer windows across native Spaces; stashing a strip often means storing model state. |
| [komorebi for Mac](https://github.com/LGUG2Z/komorebi-for-mac/blob/bdf10452f10ebf15ec1978cb05d0aac79ef5611f/komorebi/src/window.rs) — Source | Rust tiler port; caches frames and parks inactive windows in bottom corners. | Windows-platform pedigree does not bypass macOS hiding restrictions; check source-available licensing. |
| [GlazeWM for macOS](https://github.com/glzr-io/glazewm/blob/5709ad0a3c7c386bbc3e38166a865ffc12937515/packages/wm/src/commands/general/platform_sync.rs) — Source | Cross-platform i3-style tiler; macOS backend uses AX frames and one-point corner parking. | macOS support shipped in v3.10; Windows cloaking capabilities must not be attributed to its Mac backend. |
| [bobrwm](https://github.com/bobrwm/bobrwm/blob/537627f83f7d3a7ac645fc60303c1d4bc558b4e4/src/skylight.zig) — Source | Zig BSP/monocle; current native-Space backing, synthetic Dock swipes, private bridged moves and create/destroy paths. | Current source differs from directory descriptions; observe confirmed Space transitions before accepting intent. |
| [mimi](https://github.com/y3owk1n/mimi/blob/1107d3e16d4e699537e2229844f5c894d3180b04/internal/native/space.m) — Source | Native Spaces via synthetic Dock gestures and private window-transfer bridge; layouts are external JSON programs. | Closest match to Tuna backend direction; layout policy can be developed independently of OS control. |
| [Yashiki](https://github.com/typester/yashiki/blob/f36b0c358ac2316504938e8238f09d10480cd187/yashiki/src/core/state/layout.rs) — Source | Tag-based virtual workspaces; external layout programs; per-display corner hiding and re-hide reconciliation. | Tags permit richer membership; logical flexibility does not change the underlying hiding primitive. |
| [Parket](https://github.com/basuev/parket/blob/4adb3ec0cf46734e3e7485af0fd28a6f95b1bca1/README.md) — Source | Small Swift master-stack/monocle WM; nine virtual workspaces per display; screen-aware offscreen corners. | Useful reference for minimal scope and native-tab grouping; avoids SIP changes. |
| [Tatami](https://github.com/PangMo5/Tatami/blob/85633969af7f26be47ebe4211826b9713eec17ea/TatamiKit/Sources/Dependencies/WorkspaceManagerClient.swift) — Source | App-assigned workspaces plus BSP tiling; process-wide hide/unhide with private focus/visibility assistance. | Clean app hiding works when a workspace owns the app; independent windows of one process are harder. |
| [FlashSpace](https://github.com/wojciech-kulik/FlashSpace/blob/968015308d8d284a98831f90f365538a63456ee9/FlashSpace/Features/Workspaces/WorkspaceManager.swift) — Source | Fast app-based workspaces via application hide/unhide; special handling for PiP includes corner hiding. | Distinct from AeroSpace: app ownership is the fundamental restriction, not just a layout preference. |
| [HyprMac — zacharytgray](https://github.com/zacharytgray/HyprMac/blob/fe24abfe1009bde584b82f859e6cee071ca6f994/HyprMac/Core/WorkspaceManager.swift) — Source | Hyprland-inspired BSP/dwindle and virtual workspaces; inactive windows parked in a corner. | Useful small Dwindle implementation; no new hiding authority. |
| [WindowRanger](https://github.com/AppRanger/windowranger/blob/9ffe127cc3c5e96365f401d94fbe3026240e9b66/Sources/Windows/WorkspaceEngine.swift) — Source | Virtual workspaces with freeform, tiled and accordion modes; restores destination before parking source. | Position-only switching and suppressed app move animations reduce work and desktop flashes. |
| [WinMux](https://github.com/zimengxiong/winmux/blob/470eedbf9e6a1bfe78e8cf199053df434af77c81/Sources/AppBundle/layout/layoutRecursive.swift) — Source | AeroSpace-derived tiling with projects, sidebar and cross-app tab groups; corner hiding remains. | A richer shell around the same window primitives, not a separate compositor. |
| [Zonogy](https://github.com/david-soloveichik/Zonogy/blob/1c00ab41336edc14a53f7334e6b3dd3c55f11546/Sources/WindowController/WindowController+WindowOps.swift) — Source | Persistent tiling zones, selected destination for new windows, snapshots; displaced windows can be minimized. | A genuinely different visibility tradeoff: real per-window minimization, with native focus/animation side effects. |
| [Tangrid](https://tangrid.app/) — Docs | Automatic tiling, tab groups, snapping and saved workspaces restored onto native desktops. | Useful tab/tiling interaction reference; precise hiding and animation internals undisclosed. |
| [ChainYourMac](https://chainyourmac.com/) — Docs | Scrolling strips per display and Space; stacks/tabs; Rust engine with SwiftUI controls. | SIP-on product; publisher acknowledges possible hidden-window corner remnants elsewhere on its site; no source audit. |
| [hyprmac — Wisp OS](https://wisp-os.com/) — Docs | Dwindle tiling, drag-to-swap and five workspaces; Swift and SIP-on according to publisher. | Separate product from zacharytgray/HyprMac; workspace hiding internals not verified. |
| [Panewright](https://www.panewright.com/) — Docs | Packages its own AeroSpace engine with JankyBorders, SketchyBar, configuration UI and ghost dragging. | Integration and lifecycle supervision; do not count it as an independent window-control engine. |
| [OttoWM](https://github.com/brennovich/ottowm) — Docs | Floating virtual workspaces on one native Space, bottom-right parking; no automatic tiling yet. | Useful deliberately non-tiling comparison; documents limited multi-display support. |
| [BetterStage](https://betterstage.app/) — Docs | Named multi-monitor stages, floating/snapping mode and TabStack panes with tabs. | SIP stays on per publisher; exact stage hiding primitive remains unverified. |
| [Ordinary Space](https://wzordinaryventures.com/products/ordinary-space) — Docs | Fixed workareas on native desktops, stacks within each, new-window placement into the active area. | Stable geometry and stack cycling may fit the accordion goal without endless repartitioning. |
| [StackWM](https://www.stackwm.org/) — Docs | Named zones, multiple windows per zone, cycling and saved scene switching. | Distinguish saved arrangements from OS Spaces; exact visibility implementation undisclosed. |
| [Emmetapp](https://emmetapp.com/) — Docs | Custom on-screen regions called spaces, with stacked windows and keyboard cycling. | Its spaces are regions, not native macOS Desktops; no evidence of new clipping capability. |

##### Virtual displays and desktop experiments

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [orcv](https://github.com/jasonjmcghee/orcv/blob/1e7ccf193b0dff5e7904dc9640bc45127c2d682e/orcv/VirtualDisplayManager.swift) — Source | Private virtual monitors arranged in a canvas; display capture and mouse/window teleportation. | Creates additional desktop territory instead of forcing windows beyond it; radically different interaction costs. |
| [TotalSpaces3 alpha](https://discuss.binaryage.com/t/can-we-help-test-total-spaces-3-if-we-have-apple-silicon/8199) — Docs | Vendor's Apple-Silicon alpha advertised SIP-on operation with Accessibility and Screen Recording. | Historical experimental lead; exact renderer and current macOS support not verified. |

##### Snapping, zones and gestures

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [Rectangle](https://github.com/rxhanson/Rectangle/blob/ef13b03827695323fd0595e15eb86c1414ce457d/Rectangle/AccessibilityElement.swift) — Source | User-triggered snap targets and shortcuts; sets AX size and position. | Good baseline for robust geometry writes; does not continuously maintain a tiling tree. |
| [Loop](https://github.com/MrKai77/Loop/blob/df26d565e07c82e156b8f1c361bdcf428f32e3a4/Loop/Stashing/StashManager.swift) — Source | Radial/gesture placement UI, shortcuts and window stashing. | Interaction design and explicit edge stashing; not a replacement workspace compositor. |
| [Rectangle Pro](https://rectangleapp.com/pro/) — Docs | Custom sizes, snap targets, window throws, saved arrangements and edge stashing. | Shows how far interaction polish can go without automatic workspace tiling. |
| [Magnet](https://magnet.crowdcafe.com/) — Docs | Keyboard and drag snapping to standard screen regions. | One-window placement model; no maintained layout tree or offscreen viewport. |
| [BetterSnapTool](https://folivora.ai/bettersnaptool/) — Docs | Edge/corner snapping, custom snap areas, shortcuts and modified window-button actions. | Flexible snap target geometry, not compositor control. |
| [BentoBox](https://bentoboxapp.com/) — Docs | Drawn tiled or freeform zones, per-display/per-Space layouts and spanning adjacent zones. | FancyZones-style manual placement with native-Space awareness. |
| [MacsyZones](https://macsyzones.com/) — Docs | Custom and overlapping zones, shift/right-click/shake snapping and keyboard Quick Snapper. | Open-source zone editor; source not audited here. |
| [TilesWM](https://github.com/denissteinhorst/tileswm-app-release) — Docs | Custom tile profiles, display-configuration detection and always-active snapping. | The public repository distributes releases/docs; do not mistake it for the application source. |
| [Tiles](https://www.sempliva.com/tiles/) — Docs | Basic drag-to-edge snapping and customizable keyboard shortcuts. | The official page contradicts directory claims that it lacks drag snapping. |
| [Lasso](https://www.thelasso.app/) — Docs | Grid selection, saved layouts, shortcuts and modifier-based move/resize. | Useful manual layout UI; no independent workspace or hiding backend established. |
| [NeoTiler](https://getneotiler.com/) — Docs | Snapping, saved workspaces and per-app automatic placement rules. | Rules automate placement without establishing continuous tree tiling. |
| [EasySnaps Window Manager](https://easysnaps.org/) — Docs | Custom zones, app-aware one-shot arrangement and profiles including app session context. | Distinguish the WM from its separate screenshot application; restoration adds app-specific automation. |
| [Split](https://splitformac.com/) — Docs | Paired regions, jointly resized divider, window stacks and side swapping. | Relevant example of minimum-size-aware paired panes; AX permission documented. |
| [Mosaic](https://www.lightpillar.com/mosaic.html) — Docs | Saved/custom layouts selected through drag overlays, shortcuts and quick layout controls. | A visual layout application rather than a continuously maintained BSP tree. |
| [SizeUp](https://www.irradiatedsoftware.com/sizeup/) — Docs | Shortcut placement, display/Space moves, restore-original-frame and AppleScript extensions. | Veteran command-based geometry model; verify Space support on target OS independently. |
| [Moom](https://manytricks.com/moom/) — Docs | Window-button palette, snapping and saved layouts for particular apps or recent windows. | Generic recent-window layouts and chained actions are useful interaction ideas. |
| [Divvy](https://mizage.com/divvy/) — Docs | Draw a rectangle on a screen grid to resize the selected window; shortcut presets. | Minimal user-controlled geometry; does not attempt hidden workspaces. |
| [Swish](https://highlyopinionated.co/swish/) — Docs | Trackpad gestures on window chrome; grid snapping, shared resize and display/Space actions. | Strong gesture semantics; proprietary internals do not prove compositor-level animation. |
| [Multitouch](https://multitouch.app/) — Docs | Maps trackpad/Magic Mouse gestures to window and system actions. | An input/action layer, not an automatic layout engine. |
| [Hummingbird](https://github.com/finestructure/Hummingbird) — Docs | Modifier-plus-pointer move and resize, similar to Unix window-manager gestures. | Lets users manipulate existing windows without hunting title bars. |
| [ShiftIt](https://github.com/citadelgrad/ShiftIt) — Docs | Keyboard-driven position/size presets; current fork of an older project. | Keep fork identity explicit rather than assuming all ShiftIt builds share compatibility. |
| [Cinch](https://www.irradiatedsoftware.com/cinch/) — Docs | Drag windows to screen edges to place them in halves or maximize. | Small historical snapping design. |
| [Tuck](https://www.irradiatedsoftware.com/tuck/) — Docs | Stashes windows at screen edges and reveals them when approached. | Makes edge concealment an explicit interaction rather than pretending windows disappeared. |
| [Align](https://apps.apple.com/us/app/align-organize-app-windows/id6480428845) — Docs | Magnetic edge snapping, shortcuts, panel/radial menu and multiple preset layouts. | Publisher's App Store description; implementation not inspected. |
| [1Piece](https://app1piece.com/) — Docs | Snapping, shortcuts, directional focus, hot corners and window switching. | Broad desktop-control suite; no evidence of a substitute compositor. |
| [Grid](https://github.com/pom11/Grid) — Docs | Keyboard snap zones and directional/display actions with menu-bar system monitoring. | An open-source manual geometry tool; no workspace-hiding claim established. |
| [Wins](https://wins.cool/) — Docs | Window snapping and management bundled with switching/desktop conveniences. | Product-level review; proprietary movement and visibility internals unknown. |
| [Ankylix](https://ankylix.com/) — Docs | Letter hints on windows and zones, modal movement, one-shot recent-window layouts. | An efficient selection/navigation UI; uses Accessibility according to publisher. |
| [MacTiler](https://mactiler.com/) — Docs | Preset arrangements for several windows and multi-display window/screen-content swapping. | Layout preservation across displays rather than automatic workspace isolation. |

##### Programmable foundations

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [Phoenix](https://github.com/kasper/phoenix/blob/916f8f19740530cd7cd63448ec0b6fa62925cebf/Phoenix/PHWindow.m) — Source | JavaScript-scriptable window manager with AX frame operations and window/app/Space events. | A programmable policy host; its frame path also uses size-position-size. |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/libspaces.m) — Source | Lua automation; AX windows, event taps, private Space queries/moves, Mission Control UI automation. | A fast prototype host; built-in Space switching is not Tuna-style instantaneous swiping. |
| [Lattices](https://lattices.dev/docs/overview/) — Docs | Window tiling and switchable layers exposed via CLI/agent API, plus project and tmux management. | Programmable control surface; its docs do not establish a novel hiding primitive. |
| [Slate](https://github.com/jigish/slate) — Docs | Configurable window operations, bindings, layouts and snapshots; scripting-oriented design. | Historical predecessor worth studying for policy/configuration, not current OS compatibility assurance. |
| [BetterTouchTool](https://folivora.ai/) — Docs | Gesture/shortcut automation with snapping and chains of window actions. | A configurable control and prototyping layer; no source-level visibility conclusion. |

##### Historical references

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [Spectacle](https://github.com/eczarny/spectacle/blob/e75c341ec2cba179c1bb8aa726a870c4132207df/Spectacle/Sources/SpectacleAccessibilityElement.m) — Source | Legacy shortcut-based AX position/size manager. | Historical baseline and ancestor of Rectangle, not a modern alternative backend. |
| [TotalSpaces2](https://blog.binaryage.com/totalfinder-totalspaces-future/) — Docs | Older native-Space enhancement using deep system integration and SIP-related installation changes. | Vendor ended plans for Apple Silicon/next-OS support; not a modern SIP-on foundation. |
| [Better Window Manager](https://formulae.brew.sh/cask/better-window-manager) — Lead | Older saved-window-state tool. | Found in the Homebrew catalog with a disabled cask; original implementation/current support not verified. |

##### Saved layouts and workspace restoration

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [Stay](https://cordlessdog.com/stay/) — Docs | Stores window arrangements per connected-display combination and restores them. | Treat display reconnection as restoration, not necessarily an instruction to retile everything. |
| [Display Maid](https://funk-isoft.com/display-maid.html) — Docs | Per-display-configuration profiles, app/global restoration and display/app-launch triggers. | Docs explicitly limit inactive-Space handling; does not launch missing apps. |
| [Spencer](https://macspencer.app/) — Docs | Saved layouts across native Spaces/displays, app launching/hiding and profile-specific Space counts. | Interesting native-Space product; internal transfer/create mechanisms not published here. |
| [Lattix](https://www.lattix.app/) — Docs | Launch complete sets of apps/files/websites and restore layouts across displays/Spaces. | Workspace reconstruction and switching; distinct from similarly named Lattices. |
| [ShiftPlus](https://shiftplus.app/blog/aerospace-alternative-mac/) — Docs | Workspace definitions include apps, files/URLs, browser profiles, terminal context and Space placement. | App/session restoration, not a continuously running tiling algorithm. |
| [Workflo](https://getworkflo.app/) — Docs | Saved Desks/Scenes applied by time, calendar or display changes, with app launch and placement. | Event-triggered orchestration rather than viewport/window-compositor control. |
| [Ikuna](https://ikuna.app/guides/restore-macos-workspace-automatically) — Docs | Project context restoration including apps/tabs/window geometry and Focus Mode. | Its guide explicitly says it does not pin apps to native Desktops. |

##### Adjacent tools and exclusions

| Project / evidence | Approach | What it contributes or fails to solve |
|---|---|---|
| [MiddleDrag](https://github.com/NullPointerDepressiveDisorder/MiddleDrag) — Docs | Three-finger middle-click/middle-drag input emulation. | Useful gesture infrastructure; not a tiling/window-layout engine. |
| [DashPane](https://www.dashpane.pro/) — Docs | Searchable app/window switcher with a corner-activated window sidebar. | Directory calls it a WM; current official page primarily describes switching. |
| [InfiniDesk](https://infinidesk.app/) — Docs | Switches Desktop-folder contents, icons, wallpaper and widget visibility. | Manages desktop contents, not foreign-window layout; exclude from WM-engine comparisons. |
| [Click2Minimize](https://click2minimize.com/) — Lead | Click-to-minimize and window-switching utility. | Official page exposed no readable docs in this review; visibility mechanism not investigated. |

#### Coverage and exclusions

Discovery used the macOS WM directory, broad web/GitHub searches, project cross-references and the cached source trees. Primary project pages and implementation files are the evidence; directory feature descriptions were not treated as authoritative. This covers all 55 entries in the directory's window-manager category at review time, plus additional automatic tilers, workspace tools, programmable foundations and historical references. Some directory entries turn out to be switchers or input utilities, which remain listed as exclusions rather than silently counted as full WMs.

HyprSpace/Hiro are historical names/redirects in the OmniWM lineage, not additional independent engines. kwm and chunkwm were found as historical predecessors, but their old primary repository URLs were unavailable during this review; they are not assigned current behavior here. AirSpace was another directory lead for which this pass did not establish a useful primary implementation. General launchers, window-only switchers, bars and border renderers are outside the main scope; examples include Raycast, AltTab, DockDoor, SketchyBar and JankyBorders. X11-only managers on XQuartz and apps that tile only their own terminals/browser panes do not manage arbitrary native Mac windows and are excluded.

The catalog is not a popularity ranking or performance benchmark. Source-current and release-current can differ. No third-party performance claims were reproduced. The source-revision manifest makes this inspection reproducible; the CSV exposes the same coverage distinctions for sorting/filtering.

Publicly readable source is not necessarily permissively reusable: KiwiDesk advertises BSL 1.1, komorebi has source-available/commercial terms, and other projects have their own copyleft or permissive licenses. We have studied approaches rather than copied an implementation. Any code reuse would need a specific license check.

## Appendix C — Inspected source revisions

These are the cached revisions from the survey, not a claim that every repository received a complete audit. Per-project evidence depth is marked in Appendix B.

| Repository | Revision |
|---|---|
| [AppRanger/windowranger](https://github.com/AppRanger/windowranger/tree/9ffe127cc3c5e96365f401d94fbe3026240e9b66) | `9ffe127cc3c5e96365f401d94fbe3026240e9b66` |
| [zimengxiong/winmux](https://github.com/zimengxiong/winmux/tree/470eedbf9e6a1bfe78e8cf199053df434af77c81) | `470eedbf9e6a1bfe78e8cf199053df434af77c81` |
| [david-soloveichik/Zonogy](https://github.com/david-soloveichik/Zonogy/tree/1c00ab41336edc14a53f7334e6b3dd3c55f11546) | `1c00ab41336edc14a53f7334e6b3dd3c55f11546` |
| [acsandmann/rift](https://github.com/acsandmann/rift/tree/c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1) | `c1612f605bb53d15b7c7c856ba0e7b57d2bb53d1` |
| [glide-wm/glide](https://github.com/glide-wm/glide/tree/3a92f97d2b20167b26f9274cdd6a90ca504def53) | `3a92f97d2b20167b26f9274cdd6a90ca504def53` |
| [OmniNull/OmniWM](https://github.com/OmniNull/OmniWM/tree/df8890ebd26f0b92f774f93449906dc1f79bd6e0) | `df8890ebd26f0b92f774f93449906dc1f79bd6e0` |
| [karinushka/paneru](https://github.com/karinushka/paneru/tree/f79b66ca34c217af1dbf779c9e2fd7a475277c99) | `f79b66ca34c217af1dbf779c9e2fd7a475277c99` |
| [mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon/tree/82f5dde20d40cf1bdef18ab92b2b847f16f368a3) | `82f5dde20d40cf1bdef18ab92b2b847f16f368a3` |
| [ianyh/Amethyst](https://github.com/ianyh/Amethyst/tree/6508ee2cacf8f9b357e1a3249a8f28ba5c94db2a) | `6508ee2cacf8f9b357e1a3249a8f28ba5c94db2a` |
| [glzr-io/glazewm](https://github.com/glzr-io/glazewm/tree/5709ad0a3c7c386bbc3e38166a865ffc12937515) | `5709ad0a3c7c386bbc3e38166a865ffc12937515` |
| [LGUG2Z/komorebi-for-mac](https://github.com/LGUG2Z/komorebi-for-mac/tree/bdf10452f10ebf15ec1978cb05d0aac79ef5611f) | `bdf10452f10ebf15ec1978cb05d0aac79ef5611f` |
| [PangMo5/Tatami](https://github.com/PangMo5/Tatami/tree/85633969af7f26be47ebe4211826b9713eec17ea) | `85633969af7f26be47ebe4211826b9713eec17ea` |
| [wojciech-kulik/FlashSpace](https://github.com/wojciech-kulik/FlashSpace/tree/968015308d8d284a98831f90f365538a63456ee9) | `968015308d8d284a98831f90f365538a63456ee9` |
| [zacharytgray/HyprMac](https://github.com/zacharytgray/HyprMac/tree/fe24abfe1009bde584b82f859e6cee071ca6f994) | `fe24abfe1009bde584b82f859e6cee071ca6f994` |
| [qeude/Defi](https://github.com/qeude/Defi/tree/7b3cf52a58d7a60c717a0d5d3954b0059b784747) | `7b3cf52a58d7a60c717a0d5d3954b0059b784747` |
| [KiwiCanopy/KiwiDesk](https://github.com/KiwiCanopy/KiwiDesk/tree/dda1fd77b7b220c0277085dc2ab8a94df3560cc3) | `dda1fd77b7b220c0277085dc2ab8a94df3560cc3` |
| [apphane-dev/nehir](https://github.com/apphane-dev/nehir/tree/f097f35a22c463b343c16e29327bd317b7573171) | `f097f35a22c463b343c16e29327bd317b7573171` |
| [cornz/TrimWM](https://github.com/cornz/TrimWM/tree/8432cab1c5b779fd790474a0d735961500f5f557) | `8432cab1c5b779fd790474a0d735961500f5f557` |
| [1jehuang/scrollwm](https://github.com/1jehuang/scrollwm/tree/9dc7668d2ef1e7e0a8a85390ca49061ea8e4c296) | `9dc7668d2ef1e7e0a8a85390ca49061ea8e4c296` |
| [bobrwm/bobrwm](https://github.com/bobrwm/bobrwm/tree/537627f83f7d3a7ac645fc60303c1d4bc558b4e4) | `537627f83f7d3a7ac645fc60303c1d4bc558b4e4` |
| [basuev/parket](https://github.com/basuev/parket/tree/4adb3ec0cf46734e3e7485af0fd28a6f95b1bca1) | `4adb3ec0cf46734e3e7485af0fd28a6f95b1bca1` |
| [typester/yashiki](https://github.com/typester/yashiki/tree/f36b0c358ac2316504938e8238f09d10480cd187) | `f36b0c358ac2316504938e8238f09d10480cd187` |
| [y3owk1n/mimi](https://github.com/y3owk1n/mimi/tree/1107d3e16d4e699537e2229844f5c894d3180b04) | `1107d3e16d4e699537e2229844f5c894d3180b04` |
| [jasonjmcghee/orcv](https://github.com/jasonjmcghee/orcv/tree/1e7ccf193b0dff5e7904dc9640bc45127c2d682e) | `1e7ccf193b0dff5e7904dc9640bc45127c2d682e` |
| [kasper/phoenix](https://github.com/kasper/phoenix/tree/916f8f19740530cd7cd63448ec0b6fa62925cebf) | `916f8f19740530cd7cd63448ec0b6fa62925cebf` |
| [Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon/tree/23e387e2805a9890066366e0ac96c71b27f0cfd5) | `23e387e2805a9890066366e0ac96c71b27f0cfd5` |
| [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle/tree/ef13b03827695323fd0595e15eb86c1414ce457d) | `ef13b03827695323fd0595e15eb86c1414ce457d` |
| [MrKai77/Loop](https://github.com/MrKai77/Loop/tree/df26d565e07c82e156b8f1c361bdcf428f32e3a4) | `df26d565e07c82e156b8f1c361bdcf428f32e3a4` |
| [jigish/slate](https://github.com/jigish/slate/tree/ff5ee5a53afc05b619cf9eb78e852b83ad714de4) | `ff5ee5a53afc05b619cf9eb78e852b83ad714de4` |
| [eczarny/spectacle](https://github.com/eczarny/spectacle/tree/e75c341ec2cba179c1bb8aa726a870c4132207df) | `e75c341ec2cba179c1bb8aa726a870c4132207df` |
| [asmvik/yabai](https://github.com/asmvik/yabai/tree/dd845723416f5fe92af49fad5ebab00369e07edd) | `dd845723416f5fe92af49fad5ebab00369e07edd` |
| [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace/tree/5f08f9c0c9daea6bb0f652da71d80a02e0b3f6cf) | `5f08f9c0c9daea6bb0f652da71d80a02e0b3f6cf` |
