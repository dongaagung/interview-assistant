import Carbon.HIToolbox

/// A system-wide shortcut that works while the meeting app has focus.
/// Carbon's RegisterEventHotKey needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    /// ⌃⌥H, shown in the UI next to "Hint now".
    static let label = "⌃⌥H"

    private static var action: (@MainActor () -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ action: @escaping @MainActor () -> Void) {
        unregister()
        Self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // A C callback can't capture context, so it reaches the action
        // through the static. Hot-key events arrive on the main thread.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.action?() }
            return noErr
        }, 1, &pressed, nil, &handler)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x4941_4854, id: 1),  // "IAHT"
            GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        Self.action = nil
    }
}
