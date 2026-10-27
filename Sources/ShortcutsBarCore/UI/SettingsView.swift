import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                Picker("展示作用域：", selection: $viewModel.selectedScopeTag) {
                    Text("所有快捷指令 (层级子菜单)").tag("__ROOT__")
                    Divider()
                    ForEach(viewModel.availableFolders, id: \.self) { folder in
                        Text("\(folder) (纯扁平)").tag(folder)
                    }
                }
                .pickerStyle(.menu)

                Text("选择根目录将以二级子菜单组织文件夹；选择单个文件夹则在主菜单纯扁平秒点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("快捷指令目录")
            }

            Section {
                Toggle("登录时自动启动 (Launch at Login)", isOn: $viewModel.launchAtLogin)
                Toggle("执行失败时发送通知", isOn: $viewModel.notifyOnFailure)
            } header: {
                Text("通用设置")
            }

            Section {
                HStack {
                    Text("快捷指令总数")
                    Spacer()
                    Text("\(viewModel.totalShortcutsCount) 个")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("状态信息")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
        .padding(10)
    }
}

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

    @Published public var availableFolders: [String] = []
    @Published public var totalShortcutsCount: Int = 0

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

        loadFolders()
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
