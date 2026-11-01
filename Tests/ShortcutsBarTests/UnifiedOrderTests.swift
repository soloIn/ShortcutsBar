import XCTest
@testable import ShortcutsBarCore

final class UnifiedOrderTests: XCTestCase {
    private var mock: MockShortcutsCLIExecutor!
    private var service: ShortcutsService!
    private var store: PreferencesStore!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockShortcutsCLIExecutor()
        mock.responses["list"] = "Task 1\nTask 2\nTask 3\nTask 4\nTask 5"
        mock.responses["list --folders"] = "Work\nPersonal"
        mock.responses["list --folder-name Work"] = "Task 1\nTask 2\nTask 3"
        mock.responses["list --folder-name Personal"] = "Task 4\nTask 5"
        mock.responses["list --folder-name none"] = ""

        service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        store = PreferencesStore(defaults: UserDefaults(suiteName: "test.unified.order.\(UUID().uuidString)")!)
    }

    // 1. 验证默认情况下（未拖拽排序），顺序完全保持快捷指令 App 原生顺序
    func testDefaultOrderingMatchesSystemOrder() {
        let workShortcuts = service.getShortcuts(for: .leaf(folderName: "Work"))
        let sorted = ShortcutsSearchEngine.sortShortcuts(workShortcuts, customOrder: [])
        XCTAssertEqual(sorted.map { $0.name }, ["Task 1", "Task 2", "Task 3"])
    }

    // 2. 验证自定义排序后，已在列表中的按自定义顺序，新加入的项保持系统原生相对顺序排在后面
    func testCustomOrderingWithNewOrphanItems() {
        let items = [
            ShortcutItem(name: "A"),
            ShortcutItem(name: "B"),
            ShortcutItem(name: "C"),
            ShortcutItem(name: "D")
        ]
        // 用户只对 B 和 A 排了序（B在A前），C 和 D 是系统新加的
        let customOrder = ["B", "A"]
        let sorted = ShortcutsSearchEngine.sortShortcuts(items, customOrder: customOrder)

        // B, A 应该在前，C, D 保持原生相对顺序在后
        XCTAssertEqual(sorted.map { $0.name }, ["B", "A", "C", "D"])
    }

    // 3. 验证悬浮窗与菜单栏排序投影在 Root 模式下各个子文件夹均 100% 保持一致
    @MainActor
    func testFloatingPanelAndMenuBarOrderConsistencyInRootMode() {
        store.folderScope = .root

        // 模拟用户在 "Work" 文件夹中调整了顺序：Task 3 排在 Task 1 前
        store.setCustomOrder(["Task 3", "Task 1", "Task 2"], for: "Work")

        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: ProcessManager(),
            preferencesStore: store,
            panelController: panelController
        )

        // 悬浮窗选择 "Work" 文件夹
        vm.selectedFolder = "Work"
        let panelWorkNames = vm.visibleItems.map { $0.item.name }

        // 菜单栏中对应 "Work" 文件夹的排序结果
        let rawWorkItems = service.getShortcuts(for: .leaf(folderName: "Work"))
        let menuBarWorkItems = ShortcutsSearchEngine.sortShortcuts(
            rawWorkItems,
            customOrder: store.getCustomOrder(for: "Work")
        ).map { $0.name }

        // 核心断言：悬浮窗与菜单栏中的项目顺序必须 100% 严格一致！
        XCTAssertEqual(panelWorkNames, ["Task 3", "Task 1", "Task 2"])
        XCTAssertEqual(panelWorkNames, menuBarWorkItems)
    }
}
