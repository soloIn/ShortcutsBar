import AppKit
import Carbon.HIToolbox

@MainActor
public final class GlobalHotkeyManager: NSObject {
    public static let shared = GlobalHotkeyManager()

    public var onHotkeyPressed: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public private(set) var isRegistered: Bool = false

    public override init() {
        super.init()
    }

    isolated deinit {
        unregister()
    }

    public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x53435453) // "SCTS"
        gMyHotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            Task { @MainActor in
                GlobalHotkeyManager.shared.onHotkeyPressed?()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            return false
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            gMyHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            isRegistered = true
            return true
        } else {
            unregister()
            return false
        }
    }

    public func unregister() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        isRegistered = false
    }
}
