import XCTest
import SwiftUI
@testable import ShortcutsBarCore

final class MenuBarViewTests: XCTestCase {
    @MainActor
    func testMenuBarView_WithRunningTasks() throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Menu Bar"
        mock.responses["list --folder-name Menu Bar"] = "Task A\nTask B"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        _ = try manager.launch(shortcutName: "Running 1")
        _ = try manager.launch(shortcutName: "Running 2")

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.menubar.\(UUID().uuidString)")!)
        store.folderScope = .leaf(folderName: "Menu Bar")

        let view = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: manager
        )

        XCTAssertNotNil(view.body)
        XCTAssertEqual(manager.activeTasks.count, 2)
    }

    @MainActor
    func testMenuBarView_WithMultipleRunningTasks() throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Menu Bar"
        mock.responses["list --folder-name Menu Bar"] = "Task A"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        _ = try manager.launch(shortcutName: "Task 1")
        _ = try manager.launch(shortcutName: "Task 2")
        _ = try manager.launch(shortcutName: "Task 3")
        _ = try manager.launch(shortcutName: "Task 4")

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.menubar.\(UUID().uuidString)")!)
        store.folderScope = .leaf(folderName: "Menu Bar")

        let view = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: manager
        )

        XCTAssertNotNil(view.body)
        XCTAssertEqual(manager.activeTasks.count, 4)
    }

    @MainActor
    func testMenuBarView_RootFolderScopeSubmenus() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Work\nMedia"
        mock.responses["list --folder-name Work"] = "Draft Report"
        mock.responses["list --folder-name Media"] = "Compress Image"
        mock.responses["list --folder-name none"] = "Unfiled Item"

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.menubar.\(UUID().uuidString)")!)
        store.folderScope = .root

        let view = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: manager
        )

        XCTAssertNotNil(view.body)
        XCTAssertEqual(service.cachedFolders.count, 2)
    }
}
