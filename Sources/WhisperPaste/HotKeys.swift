import AppKit
import Carbon

final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((UInt32) -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            owner.onAction?(id.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register() -> Bool {
        for (id, key) in [(UInt32(1), UInt32(kVK_Space)), (UInt32(2), UInt32(kVK_Return))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey),
                EventHotKeyID(signature: 0x57505354, id: id), GetApplicationEventTarget(), 0, &ref)
            guard result == noErr, let ref else {
                refs.forEach { UnregisterEventHotKey($0) }; refs = []; return false
            }
            refs.append(ref)
        }
        return true
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
