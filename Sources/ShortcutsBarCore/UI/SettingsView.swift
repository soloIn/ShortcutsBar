import SwiftUI
import AppKit

public enum SettingsSidebarItem: String, Hashable, CaseIterable {
    case general
    case floatingPanel
    case folders
    case about

    public var title: String {
        switch self {
        case .general: return "通用"
        case .floatingPanel: return "悬浮窗与热键"
        case .folders: return "文件夹作用域"
        case .about: return "关于"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .floatingPanel: return "macwindow.on.rectangle"
        case .folders: return "folder"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var selectedSidebarItem: SettingsSidebarItem = .general

    public init(viewModel: SettingsViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public init(preferencesStore: PreferencesStore = .shared, shortcutsService: ShortcutsService) {
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(preferencesStore: preferencesStore, shortcutsService: shortcutsService))
    }

    public var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detailView
                .frame(minWidth: 480, minHeight: 400)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 440, idealHeight: 500)
        .onAppear {
            viewModel.loadFolders()
        }
    }

    // MARK: - Sidebar

    private var sidebarList: some View {
        List(selection: $selectedSidebarItem) {
            Section("偏好设置") {
                NavigationLink(value: SettingsSidebarItem.general) {
                    Label(SettingsSidebarItem.general.title, systemImage: SettingsSidebarItem.general.icon)
                }

                NavigationLink(value: SettingsSidebarItem.floatingPanel) {
                    Label(SettingsSidebarItem.floatingPanel.title, systemImage: SettingsSidebarItem.floatingPanel.icon)
                }

                NavigationLink(value: SettingsSidebarItem.folders) {
                    Label(SettingsSidebarItem.folders.title, systemImage: SettingsSidebarItem.folders.icon)
                }

                NavigationLink(value: SettingsSidebarItem.about) {
                    Label(SettingsSidebarItem.about.title, systemImage: SettingsSidebarItem.about.icon)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarItem {
        case .general:
            GeneralSettingsView(viewModel: viewModel)
                .navigationTitle("通用设置")
        case .floatingPanel:
            FloatingPanelSettingsView(viewModel: viewModel)
                .navigationTitle("悬浮窗与热键")
        case .folders:
            ShortcutsFolderSettingsView(viewModel: viewModel)
                .navigationTitle("文件夹作用域")
        case .about:
            AboutSettingsView()
                .navigationTitle("关于 Shortcuts Bar")
        }
    }
}

// MARK: - Subviews

private struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("状态栏与系统通知") {
                Toggle("在菜单栏显示任务运行状态", isOn: $viewModel.showMenuBarRunningStatus)
                Toggle("登录时自动启动 (Launch at Login)", isOn: $viewModel.launchAtLogin)
                Toggle("执行失败时发送通知", isOn: $viewModel.notifyOnFailure)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsFolderSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("文件夹过滤作用域") {
                Picker("展示作用域：", selection: $viewModel.selectedScopeTag) {
                    Text("所有快捷指令 (层级子菜单)").tag("__ROOT__")
                    Divider()
                    ForEach(viewModel.availableFolders, id: \.self) { folder in
                        Text("\(folder) (纯扁平展示)").tag(folder)
                    }
                }
                .pickerStyle(.menu)

                Text("选择根目录将以二级子菜单组织文件夹；选择单个文件夹则在菜单栏纯扁平直接展示。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("快捷指令库统计") {
                LabeledContent("已扫描指令总数") {
                    Text("\(viewModel.totalShortcutsCount) 个")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("已识别文件夹数") {
                    Text("\(viewModel.availableFolders.count) 个")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FloatingPanelSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("全局快捷键呼出") {
                Toggle("启用全局唤起热键", isOn: $viewModel.globalHotkeyEnabled)

                if viewModel.globalHotkeyEnabled {
                    LabeledContent("呼出快捷键") {
                        HotkeyRecorderView(
                            keyCode: $viewModel.globalHotkeyCode,
                            modifiers: $viewModel.globalHotkeyModifiers,
                            onSave: {
                                viewModel.saveHotkey()
                            }
                        )
                    }
                }

                Text("按下设置的全局快捷键即可随时在屏幕最前端呼出快捷指令悬浮窗。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("快捷指令排序") {
                Button("恢复为快捷指令 App 默认顺序") {
                    viewModel.resetAllCustomOrders()
                }
                Text("重置后，悬浮窗与菜单栏下拉列表将完全恢复为 macOS 系统「快捷指令」App 中的原生排列顺序。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: ShortcutsIconFactory.createAppIcon(size: 96))
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

            VStack(spacing: 4) {
                Text("Shortcuts Bar")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Version 1.0 (macOS 26+ · Apple Silicon)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 8) {
                Text("轻量、极速的 macOS 快捷指令伴侣")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("基于原生 SwiftUI NavigationSplitView 与 Liquid Glass 设计语言构建")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ViewModel

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var selectedScopeTag: String {
        didSet {
            if selectedScopeTag == "__ROOT__" {
                preferencesStore.folderScope = .root
            } else {
                preferencesStore.folderScope = .leaf(folderName: selectedScopeTag)
            }
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            preferencesStore.launchAtLogin = launchAtLogin
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
        }
    }

    @Published public var notifyOnFailure: Bool {
        didSet {
            preferencesStore.notifyOnFailure = notifyOnFailure
        }
    }

    @Published public var showMenuBarRunningStatus: Bool {
        didSet {
            preferencesStore.showMenuBarRunningStatus = showMenuBarRunningStatus
        }
    }

    @Published public var primaryClickAction: PrimaryClickAction {
        didSet {
            preferencesStore.primaryClickAction = primaryClickAction
        }
    }

    @Published public var globalHotkeyEnabled: Bool {
        didSet {
            preferencesStore.globalHotkeyEnabled = globalHotkeyEnabled
            if globalHotkeyEnabled && preferencesStore.globalHotkeyCode == nil {
                // Default: ⌥ Space (keyCode 49 for Space, Carbon optionKey = 2048)
                preferencesStore.globalHotkeyCode = 49
                preferencesStore.globalHotkeyModifiers = 2048
                self.globalHotkeyCode = 49
                self.globalHotkeyModifiers = 2048
            }
        }
    }

    @Published public var globalHotkeyCode: UInt32?
    @Published public var globalHotkeyModifiers: UInt32?

    public func saveHotkey() {
        preferencesStore.globalHotkeyCode = globalHotkeyCode
        preferencesStore.globalHotkeyModifiers = globalHotkeyModifiers
    }

    @Published public var availableFolders: [String] = []
    @Published public var totalShortcutsCount: Int = 0

    public var allShortcuts: [ShortcutItem] {
        shortcutsService.allShortcuts
    }

    private let preferencesStore: PreferencesStore
    private let shortcutsService: ShortcutsService

    public init(
        preferencesStore: PreferencesStore = .shared,
        shortcutsService: ShortcutsService
    ) {
        self.preferencesStore = preferencesStore
        self.shortcutsService = shortcutsService

        switch preferencesStore.folderScope {
        case .root:
            self.selectedScopeTag = "__ROOT__"
        case .leaf(let folder):
            self.selectedScopeTag = folder
        }

        self.launchAtLogin = preferencesStore.launchAtLogin
        self.notifyOnFailure = preferencesStore.notifyOnFailure
        self.showMenuBarRunningStatus = preferencesStore.showMenuBarRunningStatus
        self.primaryClickAction = preferencesStore.primaryClickAction
        self.globalHotkeyEnabled = preferencesStore.globalHotkeyEnabled
        self.globalHotkeyCode = preferencesStore.globalHotkeyCode ?? 49
        self.globalHotkeyModifiers = preferencesStore.globalHotkeyModifiers ?? 2048

        loadFolders()
    }

    public func resetAllCustomOrders() {
        preferencesStore.resetAllCustomOrders()
    }

    public func loadFolders() {
        let folders = shortcutsService.cachedFolders
        self.availableFolders = folders.map { $0.name }
        self.totalShortcutsCount = shortcutsService.allShortcuts.count

        if case .leaf(let folder) = preferencesStore.folderScope {
            if !availableFolders.contains(folder) && !availableFolders.isEmpty {
                if availableFolders.contains("Menu Bar") {
                    self.selectedScopeTag = "Menu Bar"
                }
            }
        }
    }
}
