import AppKit

// One instance only: a second copy cannot register the hot key, so it would sit
// there doing nothing. A newer build takes over from an older one.
guard SingleInstance.claim() else { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
