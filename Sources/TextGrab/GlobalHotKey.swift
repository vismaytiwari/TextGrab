import Carbon
import AppKit

// Thin wrapper around the Carbon hot-key API. Unlike a CGEventTap, this needs
// no Accessibility permission — the system delivers the key event directly.
final class GlobalHotKey {
    let registered: Bool
    private var ref: EventHotKeyRef?

    // A single global handler is enough for this app; the C callback below can
    // only reach static state, so we keep it here rather than capturing self.
    private static var handler: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        GlobalHotKey.handler = handler

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: fourCharCode("TGrb"), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        registered = (status == noErr)
    }
}

private func fourCharCode(_ s: String) -> FourCharCode {
    var code: FourCharCode = 0
    for unit in s.utf16.prefix(4) { code = (code << 8) + FourCharCode(unit) }
    return code
}
