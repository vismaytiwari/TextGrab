import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var copyScreenHotKey: GlobalHotKey?
    private var loginItem: NSMenuItem!
    private var codeModeItem: NSMenuItem!

    /// Whether anything is shown on screen after a grab. Off by default: the
    /// point of the app is that text lands on the clipboard and nothing else
    /// happens. Turn it on from the menu if you want the confirmation back.

    /// Tuned for code: no language correction, indentation preserved, punctuation
    /// left as ASCII. Turn it off for prose, where correction genuinely helps.
    private static let codeModeKey = "CodeMode"
    private var codeMode: Bool {
        UserDefaults.standard.object(forKey: Self.codeModeKey) as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Icon.menuBar()

        // Enable launch-at-login by default; no-op if already registered.
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }

        // Capturing moved in-process, so the grant TextGrab needs is its own
        // rather than `/usr/sbin/screencapture`'s. Said out loud at launch
        // because the symptom of missing it is a hot key that does nothing.
        Diagnostics.log("launched; screen recording granted = \(CGPreflightScreenCaptureAccess())")

        let menu = NSMenu()
        menu.addItem(withTitle: "Grab Text  (⇧⌘2)", action: #selector(grab), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Region  (⇧⌘1)", action: #selector(copyScreen), keyEquivalent: "")
        menu.addItem(.separator())
        codeModeItem = NSMenuItem(title: "Code Mode", action: #selector(toggleCodeMode), keyEquivalent: "")
        menu.addItem(codeModeItem)
        loginItem = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(withTitle: "About TextGrab", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TextGrab",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
        refreshLoginItemState()
        codeModeItem.state = codeMode ? .on : .off

        // ⇧⌘2 — free by default (macOS uses ⇧⌘3/4/5 for screenshots).
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_2),
                              modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.grab()
        }
        statusItem.button?.toolTip = (hotKey?.registered == true)
            ? "TextGrab — press ⇧⌘2 to grab text"
            : "TextGrab — ⇧⌘2 is already in use by another app"

        // ⇧⌘1 replaces macOS's own "copy picture of screen to the clipboard",
        // which has no way to drop its shutter sound. Ours copies a dragged
        // REGION rather than the whole screen: a whole-screen image is rarely
        // what you want to paste, and it carries everything else on the display
        // with it. The system shortcut is disabled in Keyboard settings so the
        // two do not both fire.
        copyScreenHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_1),
                                        modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.copyScreen()
        }
        Diagnostics.log("hot keys registered: ⇧⌘2=\(hotKey?.registered == true) ⇧⌘1=\(copyScreenHotKey?.registered == true)")
        if copyScreenHotKey?.registered != true {
            NSLog("TextGrab: ⇧⌘1 is already in use; Copy Region is menu-only")
        }
    }

    @objc private func grab() {
        Diagnostics.log("hot key: grab text")
        // Small delay lets the status menu (if open) dismiss before capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Off the main thread: the capture blocks for as long as you take to
            // drag the selection, and the OCR for a while after that. Doing both
            // on the main thread froze the menu bar for the whole grab.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = TextGrabber.captureAndCopy(codeMode: self?.codeMode ?? true)
                DispatchQueue.main.async {
                    switch result {
                    // Nothing is shown for any outcome. A toast is a window
                    // like any other and would be composited into a screen
                    // share, announcing the grab the rest of this app goes to
                    // some trouble to hide. The clipboard is the receipt.
                    //
                    // On `.empty` the clipboard is deliberately left untouched,
                    // so a paste gives back whatever was there before.
                    case .copied, .empty, .cancelled:
                        break
                    }
                }
            }
        }
    }

    @objc private func copyScreen() {
        Diagnostics.log("hot key: copy region")
        // Same small delay as a grab, so an open status menu is not in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = TextGrabber.copyRegionToClipboard()
                DispatchQueue.main.async {
                    switch result {
                    case .copied, .cancelled:
                        break
                    case .failed:
                        // Usually a missing Screen Recording grant. The HUD's
                        // failure copy is about unreadable text, so log instead.
                        NSLog("TextGrab: the capture failed for Copy Region")
                    }
                }
            }
        }
    }

    @objc private func toggleCodeMode() {
        UserDefaults.standard.set(!codeMode, forKey: Self.codeModeKey)
        codeModeItem.state = codeMode ? .on : .off
    }

    // MARK: Launch at Login

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("TextGrab: launch-at-login toggle failed: \(error)")
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TextGrab"
        alert.informativeText = """
        Press ⇧⌘2, drag a box over anything on screen, and the text inside it \
        is copied to your clipboard. ⇧⌘1 copies a silent screenshot of the \
        whole screen.

        On-device OCR via Apple Vision. No network, no telemetry.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
