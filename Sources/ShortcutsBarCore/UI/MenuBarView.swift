import SwiftUI
import AppKit

public struct MenuBarView: View {
    public static let dropdownWidth: CGFloat = 280

    public let preferencesStore: PreferencesStore
    public let shortcutsService: ShortcutsService
    public let processManager: ProcessManager
    public var onOpenFloatingPanel: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onDismiss: (() -> Void)?

    @State private var activeTasks: [RunningTask] = []
    @State private var folders: [ShortcutsFolder] = []
    @State private var flatShortcuts: [ShortcutItem] = []
    @State private var folderScope: FolderScope = .leaf(folderName: "快捷指令")

    public init(
        preferencesStore: PreferencesStore = .shared,
        shortcutsService: ShortcutsService,
        processManager: ProcessManager,
        onOpenFloatingPanel: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.shortcutsService = shortcutsService
        self.processManager = processManager
        self.onOpenFloatingPanel = onOpenFloatingPanel
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            // MARK: 1. Active Running Tasks
            if !activeTasks.isEmpty {
                runningTasksSection
                Divider()
            }

            // MARK: 2. Shortcuts Items
            shortcutsSection

            Divider()

            // MARK: 3. System Actions
            systemSection
        }
        .onAppear {
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessManager.taskQueueChangedNotification)) { _ in
            self.activeTasks = processManager.activeTasks
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesStore.preferencesChangedNotification)) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutsService.didUpdateCacheNotification)) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutsService.cacheUpdatedLegacyNotification)) { _ in
            refreshData()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var runningTasksSection: some View {
        ForEach(activeTasks) { task in
            Button(action: {
                processManager.terminate(taskId: task.id)
            }) {
                Label(
                    task.actionCount > 0 ? "\(task.actionCount) 步 · \(task.shortcutName)" : task.shortcutName,
                    systemImage: "stop.circle"
                )
            }
        }
        if activeTasks.count > 1 {
            Button(role: .destructive, action: {
                processManager.terminateAll()
            }) {
                Label("全部终止", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        switch folderScope {
        case .leaf(let folderName):
            if flatShortcuts.isEmpty {
                Text("文件夹「\(folderName)」暂无指令")
            } else {
                ForEach(flatShortcuts) { item in
                    shortcutButton(item: item)
                }
            }

        case .root:
            if folders.isEmpty && shortcutsService.unfiledShortcuts.isEmpty {
                Text("暂无快捷指令")
            } else {
                ForEach(folders) { folder in
                    Menu(folder.name) {
                        ForEach(folder.shortcuts) { item in
                            shortcutButton(item: item)
                        }
                    }
                }

                if !shortcutsService.unfiledShortcuts.isEmpty {
                    Divider()
                    ForEach(shortcutsService.unfiledShortcuts) { item in
                        shortcutButton(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutButton(item: ShortcutItem) -> some View {
        let customIcon = ShortcutIconRenderer.shared.icon(for: item, size: 14)
        Button(action: {
            _ = try? processManager.launch(shortcutName: item.name, actionCount: item.actionCount)
            onDismiss?()
        }) {
            Label {
                Text(item.name)
            } icon: {
                Image(nsImage: customIcon)
            }
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        Button(action: {
            onDismiss?()
            onOpenFloatingPanel?()
        }) {
            Label("快捷指令浮窗", systemImage: "macwindow.on.rectangle")
        }
        .keyboardShortcut("p", modifiers: [.command, .option])

        Button(action: {
            onDismiss?()
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                let fallbackURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
                NSWorkspace.shared.openApplication(at: fallbackURL, configuration: NSWorkspace.OpenConfiguration())
            }
        }) {
            Label("打开快捷指令 App", systemImage: "arrow.up.forward.app")
        }

        Button(action: {
            onDismiss?()
            if let custom = onOpenSettings {
                custom()
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }) {
            Label("设置...", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(role: .destructive, action: {
            NSApp.terminate(nil)
        }) {
            Label("退出 Shortcuts Bar", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func refreshData() {
        self.activeTasks = processManager.activeTasks
        self.folderScope = preferencesStore.folderScope
        self.folders = shortcutsService.cachedFolders
        var items = shortcutsService.getShortcuts(for: preferencesStore.folderScope)
        let folderName: String = {
            switch preferencesStore.folderScope {
            case .leaf(let name): return name
            case .root: return "全部"
            }
        }()
        let customOrder = preferencesStore.getCustomOrder(for: folderName)
        if !customOrder.isEmpty {
            let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: customOrder.enumerated().map { ($0.element, $0.offset) })
            items.sort { a, b in
                let orderA = orderMap[a.name] ?? Int.max
                let orderB = orderMap[b.name] ?? Int.max
                if orderA != orderB {
                    return orderA < orderB
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        self.flatShortcuts = items
    }
}
