import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Icon.menuBar()

        // Enable launch-at-login by default; no-op if already registered.
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Grab Text  (⇧⌘2)", action: #selector(grab), keyEquivalent: "")
        menu.addItem(.separator())
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

        // ⇧⌘2 — free by default (macOS uses ⇧⌘3/4/5 for screenshots).
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_2),
                              modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.grab()
        }
        statusItem.button?.toolTip = (hotKey?.registered == true)
            ? "TextGrab — press ⇧⌘2 to grab text"
            : "TextGrab — ⇧⌘2 is already in use by another app"
    }

    @objc private func grab() {
        // Small delay lets the status menu (if open) dismiss before capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch TextGrabber.captureAndCopy() {
            case .copied(let text, let image):
                HUD.show(success: true, text: text, image: image)
            case .empty:
                HUD.show(success: false, text: "", image: nil)
            case .cancelled:
                break
            }
        }
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
        is copied to your clipboard.

        On-device OCR via Apple Vision. No network, no telemetry.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
