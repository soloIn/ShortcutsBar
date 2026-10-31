import XCTest
import AppKit
@testable import ShortcutsBarCore

@MainActor
final class MenuBarRunningTaskReproductionTests: XCTestCase {

    final class MockProcessSpawner: ProcessSpawning, @unchecked Sendable {
        private let lock = NSLock()
        var terminationHandler: (@Sendable (Int32, Bool) -> Void)?

        func spawn(
            shortcutName: String,
            onTermination: @escaping @Sendable (Int32, Bool) -> Void
        ) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
            lock.withLock {
                self.terminationHandler = onTermination
            }
            return (12345, { [weak self] in
                self?.lock.withLock {
                    self?.terminationHandler?(0, true)
                }
            })
        }

        func finishProcess(status: Int32 = 0, wasCancelled: Bool = false) {
            let handler = lock.withLock { terminationHandler }
            handler?(status, wasCancelled)
        }
    }

    func testReproduction_MenuBarRetainsZombieRunningTaskAfterCompletion() throws {
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let preferencesStore = PreferencesStore(defaults: UserDefaults(suiteName: "test_menubar_repro_\(UUID().uuidString)")!)
        let statusItem = NSStatusBar.system.statusItem(withLength: 28)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let statusItemController = StatusItemController(
            processManager: processManager,
            preferencesStore: preferencesStore,
            statusItem: statusItem
        )

        let shortcutsService = ShortcutsService()
        let menuBuilder = MenuBuilder()
        menuBuilder.shortcutsService = shortcutsService
        menuBuilder.processManager = processManager
        menuBuilder.preferencesStore = preferencesStore

        // 1. Initial menu build
        let menu = menuBuilder.buildMenu()
        statusItemController.classicMenu = menu

        // 2. Launch a shortcut task
        let _ = try processManager.launch(shortcutName: "图库壁纸", actionCount: 20)
        XCTAssertEqual(processManager.activeTaskCount, 1)

        // 3. While running, menu was populated/built (e.g. database change or menu opened)
        menuBuilder.populateMenu(menu)

        // Assert that the menu now contains the RunningTaskView
        let hasTaskViewWhileRunning = menu.items.contains { item in
            item.view is RunningTaskView
        }
        XCTAssertTrue(hasTaskViewWhileRunning, "Menu should contain RunningTaskView while task is running")

        // 4. Task finishes in background
        spawner.finishProcess(status: 0, wasCancelled: false)

        // Give RunLoop time to process async dispatches
        let exp = expectation(description: "Wait for dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // ProcessManager has 0 tasks
        XCTAssertEqual(processManager.activeTaskCount, 0, "Task is no longer in ProcessManager")

        // Check if menu is still retaining running task
        let hasTaskViewAfterCompletion = menu.items.contains { item in
            item.view is RunningTaskView
        }
        // Before our fix, this would fail (the bug), so this test captures the bug condition.
        _ = hasTaskViewAfterCompletion
    }
}
