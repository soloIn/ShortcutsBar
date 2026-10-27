import AppKit

@MainActor
public final class MenuBuilder: NSObject, NSMenuDelegate {
    public weak var shortcutsService: ShortcutsService?
    public weak var processManager: ProcessManager?
    public var currentScope: FolderScope = .leaf(folderName: "Menu Bar")

    public var onOpenSettings: (() -> Void)?
    public var onOpenShortcutsApp: (() -> Void)?

    private var isMenuVisible = false
    private var pendingTaskViews: [WeakRunningTaskView] = []

    private struct WeakRunningTaskView {
        weak var view: RunningTaskView?
    }

    public func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        populateMenu(menu)
        return menu
    }

    public func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        pendingTaskViews.removeAll()

        guard let service = shortcutsService, let manager = processManager else {
            let errorItem = NSMenuItem(title: "服务不可用", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            return
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
                        startTime: task.startTime,
                        actionCount: task.actionCount,
                        onStop: { [weak manager] id in
                            manager?.terminate(taskId: id)
                        }
                    )
                    pendingTaskViews.append(WeakRunningTaskView(view: taskView))
                    taskItem.view = taskView
                    menu.addItem(taskItem)
                }
            } else {
                // Collapsed into submenu (count > 3)
                let summaryItem = NSMenuItem(
                    title: "正在运行的任务 (\(activeTasks.count))",
                    action: nil,
                    keyEquivalent: ""
                )
                summaryItem.image = ShortcutsIconFactory.createRunningShortcutsIcon(size: 16)

                let subMenu = NSMenu()
                for task in activeTasks {
                    let taskItem = NSMenuItem()
                    let taskView = RunningTaskView(
                        taskId: task.id,
                        taskName: task.shortcutName,
                        startTime: task.startTime,
                        actionCount: task.actionCount,
                        onStop: { [weak manager] id in
                            manager?.terminate(taskId: id)
                        }
                    )
                    pendingTaskViews.append(WeakRunningTaskView(view: taskView))
                    taskItem.view = taskView
                    subMenu.addItem(taskItem)
                }

                subMenu.addItem(NSMenuItem.separator())

                let stopAllItem = NSMenuItem(
                    title: "终止所有正在运行的任务",
                    action: #selector(handleStopAllClicked),
                    keyEquivalent: ""
                )
                if let stopIcon = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil) {
                    stopAllItem.image = stopIcon
                }
                stopAllItem.target = self
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
            action: #selector(handleOpenShortcutsAppClicked),
            keyEquivalent: ""
        )
        openAppItem.target = self
        if let appIcon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) {
            openAppItem.image = appIcon
        }
        menu.addItem(openAppItem)

        // Apple HIG macOS 13+ standard: "设置..." instead of legacy "偏好设置..."
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(handleOpenSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            settingsItem.image = gear
        }
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "退出 Shortcuts Bar",
            action: #selector(handleQuitClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func createShortcutMenuItem(for item: ShortcutItem) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: item.name,
            action: #selector(handleShortcutClicked(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = item.name

        // Native authentic 16x16 shortcut icon
        menuItem.image = ShortcutIconRenderer.shared.icon(for: item, size: 16)
        return menuItem
    }

    // MARK: - Action Selectors
    @objc private func handleShortcutClicked(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let manager = processManager else { return }
        do {
            try manager.launch(shortcutName: name)
        } catch {
            NSLog("Failed to launch shortcut '\(name)': \(error)")
        }
    }

    @objc private func handleStopAllClicked() {
        processManager?.terminateAll()
    }

    @objc private func handleOpenShortcutsAppClicked() {
        if let custom = onOpenShortcutsApp {
            custom()
        } else {
            let url = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleOpenSettingsClicked() {
        onOpenSettings?()
    }

    @objc private func handleQuitClicked() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate Lifecycle
    public func menuWillOpen(_ menu: NSMenu) {
        isMenuVisible = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        isMenuVisible = false
        // Safely invalidate active task view timers on menu close
        for weakItem in pendingTaskViews {
            weakItem.view?.stopTimer()
        }
        pendingTaskViews.removeAll()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        if let service = shortcutsService,
           let last = service.lastRefreshed,
           ShortcutsDatabaseWatcher.shared.hasChanged(since: last) {
            Task { @MainActor [weak self, weak menu] in
                _ = try? await service.refreshCache()
                // Only replace items if menu is not actively being tracked
                if let self = self, let m = menu, !self.isMenuVisible {
                    self.populateMenu(m)
                }
            }
        }
        populateMenu(menu)
    }
}
