import AppKit
import Carbon.HIToolbox
import OSLog

@MainActor
public final class GlobalHotkeyManager: NSObject {
    public static let shared = GlobalHotkeyManager()

    public enum HotkeyError: LocalizedError, Equatable, Sendable {
        case installHandlerFailed(OSStatus)
        case registerHotKeyFailed(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .installHandlerFailed(let status):
                return "Carbon InstallEventHandler failed with OSStatus \(status)"
            case .registerHotKeyFailed(let status):
                return "Carbon RegisterEventHotKey failed with OSStatus \(status) (possible conflict with system or other apps)"
            }
        }
    }

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
            Logger.hotkey.error("Failed to install Carbon event handler: OSStatus \(installStatus)")
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
            Logger.hotkey.info("Successfully registered global hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")
            return true
        } else {
            Logger.hotkey.error("Failed to register global hotkey: OSStatus \(registerStatus) (keyCode=\(keyCode), modifiers=\(modifiers))")
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
