import AppKit

@MainActor
public final class MenuBuilder: NSObject, NSMenuDelegate {
    public weak var shortcutsService: ShortcutsService?
    public weak var processManager: ProcessManager?
    public var currentScope: FolderScope = .leaf(folderName: "Menu Bar")

    public var onOpenSettings: (() -> Void)?
    public var onOpenShortcutsApp: (() -> Void)?

    private let actionTarget = MenuActionTarget()

    public func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        guard let service = shortcutsService, let manager = processManager else {
            let errorItem = NSMenuItem(title: "服务不可用", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            return menu
        }

        let activeTasks = manager.activeTasks

        // MARK: 1. Running Tasks Queue Section
        if !activeTasks.isEmpty {
            if activeTasks.count <= 3 {
                // Inline running rows (count <= 3)
                for task in activeTasks {
                    let taskItem = NSMenuItem()
                    let taskView = RunningTaskView(
                        taskId: task.id,
                        taskName: task.shortcutName,
                        onStop: { [weak manager] id in
                            manager?.terminate(taskId: id)
                        }
                    )
                    taskItem.view = taskView
                    menu.addItem(taskItem)
                }
            } else {
                // Collapsed into submenu (count > 3)
                let summaryItem = NSMenuItem(
                    title: "⚡ 正在运行的任务 (\(activeTasks.count))",
                    action: nil,
                    keyEquivalent: ""
                )
                if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
                    summaryItem.image = symbol
                }

                let subMenu = NSMenu()
                for task in activeTasks {
                    let taskItem = NSMenuItem()
                    let taskView = RunningTaskView(
                        taskId: task.id,
                        taskName: task.shortcutName,
                        onStop: { [weak manager] id in
                            manager?.terminate(taskId: id)
                        }
                    )
                    taskItem.view = taskView
                    subMenu.addItem(taskItem)
                }

                subMenu.addItem(NSMenuItem.separator())

                let stopAllItem = NSMenuItem(
                    title: "🛑 终止所有正在运行的任务",
                    action: #selector(actionTarget.handleStopAll),
                    keyEquivalent: ""
                )
                stopAllItem.target = actionTarget
                actionTarget.stopAllHandler = { [weak manager] in
                    manager?.terminateAll()
                }
                subMenu.addItem(stopAllItem)

                summaryItem.submenu = subMenu
                menu.addItem(summaryItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // MARK: 2. Shortcuts Section (Folder Scope)
        switch currentScope {
        case .leaf(let folderName):
            let items = service.getShortcuts(for: currentScope)
            if items.isEmpty {
                let emptyItem = NSMenuItem(
                    title: "文件夹「\(folderName)」暂无快捷指令",
                    action: nil,
                    keyEquivalent: ""
                )
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                for item in items {
                    let menuItem = createShortcutMenuItem(for: item)
                    menu.addItem(menuItem)
                }
            }

        case .root:
            let folders = service.cachedFolders
            if folders.isEmpty && service.unfiledShortcuts.isEmpty {
                let emptyItem = NSMenuItem(title: "暂无快捷指令", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                // Add submenus for each folder
                for folder in folders {
                    let folderItem = NSMenuItem(
                        title: "\(folder.name) (\(folder.shortcuts.count))",
                        action: nil,
                        keyEquivalent: ""
                    )
                    if let folderIcon = NSImage(systemSymbolName: "folder", accessibilityDescription: folder.name) {
                        folderItem.image = folderIcon
                    }

                    let subMenu = NSMenu()
                    if folder.shortcuts.isEmpty {
                        let empty = NSMenuItem(title: "暂无指令", action: nil, keyEquivalent: "")
                        empty.isEnabled = false
                        subMenu.addItem(empty)
                    } else {
                        for item in folder.shortcuts {
                            subMenu.addItem(createShortcutMenuItem(for: item))
                        }
                    }
                    folderItem.submenu = subMenu
                    menu.addItem(folderItem)
                }

                // Add unfiled shortcuts if any
                if !service.unfiledShortcuts.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                    for item in service.unfiledShortcuts {
                        menu.addItem(createShortcutMenuItem(for: item))
                    }
                }
            }
        }

        // MARK: 3. System Section
        menu.addItem(NSMenuItem.separator())

        let openAppItem = NSMenuItem(
            title: "打开快捷指令 App...",
            action: #selector(actionTarget.handleOpenShortcutsApp),
            keyEquivalent: ""
        )
        openAppItem.target = actionTarget
        if let appIcon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) {
            openAppItem.image = appIcon
        }
        actionTarget.openShortcutsAppHandler = { [weak self] in
            if let custom = self?.onOpenShortcutsApp {
                custom()
            } else {
                let url = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
                NSWorkspace.shared.open(url)
            }
        }
        menu.addItem(openAppItem)

        let settingsItem = NSMenuItem(
            title: "偏好设置...",
            action: #selector(actionTarget.handleOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = actionTarget
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            settingsItem.image = gear
        }
        actionTarget.openSettingsHandler = { [weak self] in
            self?.onOpenSettings?()
        }
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "退出 Shortcuts Bar",
            action: #selector(actionTarget.handleQuit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = actionTarget
        actionTarget.quitHandler = {
            NSApplication.shared.terminate(nil)
        }
        menu.addItem(quitItem)

        return menu
    }

    private func createShortcutMenuItem(for item: ShortcutItem) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: item.name,
            action: #selector(actionTarget.handleShortcutClicked(_:)),
            keyEquivalent: ""
        )
        menuItem.target = actionTarget
        menuItem.representedObject = item.name

        // Set clean HIG SF Symbol template icon
        if let icon = NSImage(systemSymbolName: "command", accessibilityDescription: item.name) {
            icon.isTemplate = true
            menuItem.image = icon
        }

        actionTarget.shortcutClickHandler[item.name] = { [weak self] name in
            guard let manager = self?.processManager else { return }
            do {
                try manager.launch(shortcutName: name)
            } catch {
                NSLog("Failed to launch shortcut '\(name)': \(error)")
            }
        }

        return menuItem
    }

    // MARK: - NSMenuDelegate
    public func menuNeedsUpdate(_ menu: NSMenu) {
        // Rebuild menu contents dynamically on open
        let updated = buildMenu()
        menu.removeAllItems()
        for item in updated.items {
            menu.addItem(item.copy() as! NSMenuItem)
        }
    }
}

// Helper target class for AppKit target-action selector handling
private final class MenuActionTarget: NSObject {
    var shortcutClickHandler: [String: (String) -> Void] = [:]
    var stopAllHandler: (() -> Void)?
    var openShortcutsAppHandler: (() -> Void)?
    var openSettingsHandler: (() -> Void)?
    var quitHandler: (() -> Void)?

    @objc func handleShortcutClicked(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        shortcutClickHandler[name]?(name)
    }

    @objc func handleStopAll() {
        stopAllHandler?()
    }

    @objc func handleOpenShortcutsApp() {
        openShortcutsAppHandler?()
    }

    @objc func handleOpenSettings() {
        openSettingsHandler?()
    }

    @objc func handleQuit() {
        quitHandler?()
    }
}
