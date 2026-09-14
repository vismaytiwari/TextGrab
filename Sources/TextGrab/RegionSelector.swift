import AppKit

/// Drag out a screen region without anyone else seeing you do it.
///
/// The system selector (`screencapture -i`) dims every display, draws its own
/// selection rectangle and swaps the pointer for a crosshair, and all three are
/// composited into the display stream — so anyone watching a screen share sees
/// the exact moment a screenshot is taken. This overlay is marked `.none` for
/// sharing, which is what makes the window server leave it out of every
/// recording and share, and it never touches the cursor. To a viewer nothing
/// happens but an ordinary pointer moving; locally the rectangle is fully there.
enum RegionSelector {
    /// A rectangle on its own is not enough to capture: a capture is addressed
    /// to one display, so the display the region belongs to travels with it.
    struct Selection {
        let rect: CGRect  // global screen points, bottom-left origin, as NSScreen measures
        let screen: NSScreen
    }

    /// Under this a drag is a slip of the hand rather than a selection, and a
    /// one-pixel image is never what was wanted.
    fileprivate static let minimumDrag: CGFloat = 4

    fileprivate static var session: Session?

    /// Development tool: brings the overlay up, reports what the window server
    /// actually did with it, and takes it down again. A selection cannot be
    /// dragged from a script, so this checks everything up to the drag.
    static func selfTest() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            session = Session(dimmed: true) { _ in }
        }
        // One second of real runloop first: ordering a window front and the app
        // becoming active are both asynchronous, so asking straight away would
        // only ever report the state before any of it happened.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        print(session?.describeForProbe() ?? "session missing")
        print("app active: \(app.isActive)")
        DispatchQueue.main.async { session?.cancel() }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.3))
        return 0
    }

    /// Blocks the caller until the drag ends, returning nil if it was cancelled.
    ///
    /// Both capture paths already run on a background queue, because a drag
    /// lasts as long as the user wants it to. The overlay has to be driven by
    /// the main runloop, so the background caller parks here instead of the main
    /// thread waiting on the user.
    /// `dimmed` decides how loudly the mode announces itself locally. A text
    /// grab dims everything outside the selection, because reading back OCR you
    /// did not mean to take is worse than a moment of grey. Copying a picture
    /// does not, because the point there is to see the colours you are taking;
    /// it gets a thin border instead, which is still enough to know the mode is
    /// armed. Neither is visible to anyone else: the window is excluded from
    /// every recording.
    static func select(dimmed: Bool) -> Selection? {
        guard !Thread.isMainThread else {
            NSLog("TextGrab: a region selection has to be started off the main thread")
            return nil
        }
        var selection: Selection?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            // A second hot key press while an overlay is already up replaces it
            // rather than stacking another one over the first.
            session?.cancel()
            session = Session(dimmed: dimmed) { result in
                selection = result
                done.signal()
            }
        }
        done.wait()
        return selection
    }
}

/// One selection's worth of overlay: a window per display, and the drag that
/// runs across them.
private final class Session {
    /// Cleared the moment the selection ends, so a mouse-up arriving after an
    /// Esc cannot signal the waiting caller a second time.
    private var finish: ((RegionSelector.Selection?) -> Void)?
    /// A full-screen window that swallows every click is the worst thing this
    /// app can leave behind: there is nothing to click to get rid of it. If no
    /// selection has been made by now, something went wrong and the overlay
    /// takes itself down rather than holding the machine hostage.
    private var deadline: Timer?
    private var windows: [OverlayWindow] = []
    private var origin: CGPoint?
    /// Activating an accessory app takes the keyboard away from whatever was
    /// being typed in and nothing hands it back on its own.
    private let previousApp = NSWorkspace.shared.frontmostApplication

    init(dimmed: Bool, finish: @escaping (RegionSelector.Selection?) -> Void) {
        self.finish = finish
        let pointer = NSEvent.mouseLocation
        windows = NSScreen.screens.map { OverlayWindow(screen: $0, session: self, dimmed: dimmed) }
        for window in windows {
            window.orderFrontRegardless()
        }
        // Only the key window of an active application is sent a key press, and
        // an accessory app is never active until it says so — without this Esc
        // would go to whatever was in front and cancel nothing.
        //
        // `activate()` alone is not enough. macOS 14's cooperative activation
        // lets the system refuse it when another app is frontmost, and it did:
        // the overlay came up with the app still inactive and no key window, so
        // Esc went nowhere. Ignoring other apps is the older, blunter call that
        // actually takes the focus.
        NSApp.activate(ignoringOtherApps: true)
        Diagnostics.log("selector: overlay up on \(windows.count) screen(s), dimmed=\(dimmed)")
        armDeadline()
        // The window under the pointer takes the key role because that is where
        // Esc is aimed before any button has been pressed.
        (windows.first { $0.frame.contains(pointer) } ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    /// Development tool: what the window server did with the overlay.
    func describeForProbe() -> String {
        let lines = windows.map { window in
            "window \(window.frame.integral) visible=\(window.isVisible) key=\(window.isKeyWindow) "
                + "sharing=\(window.sharingType == .none ? "none" : "SHARED") level=\(window.level.rawValue) "
                + "alpha=\(window.alphaValue) onActiveSpace=\(window.isOnActiveSpace)"
        }
        return ([ "overlay windows: \(windows.count)" ] + lines).joined(separator: "\n")
    }

    /// The overlay only ever dies of old age, never of losing focus.
    ///
    /// Cancelling on `didResignActive` was tried and was the bug: the app
    /// activates for the overlay and something takes the focus straight back
    /// within a second, so the selector tore itself down before a drag could
    /// even start and the hot key looked dead. Focus is not needed to select —
    /// the view takes the first mouse — only to receive Esc.
    private func armDeadline() {
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // A drag in progress is someone taking their time, not a stuck
            // window; give it another round rather than yanking it away.
            if self.origin != nil {
                self.armDeadline()
                return
            }
            Diagnostics.log("selector: nothing selected in 20s; taking the overlay down")
            self.cancel()
        }
    }

    func begin(at point: CGPoint) {
        origin = point
        armDeadline()
        show(nil)
    }

    func drag(to point: CGPoint) {
        guard let origin = origin else { return }
        show(rect(from: origin, to: point))
    }

    func end(at point: CGPoint) {
        guard let start = origin else { return cancel() }
        origin = nil
        // A selection can be dragged across a display boundary, and one capture
        // cannot span two displays. The one the drag started on wins, and the
        // region stops at its edge.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(start) }) ?? NSScreen.main else {
            return cancel()
        }
        let selected = rect(from: start, to: point).intersection(screen.frame)
        guard selected.width >= RegionSelector.minimumDrag,
              selected.height >= RegionSelector.minimumDrag else {
            return cancel()
        }
        close(with: RegionSelector.Selection(rect: selected, screen: screen))
    }

