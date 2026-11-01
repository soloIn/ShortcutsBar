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

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeTasks: [RunningTask] = []
    @State private var folders: [ShortcutsFolder] = []
    @State private var flatShortcuts: [ShortcutItem] = []
    @State private var folderScope: FolderScope = .leaf(folderName: "快捷指令")
    @State private var expandedFolders: Set<String> = []

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
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 5) {
                // MARK: 1. Active Running Tasks
                if !activeTasks.isEmpty {
                    runningTasksSection
                    Divider()
                        .opacity(colorScheme == .dark ? 0.15 : 0.10)
                }

                // MARK: 2. Shortcuts Items
                shortcutsSection

                Divider()
                    .opacity(colorScheme == .dark ? 0.15 : 0.10)

                // MARK: 3. System Actions
                systemSection
            }
            .padding(8)
            .frame(width: Self.dropdownWidth)
            .background {
                LiquidGlassBackdropView(cornerRadius: 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.15)
                            : Color.white.opacity(0.35),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var runningTasksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("正在运行 (\(activeTasks.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if activeTasks.count > 1 {
                    Button(action: {
                        processManager.terminateAll()
                    }) {
                        Text("全部终止")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            ForEach(activeTasks) { task in
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)

                    Text(task.actionCount > 0 ? "\(task.actionCount) 步 · \(task.shortcutName)" : task.shortcutName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Button(action: {
                        processManager.terminate(taskId: task.id)
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("终止此任务")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                switch folderScope {
                case .leaf(let folderName):
                    if flatShortcuts.isEmpty {
                        Text("文件夹「\(folderName)」暂无指令")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(flatShortcuts) { item in
                            shortcutRow(item: item)
                        }
                    }

                case .root:
                    if folders.isEmpty && shortcutsService.unfiledShortcuts.isEmpty {
                        Text("暂无快捷指令")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(folders) { folder in
                            let isExpanded = expandedFolders.contains(folder.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if isExpanded {
                                            expandedFolders.remove(folder.name)
                                        } else {
                                            expandedFolders.insert(folder.name)
                                        }
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.accentColor)
                                        Text("\(folder.name) (\(folder.shortcuts.count))")
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isExpanded {
                                    ForEach(folder.shortcuts) { item in
                                        shortcutRow(item: item, indentation: 16)
                                    }
                                }
                            }
                        }

                        if !shortcutsService.unfiledShortcuts.isEmpty {
                            Divider()
                                .opacity(colorScheme == .dark ? 0.12 : 0.08)
                            ForEach(shortcutsService.unfiledShortcuts) { item in
                                shortcutRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private func shortcutRow(item: ShortcutItem, indentation: CGFloat = 0) -> some View {
        let iconImage = ShortcutIconRenderer.shared.icon(for: item, size: 14)
        return MenuBarRowItem(
            title: item.name,
            customImage: iconImage,
            indentation: indentation
        ) {
            _ = try? processManager.launch(shortcutName: item.name, actionCount: item.actionCount)
            onDismiss?()
        }
    }

    private var globalHotkeyDisplayString: String {
        guard let code = preferencesStore.globalHotkeyCode,
              let mods = preferencesStore.globalHotkeyModifiers else {
            return "⌘ ⌥ P"
        }
        return HotkeyHelper.string(for: code, modifiers: mods)
    }

    private var systemSection: some View {
        VStack(spacing: 2) {
            MenuBarRowItem(
                title: "快捷指令浮窗",
                icon: "macwindow.on.rectangle",
                shortcut: globalHotkeyDisplayString
            ) {
                onDismiss?()
                onOpenFloatingPanel?()
            }

            MenuBarRowItem(
                title: "打开快捷指令 App",
                icon: "arrow.up.forward.app"
            ) {
                onDismiss?()
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                    NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    let fallbackURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
                    NSWorkspace.shared.openApplication(at: fallbackURL, configuration: NSWorkspace.OpenConfiguration())
                }
            }

            MenuBarRowItem(
                title: "设置...",
                icon: "gearshape",
                shortcut: "⌘ ,"
            ) {
                onDismiss?()
                if let custom = onOpenSettings {
                    custom()
                } else {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }

            Divider()
                .opacity(colorScheme == .dark ? 0.15 : 0.10)

            MenuBarRowItem(
                title: "退出 Shortcuts Bar",
                icon: "power",
                shortcut: "⌘ Q",
                isDestructive: true
            ) {
                NSApp.terminate(nil)
            }
        }
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

// MARK: - Row Helper Component

private struct MenuBarRowItem: View {
    let title: String
    var icon: String? = nil
    var customImage: NSImage? = nil
    var shortcut: String? = nil
    var indentation: CGFloat = 0
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if indentation > 0 {
                    Spacer().frame(width: indentation - 8)
                }
                if let custom = customImage {
                    Image(nsImage: custom)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(isDestructive ? Color.red : Color.secondary)
                        .frame(width: 14)
                }

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let sc = shortcut {
                    Text(sc)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHovered
                    ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
