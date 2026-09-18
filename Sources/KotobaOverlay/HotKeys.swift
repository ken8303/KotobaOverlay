import AppKit
import Carbon

@MainActor final class HotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var action: ((UInt32) -> Void)?
    func register(action: @escaping (UInt32) -> Void) {
        guard handler == nil else { return }
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let hotkeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            Task { @MainActor in hotkeys.action?(id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_T)), (2, UInt32(kVK_ANSI_H)), (3, UInt32(kVK_ANSI_R)), (4, UInt32(kVK_ANSI_E))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4B4F544F, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { references.append(reference) }
        }
    }
}
