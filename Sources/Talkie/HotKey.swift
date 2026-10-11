import Carbon.HIToolbox

/// A system-wide push-to-talk shortcut (⌥Space by default) that works while any app is in front.
/// Carbon hot keys report both press and release and don't need accessibility permission.
final class HotKey {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: Int = kVK_Space, modifiers: Int = optionKey) {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let typeCount = types.count
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                hotKey.onPress()
            } else {
                hotKey.onRelease()
            }
            return OSStatus(noErr)
        }, typeCount, &types, me, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x544C_4B45), id: 1) // 'TLKE'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