    func cancel() {
        close(with: nil)
    }

    private func close(with selection: RegionSelector.Selection?) {
        guard let finish = finish else { return }
        self.finish = nil
        deadline?.invalidate()
        deadline = nil
        Diagnostics.log("selector: closing, selection=\(selection.map { "\($0.rect.integral)" } ?? "cancelled")")
        if RegionSelector.session === self { RegionSelector.session = nil }
        for window in windows {
            window.orderOut(nil)
        }
        previousApp?.activate()
        // The overlay is out of every recording anyway, but the capture still
        // must not race the window server: one turn of the runloop is what
        // guarantees the frame being captured no longer has the rectangle in it.
        // The windows are let go in the same turn rather than here, because this
        // is usually running inside one of their own mouse events.
        DispatchQueue.main.async { [self] in
            windows = []
            finish(selection)
        }
    }

    private func show(_ rect: CGRect?) {
        for window in windows {
            window.overlay.selection = rect?.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }
}

/// A borderless window answers false to `canBecomeKey`, and a window that cannot
/// become key is never sent a key press — which would leave Esc nowhere to land.
private final class OverlayWindow: NSWindow {
    let overlay: OverlayView

    override var canBecomeKey: Bool { true }

    init(screen: NSScreen, session: Session, dimmed: Bool) {
        overlay = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        overlay.session = session
        overlay.dimmed = dimmed
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // The whole point of the exercise: the window server keeps a window
        // marked `.none` out of every screen recording and share, so the person
        // on the other end of a call sees nothing happen at all.
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, so a region can be dragged over anything.
        level = .screenSaver
        // Joining the space that is showing — including a full-screen app's —
        // rather than forcing a switch away from it, which would be very visible.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = overlay
        initialFirstResponder = overlay
    }
}

/// Draws the selection and turns the drag into coordinates.
private final class OverlayView: NSView {
    weak var session: Session?
    var dimmed = true

    var selection: CGRect? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    /// The overlay arrives under the pointer without the app ever having been
    /// clicked, so the first mouse-down has to start the drag rather than being
    /// spent activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit gives a view whatever cursor its rects ask for, and asking for the
    /// ordinary arrow is what stops anything substituting a crosshair while the
    /// overlay is up: the pointer a viewer sees has to stay unremarkable.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A dim over everything, with the selection punched back out of it.
        //
        // The first version drew nothing until a drag began, on the theory that
        // a tint was a heavy thing to do to your own screen. It made the mode
        // invisible to its own user: pressing the hot key looked exactly like
        // nothing happening, which is indistinguishable from a broken app. The
        // dim is free here in the way that matters — this window is excluded
        // from every recording, so no viewer sees any of it.
        if dimmed {
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()
        } else {
            // This fill looks like nothing and is the whole reason the undimmed
            // selector works at all.
            //
            // The window server routes mouse events through a non-opaque
            // window's alpha mask: wherever the window drew nothing, the click
            // goes straight past it to the application underneath. Drawing only
            // an edge hairline meant every click in the middle of the screen —
            // which is every click that matters — missed the overlay entirely,
            // landed on whatever was behind it, and took the focus with it. The
            // hot key looked completely dead.
            //
            // Two percent black is invisible to the eye and opaque to the event
            // system, which is exactly the combination needed here.
            NSColor.black.withAlphaComponent(0.02).setFill()
            bounds.fill()
            // And a hairline at the very edge, so the mode says "armed" without
            // touching a single pixel of what is about to be copied.
            NSColor.white.withAlphaComponent(0.55).setStroke()
            let edge = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            edge.lineWidth = 2
            edge.stroke()
        }
        guard let selection = selection, !selection.isEmpty else { return }
        // Erase rather than lighten, so the pixels being taken are shown at
        // their true brightness and what you see is what you get.
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        // The outline is drawn twice because one colour always loses somewhere:
        // a dark halo under a bright line stays readable over a white page and a
        // black terminal alike.
        let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        NSColor.black.withAlphaComponent(0.45).setStroke()
        outline.lineWidth = 3
        outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        session?.begin(at: location(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        session?.drag(to: location(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        session?.end(at: location(of: event))
    }

    /// A right-click is the other way out, for a hand already on the mouse.
    override func rightMouseDown(with event: NSEvent) {
        session?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        // 53 is Esc. Everything else is swallowed rather than passed along, so a
        // keystroke during a selection cannot beep or reach the app underneath.
        if event.keyCode == 53 {
            session?.cancel()
        }
    }

    /// Global screen points, so a drag that wanders onto another display is
    /// still one continuous rectangle.
    private func location(of event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}
