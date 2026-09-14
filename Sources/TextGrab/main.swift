import AppKit
import Carbon.HIToolbox

// One instance only: a second copy cannot register the hot key, so it would sit
// there doing nothing. A newer build takes over from an older one.
// Development tool. Captures a fixed rectangle with the same ScreenCaptureKit
// path a grab uses, so a broken capture can be told apart from a broken
// selector without anyone having to drag anything. Runs before the instance
// claim so it never disturbs a copy that is already up.
if CommandLine.arguments.contains("--capture-self-test") {
    exit(TextGrabber.captureSelfTest())
}

if CommandLine.arguments.contains("--selector-self-test") {
    exit(RegionSelector.selfTest())
}

// Development tool: a hot key can only be held by one process, so failing to
// register it here is the proof that the running copy has it. Succeeding is the
// bug — it would mean nothing is listening for that combination at all.
if CommandLine.arguments.contains("--hotkey-self-test") {
    _ = NSApplication.shared
    let one = GlobalHotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey)) {}
    let two = GlobalHotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)) {}
    print("⇧⌘1 held by the running app: \(!one.registered)")
    print("⇧⌘2 held by the running app: \(!two.registered)")
    exit(0)
}

guard SingleInstance.claim() else { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
