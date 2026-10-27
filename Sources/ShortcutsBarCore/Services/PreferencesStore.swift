import Foundation

public final class PreferencesStore: @unchecked Sendable {
    public static let shared = PreferencesStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    private let scopeModeKey = "shortcutsbar.scopeMode"
    private let leafFolderKey = "shortcutsbar.leafFolderName"
    private let launchAtLoginKey = "shortcutsbar.launchAtLogin"
    private let notifyOnFailureKey = "shortcutsbar.notifyOnFailure"
    private let progressRingStyleKey = "shortcutsbar.progressRingStyle"

    public static let preferencesChangedNotification = Notification.Name("ShortcutsBarPreferencesChanged")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var progressRingStyle: ProgressRingStyle {
        get {
            lock.withLock {
                if let raw = defaults.string(forKey: progressRingStyleKey),
                   let style = ProgressRingStyle(rawValue: raw) {
                    return style
                }
                return .classicMinimal
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: progressRingStyleKey)
            }
            NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self)
        }
    }

    public var folderScope: FolderScope {
        get {
            lock.withLock {
                let mode = defaults.string(forKey: scopeModeKey) ?? "leaf"
                if mode == "root" {
                    return .root
                } else {
                    let folder = defaults.string(forKey: leafFolderKey) ?? "Menu Bar"
                    return .leaf(folderName: folder)
                }
            }
        }
        set {
            lock.withLock {
                switch newValue {
                case .root:
                    defaults.set("root", forKey: scopeModeKey)
                case .leaf(let folderName):
                    defaults.set("leaf", forKey: scopeModeKey)
                    defaults.set(folderName, forKey: leafFolderKey)
                }
            }
            NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self)
        }
    }

    public var launchAtLogin: Bool {
        get {
            lock.withLock { defaults.bool(forKey: launchAtLoginKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: launchAtLoginKey) }
            NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self)
        }
    }

    public var notifyOnFailure: Bool {
        get {
            lock.withLock { defaults.bool(forKey: notifyOnFailureKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: notifyOnFailureKey) }
            NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self)
        }
    }
}
