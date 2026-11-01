import Foundation

public final class PreferencesStore: @unchecked Sendable {
    public static let shared = PreferencesStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    private let scopeModeKey = "shortcutsbar.scopeMode"
    private let leafFolderKey = "shortcutsbar.leafFolderName"
    private let launchAtLoginKey = "shortcutsbar.launchAtLogin"
    private let notifyOnFailureKey = "shortcutsbar.notifyOnFailure"
    private let primaryClickActionKey = "shortcutsbar.primaryClickAction"
    private let panelOriginXKey = "shortcutsbar.panelOriginX"
    private let panelOriginYKey = "shortcutsbar.panelOriginY"
    private let isPinnedKey = "shortcutsbar.isPinned"
    private let customSortOrdersKey = "shortcutsbar.customSortOrders"
    private let globalHotkeyEnabledKey = "shortcutsbar.globalHotkeyEnabled"
    private let globalHotkeyCodeKey = "shortcutsbar.globalHotkeyCode"
    private let globalHotkeyModifiersKey = "shortcutsbar.globalHotkeyModifiers"
    private let showMenuBarRunningStatusKey = "shortcutsbar.showMenuBarRunningStatus"

    public static let preferencesChangedNotification = Notification.Name("ShortcutsBarPreferencesChanged")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var folderScope: FolderScope {
        get {
            lock.withLock {
                let mode = defaults.string(forKey: scopeModeKey) ?? "leaf"
                if mode == "root" {
                    return .root
                } else {
                    let defaultLeaf = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? "快捷指令" : "Menu Bar"
                    let folder = defaults.string(forKey: leafFolderKey) ?? defaultLeaf
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
            postPreferencesChangedNotification(key: "folderScope")
        }
    }

    public var launchAtLogin: Bool {
        get {
            lock.withLock { defaults.bool(forKey: launchAtLoginKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: launchAtLoginKey) }
            postPreferencesChangedNotification(key: "launchAtLogin")
        }
    }

    public var notifyOnFailure: Bool {
        get {
            lock.withLock { defaults.bool(forKey: notifyOnFailureKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: notifyOnFailureKey) }
            postPreferencesChangedNotification(key: "notifyOnFailure")
        }
    }

    public var showMenuBarRunningStatus: Bool {
        get {
            lock.withLock {
                if defaults.object(forKey: showMenuBarRunningStatusKey) == nil {
                    return true // 默认在菜单栏显示任务运行状态
                }
                return defaults.bool(forKey: showMenuBarRunningStatusKey)
            }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: showMenuBarRunningStatusKey) }
            postPreferencesChangedNotification(key: "showMenuBarRunningStatus")
        }
    }

    public var primaryClickAction: PrimaryClickAction {
        get {
            lock.withLock {
                guard let raw = defaults.string(forKey: primaryClickActionKey),
                      let action = PrimaryClickAction(rawValue: raw) else {
                    return .classicMenu
                }
                return action
            }
        }
        set {
            lock.withLock { defaults.set(newValue.rawValue, forKey: primaryClickActionKey) }
            postPreferencesChangedNotification(key: "primaryClickAction")
        }
    }

    public var panelOrigin: CGPoint? {
        get {
            lock.withLock {
                guard defaults.object(forKey: panelOriginXKey) != nil,
                      defaults.object(forKey: panelOriginYKey) != nil else {
                    return nil
                }
                let x = defaults.double(forKey: panelOriginXKey)
                let y = defaults.double(forKey: panelOriginYKey)
                return CGPoint(x: x, y: y)
            }
        }
        set {
            lock.withLock {
                if let pt = newValue {
                    defaults.set(Double(pt.x), forKey: panelOriginXKey)
                    defaults.set(Double(pt.y), forKey: panelOriginYKey)
                } else {
                    defaults.removeObject(forKey: panelOriginXKey)
                    defaults.removeObject(forKey: panelOriginYKey)
                }
            }
            postPreferencesChangedNotification(key: "panelOrigin")
        }
    }

    public var isPinned: Bool {
        get {
            lock.withLock { defaults.bool(forKey: isPinnedKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: isPinnedKey) }
            postPreferencesChangedNotification(key: "isPinned")
        }
    }

    public func getCustomOrder(for folder: String) -> [String] {
        lock.withLock {
            guard let dict = defaults.dictionary(forKey: customSortOrdersKey) as? [String: [String]] else {
                return []
            }
            return dict[folder] ?? []
        }
    }

    public func setCustomOrder(_ order: [String], for folder: String) {
        lock.withLock {
            var dict = (defaults.dictionary(forKey: customSortOrdersKey) as? [String: [String]]) ?? [:]
            dict[folder] = order
            defaults.set(dict, forKey: customSortOrdersKey)
        }
        postPreferencesChangedNotification(key: "customOrder")
    }

    /// 💡 清除指定文件夹的自定义排序，恢复为快捷指令 App 原生排序
    public func resetCustomOrder(for folder: String) {
        lock.withLock {
            var dict = (defaults.dictionary(forKey: customSortOrdersKey) as? [String: [String]]) ?? [:]
            dict.removeValue(forKey: folder)
            defaults.set(dict, forKey: customSortOrdersKey)
        }
        postPreferencesChangedNotification(key: "customOrder")
    }

    /// 💡 清除所有分类的自定义排序，全部恢复为快捷指令 App 原生排序
    public func resetAllCustomOrders() {
        lock.withLock {
            defaults.removeObject(forKey: customSortOrdersKey)
        }
        postPreferencesChangedNotification(key: "customOrder")
    }

    public var globalHotkeyEnabled: Bool {
        get {
            lock.withLock { defaults.bool(forKey: globalHotkeyEnabledKey) }
        }
        set {
            lock.withLock { defaults.set(newValue, forKey: globalHotkeyEnabledKey) }
            postPreferencesChangedNotification(key: "globalHotkey")
        }
    }

    public var globalHotkeyCode: UInt32? {
        get {
            lock.withLock {
                guard defaults.object(forKey: globalHotkeyCodeKey) != nil else { return nil }
                return UInt32(defaults.integer(forKey: globalHotkeyCodeKey))
            }
        }
        set {
            lock.withLock {
                if let val = newValue {
                    defaults.set(Int(val), forKey: globalHotkeyCodeKey)
                } else {
                    defaults.removeObject(forKey: globalHotkeyCodeKey)
                }
            }
            postPreferencesChangedNotification(key: "globalHotkey")
        }
    }

    public var globalHotkeyModifiers: UInt32? {
        get {
            lock.withLock {
                guard defaults.object(forKey: globalHotkeyModifiersKey) != nil else { return nil }
                return UInt32(defaults.integer(forKey: globalHotkeyModifiersKey))
            }
        }
        set {
            lock.withLock {
                if let val = newValue {
                    defaults.set(Int(val), forKey: globalHotkeyModifiersKey)
                } else {
                    defaults.removeObject(forKey: globalHotkeyModifiersKey)
                }
            }
            postPreferencesChangedNotification(key: "globalHotkey")
        }
    }

    private func postPreferencesChangedNotification(key: String? = nil) {
        let userInfo: [String: Any]? = key.map { ["key": $0] }
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self, userInfo: userInfo)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                NotificationCenter.default.post(name: Self.preferencesChangedNotification, object: self, userInfo: userInfo)
            }
        }
    }
}
