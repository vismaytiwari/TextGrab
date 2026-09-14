import Carbon
import AppKit

// Thin wrapper around the Carbon hot-key API. Unlike a CGEventTap, this needs
// no Accessibility permission: the system delivers the key event directly.
final class GlobalHotKey {
    let registered: Bool
    private var ref: EventHotKeyRef?
    private let id: UInt32

    // The C callback below can only reach static state, so handlers live here,
    // keyed by the id the system hands back with each press. One Carbon event
    // handler serves every hot key the app registers.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.handlers[id] = handler
        GlobalHotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: fourCharCode("TGrb"), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        registered = (status == noErr)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        GlobalHotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &pressed)
            if status == noErr {
                GlobalHotKey.handlers[pressed.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

private func fourCharCode(_ s: String) -> FourCharCode {
    var code: FourCharCode = 0
    for unit in s.utf16.prefix(4) { code = (code << 8) + FourCharCode(unit) }
    return code
}
