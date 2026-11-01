import XCTest
import AppKit
@testable import ShortcutsBarCore

final class DualModeIntegrationTests: XCTestCase {
    @MainActor
    func testEndToEndDualModeAndTaskLifecycle() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Office\nDev"
        mock.responses["list --folder-name Office"] = "Summarize Meeting\nSend Report"
        mock.responses["list --folder-name Dev"] = "Git Commit\nDeploy Staging"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.integration.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        let menuBarView = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: processManager
        )

        // 1. Initial State verification
        panelController.show()
        XCTAssertTrue(panelController.isPresented)
        XCTAssertEqual(vm.visibleItems.count, 4)
        XCTAssertNotNil(menuBarView.body)

        // 2. Launch a shortcut from floating panel
        let targetItem = vm.visibleItems[0].item
        vm.execute(item: targetItem)

        // Since isPinned is false, panel should auto-dismiss on execution
        XCTAssertFalse(panelController.isPresented)

        // ProcessManager has 1 active task
        XCTAssertEqual(processManager.activeTasks.count, 1)
        XCTAssertEqual(processManager.activeTasks[0].shortcutName, "Summarize Meeting")

        // 3. MenuBarView now reflects active task
        XCTAssertEqual(processManager.activeTasks.count, 1)

        // 4. Simulate task completion with success
        let activePid = spawner.activePids.first!
        spawner.simulateTermination(pid: activePid, status: 0)

        // Yield to allow @MainActor Task observer in ViewModel to process completion
        try await Task.sleep(nanoseconds: 50_000_000)

        // ProcessManager queue should be empty
        XCTAssertEqual(processManager.activeTasks.count, 0)

        // Re-open panel: task tray should show completed task feedback
        panelController.show()
        XCTAssertTrue(panelController.isPresented)
        let feedback = vm.completedTasks.values.first
        XCTAssertNotNil(feedback)
        XCTAssertEqual(feedback?.shortcutName, "Summarize Meeting")
        XCTAssertEqual(feedback?.isSuccess, true)

        // 5. Test empty search state
        vm.searchQuery = "nonexistent_query_xyz"
        XCTAssertEqual(vm.visibleItems.count, 0)

        // Clear search
        vm.searchQuery = ""
        XCTAssertEqual(vm.visibleItems.count, 4)
    }

    @MainActor
    func testSilentLibraryHotSyncIntegration() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "General"
        mock.responses["list --folder-name General"] = "Initial Task"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.sync.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: ProcessManager(),
            preferencesStore: store,
            panelController: panelController
        )

        panelController.show()
        vm.searchQuery = "Init"
        XCTAssertEqual(vm.visibleItems.count, 1)

        // Background update adds a new shortcut
        mock.responses["list --folder-name General"] = "Initial Task\nNewly Added Task"
        _ = try? await service.refreshCache()
        vm.refreshData()

        // Search text and filtering should be preserved silently
        XCTAssertEqual(vm.searchQuery, "Init")
        XCTAssertEqual(vm.visibleItems.count, 1)
        XCTAssertEqual(vm.visibleItems[0].id, "Initial Task")

        // Clear search: newly added task should now appear in the list
        vm.searchQuery = ""
        XCTAssertEqual(vm.visibleItems.count, 2)
        XCTAssertEqual(vm.visibleItems[1].id, "Newly Added Task")
    }
}
