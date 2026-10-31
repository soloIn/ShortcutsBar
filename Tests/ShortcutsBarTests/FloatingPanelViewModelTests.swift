import XCTest
@testable import ShortcutsBarCore

final class FloatingPanelViewModelTests: XCTestCase {
    @MainActor
    func testViewModelInitialStateAndSearch() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Office\nDev"
        mock.responses["list --folder-name Office"] = "Clean Desk\nSend Mail"
        mock.responses["list --folder-name Dev"] = "Run Tests\nBuild App"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.vm.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        XCTAssertEqual(vm.availableFolders, ["全部", "Office", "Dev"])
        XCTAssertEqual(vm.visibleItems.count, 4)
        XCTAssertEqual(vm.highlightedIndex, 0)

        // Select folder "Dev"
        vm.selectedFolder = "Dev"
        XCTAssertEqual(vm.visibleItems.count, 2)
        XCTAssertEqual(vm.visibleItems[0].id, "Run Tests")
        XCTAssertEqual(vm.visibleItems[0].inPanelShortcut, "⌘1")

        // Search query "Mail" -> global across all folders
        vm.searchQuery = "Mail"
        XCTAssertEqual(vm.visibleItems.count, 1)
        XCTAssertEqual(vm.visibleItems[0].id, "Send Mail")
        XCTAssertEqual(vm.visibleItems[0].inPanelShortcut, "⌘1")
    }

    @MainActor
    func testHighlightNavigationAndExecution() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Alpha"
        mock.responses["list --folder-name Alpha"] = "Item 1\nItem 2\nItem 3"
        mock.responses["list --folder-name none"] = ""
        mock.responses["run Item 1"] = ""
        mock.responses["run Item 2"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.vm.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        XCTAssertEqual(vm.highlightedIndex, 0)

        // Move down
        vm.moveHighlight(down: true)
        XCTAssertEqual(vm.highlightedIndex, 1)

        // Move down
        vm.moveHighlight(down: true)
        XCTAssertEqual(vm.highlightedIndex, 2)

        // Move down at boundary
        vm.moveHighlight(down: true)
        XCTAssertEqual(vm.highlightedIndex, 2)

        // Move up
        vm.moveHighlight(down: false)
        XCTAssertEqual(vm.highlightedIndex, 1)

        // Execute highlighted (Item 2)
        vm.executeHighlighted()
        XCTAssertEqual(processManager.activeTasks.count, 1)
        XCTAssertEqual(processManager.activeTasks[0].shortcutName, "Item 2")

        // Execute numbered (Item 1 via index 0)
        vm.executeNumbered(index: 0)
        XCTAssertEqual(processManager.activeTasks.count, 2)
    }

    @MainActor
    func testReorderingAndLockingDuringSearch() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Folder"
        mock.responses["list --folder-name Folder"] = "A\nB\nC"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.vm.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        vm.selectedFolder = "Folder"
        XCTAssertEqual(vm.visibleItems.map { $0.id }, ["A", "B", "C"])

        // Move C (index 2) to index 0
        vm.reorderVisibleItems(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(vm.visibleItems.map { $0.id }, ["C", "A", "B"])
        XCTAssertEqual(store.getCustomOrder(for: "Folder"), ["C", "A", "B"])

        // Now start searching: reorder should be locked/ignored
        vm.searchQuery = "A"
        vm.reorderVisibleItems(from: IndexSet(integer: 0), to: 1)
        // Store should remain unchanged
        XCTAssertEqual(store.getCustomOrder(for: "Folder"), ["C", "A", "B"])
    }

    @MainActor
    func testPinToggling() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.vm.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)
        let service = ShortcutsService()
        let processManager = ProcessManager()

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        XCTAssertFalse(vm.isPinned)
        XCTAssertFalse(store.isPinned)

        vm.togglePin()
        XCTAssertTrue(vm.isPinned)
        XCTAssertTrue(store.isPinned)
        XCTAssertEqual(panelController.panel.level, .floating)
        XCTAssertTrue(panelController.panel.collectionBehavior.contains(.canJoinAllSpaces))

        vm.togglePin()
        XCTAssertFalse(vm.isPinned)
        XCTAssertFalse(store.isPinned)
        XCTAssertEqual(panelController.panel.level, .floating)
    }

    @MainActor
    func testFolderTabCycling() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Alpha\nBeta"
        mock.responses["list --folder-name Alpha"] = "A1"
        mock.responses["list --folder-name Beta"] = "B1"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.vm.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        XCTAssertEqual(vm.availableFolders, ["全部", "Alpha", "Beta"])
        XCTAssertEqual(vm.selectedFolder, "全部")

        // Cycle forward
        vm.selectNextFolder()
        XCTAssertEqual(vm.selectedFolder, "Alpha")

        vm.selectNextFolder()
        XCTAssertEqual(vm.selectedFolder, "Beta")

        vm.selectNextFolder()
        XCTAssertEqual(vm.selectedFolder, "全部")

        // Cycle backward
        vm.selectPreviousFolder()
        XCTAssertEqual(vm.selectedFolder, "Beta")

        vm.selectPreviousFolder()
        XCTAssertEqual(vm.selectedFolder, "Alpha")
    }

    @MainActor
    func testViewModelLeafFolderScopeSingleSource() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "快捷指令\nMac\niPhone"
        mock.responses["list --folder-name 快捷指令"] = "Shortcut A\nShortcut B"
        mock.responses["list --folder-name Mac"] = "Mac Only"
        mock.responses["list --folder-name iPhone"] = "iPhone Only"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.leaf.\(UUID().uuidString)")!)
        store.folderScope = .leaf(folderName: "快捷指令")

        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: ProcessManager(),
            preferencesStore: store,
            panelController: panelController
        )

        // Leaf mode: no submenus, no multi-tabs!
        XCTAssertFalse(vm.hasSubmenus)
        XCTAssertEqual(vm.availableFolders, ["快捷指令"])
        XCTAssertEqual(vm.selectedFolder, "快捷指令")
        XCTAssertEqual(vm.visibleItems.count, 2)
        XCTAssertEqual(vm.visibleItems.map { $0.id }, ["Shortcut A", "Shortcut B"])

        // Search within this single folder
        vm.searchQuery = "Shortcut A"
        XCTAssertEqual(vm.visibleItems.count, 1)
        XCTAssertEqual(vm.visibleItems[0].id, "Shortcut A")
    }
}
