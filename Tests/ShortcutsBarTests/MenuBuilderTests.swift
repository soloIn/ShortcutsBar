import XCTest
@testable import ShortcutsBarCore

final class MenuBuilderTests: XCTestCase {
    @MainActor
    func testInlineQueueWhenThreeOrFewerTasks() throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Menu Bar"
        mock.responses["list --folder-name Menu Bar"] = "Task A\nTask B"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        _ = try manager.launch(shortcutName: "Running 1")
        _ = try manager.launch(shortcutName: "Running 2")

        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager
        builder.currentScope = .leaf(folderName: "Menu Bar")

        let menu = builder.buildMenu()

        // With 2 running tasks, first 2 items should be inline running tasks (holding RunningTaskView)
        XCTAssertNotNil(menu.items[0].view as? RunningTaskView)
        XCTAssertNotNil(menu.items[1].view as? RunningTaskView)
        XCTAssertTrue(menu.items[2].isSeparatorItem)
    }

    @MainActor
    func testCollapsedSubmenuWhenMoreThanThreeTasks() throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Menu Bar"
        mock.responses["list --folder-name Menu Bar"] = "Task A"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        // Launch 4 tasks (>3 threshold)
        _ = try manager.launch(shortcutName: "Task 1")
        _ = try manager.launch(shortcutName: "Task 2")
        _ = try manager.launch(shortcutName: "Task 3")
        _ = try manager.launch(shortcutName: "Task 4")

        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager
        builder.currentScope = .leaf(folderName: "Menu Bar")

        let menu = builder.buildMenu()

        // First item should be the collapsed submenu item
        let collapsedItem = menu.items[0]
        XCTAssertTrue(collapsedItem.title.contains("正在运行的任务 (4)"))
        XCTAssertNotNil(collapsedItem.submenu)

        let subMenu = collapsedItem.submenu!
        // Should have 4 task items, 1 separator, 1 stop all item
        XCTAssertEqual(subMenu.items.count, 6)
        XCTAssertNotNil(subMenu.items[0].view as? RunningTaskView)
        XCTAssertNotNil(subMenu.items[1].view as? RunningTaskView)
        XCTAssertNotNil(subMenu.items[2].view as? RunningTaskView)
        XCTAssertNotNil(subMenu.items[3].view as? RunningTaskView)
        XCTAssertTrue(subMenu.items[4].isSeparatorItem)
        XCTAssertTrue(subMenu.items[5].title.contains("终止所有"))
    }

    @MainActor
    func testRootFolderScopeSubmenus() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Work\nMedia"
        mock.responses["list --folder-name Work"] = "Draft Report"
        mock.responses["list --folder-name Media"] = "Compress Image"
        mock.responses["list --folder-name none"] = "Unfiled Item"

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager
        builder.currentScope = .root

        let menu = builder.buildMenu()

        // In root mode, top items are folders with submenus
        let workItem = menu.items.first { $0.title.contains("Work") }
        XCTAssertNotNil(workItem)
        XCTAssertNotNil(workItem?.submenu)
        XCTAssertEqual(workItem?.submenu?.items[0].title, "Draft Report")

        let mediaItem = menu.items.first { $0.title.contains("Media") }
        XCTAssertNotNil(mediaItem)
        XCTAssertNotNil(mediaItem?.submenu)
        XCTAssertEqual(mediaItem?.submenu?.items[0].title, "Compress Image")
    }
}
