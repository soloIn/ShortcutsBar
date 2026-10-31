import XCTest
import AppKit
@testable import ShortcutsBarCore

final class BugVerificationBlackboxTests: XCTestCase {

    final class ThreadSafeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func increment() { lock.withLock { _count += 1 } }
    }

    // MARK: - Bug 1 Resolution: ProcessManager 多播与事件驱动模型彻底杜绝观察者踩踏
    @MainActor
    func testBug1_ProcessManagerObserverTrampling() async throws {
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.bug1.\(UUID().uuidString)")!)

        // 1. Initial subscriber (simulating StatusItemController)
        let firstObserverQueueCount = ThreadSafeCounter()
        let firstObserverCompletedCount = ThreadSafeCounter()

        processManager.addQueueObserver { _ in
            firstObserverQueueCount.increment()
        }
        processManager.addTaskCompletedObserver { _, _ in
            firstObserverCompletedCount.increment()
        }

        // 2. Second subscriber (FloatingPanelViewModel) initializes and binds to the SAME processManager
        let panelController = FloatingPanelController(preferencesStore: store)
        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        // 3. Trigger a task launch and termination through ProcessManager
        let taskId = try processManager.launch(shortcutName: "Bug1VerificationTask")
        if let pid = spawner.activePids.first {
            spawner.simulateTermination(pid: pid, status: 0)
        }

        // 4. Assertions:
        // With multicast architecture, both FloatingPanelViewModel AND the first observer receive all events!
        XCTAssertGreaterThan(
            firstObserverQueueCount.count,
            0,
            "FIX VERIFIED: First observer reliably received onQueueChanged notifications via multicast."
        )
        XCTAssertGreaterThan(
            firstObserverCompletedCount.count,
            0,
            "FIX VERIFIED: First observer reliably received onTaskCompleted notification via multicast."
        )

        // 5. Component integration verification: StatusItemController + FloatingPanelViewModel
        let spawner2 = MockProcessSpawner()
        let processManager2 = ProcessManager(spawner: spawner2)
        let testStatusItem = NSStatusBar.system.statusItem(withLength: 28)
        let statusItemController = StatusItemController(
            processManager: processManager2,
            preferencesStore: store,
            statusItem: testStatusItem
        )

        // FloatingPanelViewModel is initialized after StatusItemController (identical to AppDelegate lifecycle)
        let viewModel2 = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: processManager2,
            preferencesStore: store,
            panelController: panelController
        )

        _ = try processManager2.launch(shortcutName: "StatusItemStompTask")

        // Yield to main runloop so StatusItemController's DispatchQueue.main.async completes
        try await Task.sleep(nanoseconds: 50_000_000)

        // With multicast event architecture, StatusItemController receives handleQueueChanged and
        // immediately transitions to active spinner state, adding ScriptMonitorSpinnerView!
        let hasSpinnerInButton = statusItemController.statusItem?.button?.subviews.contains { $0 is ScriptMonitorSpinnerView } ?? false
        XCTAssertTrue(
            hasSpinnerInButton,
            "FIX VERIFIED: StatusItemController successfully transitioned to active spinner state when shortcut was launched!"
        )

        _ = viewModel
        _ = viewModel2
        _ = taskId
    }

    // MARK: - Bug 2: ShortcutsSearchEngine 文件夹筛选前提前去重导致跨文件夹同名指令丢失
    func testBug2_ShortcutsSearchEnginePrematureDeduplicationDropsFolderItems() {
        // Setup two folders: "Folder A" and "Folder B", both having a shortcut named "Backup"
        let backupItemA = ShortcutItem(name: "Backup", folderName: "Folder A")
        let backupItemB = ShortcutItem(name: "Backup", folderName: "Folder B")

        let folderA = ShortcutsFolder(name: "Folder A", shortcuts: [backupItemA])
        let folderB = ShortcutsFolder(name: "Folder B", shortcuts: [backupItemB])

        let engine = ShortcutsSearchEngine()

        // When the user switches to "Folder B" tab:
        let projectedB = engine.project(
            allFolders: [folderA, folderB],
            selectedFolder: "Folder B",
            searchQuery: ""
        )

        // Verified Fix: Folder B displays its own "Backup" shortcut, not dropped by premature deduplication!
        let containsBackupInFolderB = projectedB.contains { $0.item.name == "Backup" }

        XCTAssertTrue(
            containsBackupInFolderB,
            "FIX VERIFIED: 'Backup' in Folder B is legitimately displayed without being dropped by cross-folder deduplication!"
        )
        XCTAssertEqual(
            projectedB.count,
            1,
            "FIX VERIFIED: Folder B shows exactly its 1 shortcut."
        )
    }

    // MARK: - Bug 3: ShortcutsSearchEngine 自定义排序遵循严格弱序与自然排序
    func testBug3_ShortcutsSearchEngineSortingBypassesLocalizedStandardCompare() {
        let engine = ShortcutsSearchEngine()

        let itemPinned = ShortcutItem(name: "Pinned", folderName: "Work")
        let item10 = ShortcutItem(name: "Item 10", folderName: "Work")
        let item2 = ShortcutItem(name: "Item 2", folderName: "Work")

        let folder = ShortcutsFolder(name: "Work", shortcuts: [itemPinned, item10, item2])

        // Verify standard macOS Finder / localizedStandardCompare natural ordering:
        XCTAssertEqual(
            "Item 2".localizedStandardCompare("Item 10"),
            .orderedAscending,
            "localizedStandardCompare puts 'Item 2' before 'Item 10'"
        )

        let customOrders = ["Work": ["Pinned"]]

        let projected = engine.project(
            allFolders: [folder],
            selectedFolder: "Work",
            searchQuery: "",
            customSortOrders: customOrders
        )

        let projectedNames = projected.map { $0.item.name }

        // Verified Fix: Pinned is first, and unpinned items are sorted with localizedStandardCompare ("Item 2" before "Item 10")
        XCTAssertEqual(
            projectedNames,
            ["Pinned", "Item 2", "Item 10"],
            "FIX VERIFIED: 'Item 2' is correctly sorted before 'Item 10' adhering to localizedStandardCompare!"
        )
    }

    // MARK: - Bug 4: 失败任务永久驻留 completedTasks 无法清除
    @MainActor
    func testBug4_FailedTasksPermanentlyRetainedInCompletedTasks() async throws {
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.bug4.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)

        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        // 1. Launch a task that will succeed
        let successTaskId = try processManager.launch(shortcutName: "SuccessTask")
        if let successPid = spawner.activePids.first {
            spawner.simulateTermination(pid: successPid, status: 0) // Exit 0 = success
        }

        // 2. Launch a task that will fail
        let failedTaskId = try processManager.launch(shortcutName: "FailedTask")
        if let failedPid = spawner.activePids.first {
            spawner.simulateTermination(pid: failedPid, status: 1) // Exit 1 = failure
        }

        // Wait a short moment to let initial MainActor tasks register in completedTasks
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(viewModel.completedTasks[successTaskId], "Success task initially present in completedTasks")
        XCTAssertNotNil(viewModel.completedTasks[failedTaskId], "Failed task initially present in completedTasks")
        XCTAssertEqual(viewModel.completedTasks[failedTaskId]?.isSuccess, false)

        // 3. Wait 1.8 seconds (which exceeds the 1.5s auto-fade timeout for success tasks)
        try await Task.sleep(nanoseconds: 1_800_000_000)

        // 4. Assertions:
        // Success task auto-faded and was removed
        XCTAssertNil(viewModel.completedTasks[successTaskId], "Success task was automatically cleaned up after 1.5s")

        // Failed task has NO auto-cleanup timer and NO clear mechanism, so it permanently remains in completedTasks!
        XCTAssertNotNil(
            viewModel.completedTasks[failedTaskId],
            "CONFIRMED BUG: Failed task permanently lingers in completedTasks with no auto-dismiss or cleanup mechanism!"
        )
    }

    // MARK: - Bug 5: PanelKeyInterceptor 拦截 ⌘← / ⌘→ 劫持文本输入框跳行
    @MainActor
    func testBug5_PanelKeyInterceptorHijacksTextNavigationCommandArrowKeys() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.bug5.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)
        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: ProcessManager(),
            preferencesStore: store,
            panelController: panelController
        )

        let interceptor = PanelKeyInterceptor(
            panel: panelController.panel,
            viewModel: viewModel,
            panelController: panelController
        )

        // Set up available folders
        viewModel.availableFolders = ["全部", "Personal", "Work"]
        viewModel.selectedFolder = "全部"

        panelController.show()

        // Construct Command + Left Arrow (keyCode 123)
        // Standard macOS behavior in text input: moveToBeginningOfLine:
        let cmdLeftEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!

        // Construct Command + Right Arrow (keyCode 124)
        // Standard macOS behavior in text input: moveToEndOfLine:
        let cmdRightEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!

        // Test ⌘→ (intended for moving text cursor to end of line in search field)
        let handledRight = interceptor.handleKeyEvent(cmdRightEvent)
        XCTAssertTrue(
            handledRight,
            "CONFIRMED BUG: PanelKeyInterceptor intercepted and consumed ⌘→ (keyCode 124), hijacking system text navigation."
        )
        // Side effect assertion: Instead of moving cursor, folder tab switched to "Personal"
        XCTAssertEqual(
            viewModel.selectedFolder,
            "Personal",
            "CONFIRMED BUG: Interceptor switched tab to 'Personal' instead of allowing text cursor navigation!"
        )

        // Test ⌘← (intended for moving text cursor to beginning of line in search field)
        let handledLeft = interceptor.handleKeyEvent(cmdLeftEvent)
        XCTAssertTrue(
            handledLeft,
            "CONFIRMED BUG: PanelKeyInterceptor intercepted and consumed ⌘← (keyCode 123), hijacking system text navigation."
        )
        // Side effect assertion: Instead of moving cursor, folder tab switched back to "全部"
        XCTAssertEqual(
            viewModel.selectedFolder,
            "全部",
            "CONFIRMED BUG: Interceptor switched tab to '全部' instead of allowing text cursor navigation!"
        )
    }

    // MARK: - Bug 6: ProjectedShortcutItem 唯一标识符碰撞
    func testBug6_ProjectedShortcutItemIdCollision() {
        // Construct two distinct ShortcutItem instances that share the same name
        // (e.g. shortcuts from different folders, or different database IDs)
        let item1 = ShortcutItem(name: "Export", folderName: "Personal", id: "uuid-001", glyph: 10, colorValue: 111)
        let item2 = ShortcutItem(name: "Export", folderName: "Work", id: "uuid-002", glyph: 20, colorValue: 222)

        XCTAssertNotEqual(item1.id, item2.id, "Shortcut items have different database/UUID IDs")
        XCTAssertNotEqual(item1.folderName, item2.folderName, "Shortcut items belong to different folders")
        XCTAssertNotEqual(item1, item2, "Shortcut items are non-equal")

        let projected1 = ProjectedShortcutItem(item: item1, folderName: "Personal")
        let projected2 = ProjectedShortcutItem(item: item2, folderName: "Work")

        // Verified Fix: ProjectedShortcutItem.id delegates to item.id, preserving uniqueness!
        XCTAssertNotEqual(
            projected1.id,
            projected2.id,
            "FIX VERIFIED: ProjectedShortcutItem.id is unique for distinct items with different IDs!"
        )

        let idSet: Set<String> = [projected1.id, projected2.id]
        XCTAssertEqual(
            idSet.count,
            2,
            "FIX VERIFIED: Set maintains 2 distinct elements with unique Identifiable IDs!"
        )
    }

    // MARK: - Bug 7: FloatingPanelController 停靠坐标硬编码主屏，副屏状态栏被瞬移回主屏
    @MainActor
    func testBug7_FloatingPanelControllerHardcodedPrimaryScreenTeleportsSecondaryScreenCoordinates() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.bug7.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        // Case 1: External / secondary monitor located to the right of primary display
        // Primary Screen: x: 0..1920 (width: 1920, height: 1080)
        // Secondary Screen: x: 2560..4480 (width: 1920, height: 1080)
        // A status item button on the secondary screen is placed at x = 3000, y = 1000
        let secondaryWindowRight = NSWindow(
            contentRect: NSRect(x: 3000, y: 1000, width: 30, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let buttonRight = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        secondaryWindowRight.contentView?.addSubview(buttonRight)

        let buttonScreenRectRight = buttonRight.window!.convertToScreen(buttonRight.bounds)
        XCTAssertGreaterThanOrEqual(buttonScreenRectRight.midX, 3000.0, "Button is located in secondary monitor coordinates (x >= 3000)")

        // FloatingPanelController.show(attachedTo:), resetToDocked(), and handleDragEnd()
        // hardcode primaryScreen:
        // let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        // let dockedRect = calculateDockedFrame(for: self.statusButton, on: primaryScreen)
        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let primaryScreenFrame = primaryScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let dockedFrameRight = controller.calculateDockedFrame(for: buttonRight, on: primaryScreen)

        // In buggy FloatingPanelController:
        // targetX is computed from buttonScreenRectRight.midX (~3015)
        // But then it is clamped against primaryScreen.visibleFrame (maxX ~1440 or ~1920 or ~2560)!
        // Because targetX + width > screenRect.maxX - 8:
        // targetX is clamped to primaryScreenFrame.maxX - width - 8!
        // As a result, the dockedFrame is pulled entirely back into the PRIMARY screen:
        XCTAssertLessThanOrEqual(
            dockedFrameRight.maxX,
            primaryScreenFrame.maxX,
            "CONFIRMED BUG: Docked panel frame was forcibly clamped inside the primary screen boundaries!"
        )
        XCTAssertLessThan(
            dockedFrameRight.origin.x,
            2560.0,
            "CONFIRMED BUG: Docked panel was teleported out of the right-hand secondary display (x >= 2560) and onto the primary display!"
        )

        // Case 2: External / secondary monitor located to the left of primary display
        // Secondary Screen (Left): x: -1920..0
        // A status item button on the left secondary screen is placed at x = -500, y = 1000
        let secondaryWindowLeft = NSWindow(
            contentRect: NSRect(x: -500, y: 1000, width: 30, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let buttonLeft = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        secondaryWindowLeft.contentView?.addSubview(buttonLeft)

        let buttonScreenRectLeft = buttonLeft.window!.convertToScreen(buttonLeft.bounds)
        XCTAssertLessThan(buttonScreenRectLeft.midX, 0.0, "Button is located in left-hand secondary monitor coordinates (x < 0)")

        let dockedFrameLeft = controller.calculateDockedFrame(for: buttonLeft, on: primaryScreen)

        // targetX is computed from buttonScreenRectLeft.midX (~ -485)
        // Because targetX < screenRect.minX + 8:
        // targetX is clamped to primaryScreenFrame.minX + 8 (e.g. 0 + 8 = 8)!
        // Panel is pulled from the left display into the primary display:
        XCTAssertGreaterThanOrEqual(
            dockedFrameLeft.origin.x,
            primaryScreenFrame.minX,
            "CONFIRMED BUG: Docked panel frame was pulled from negative coordinates into the primary screen!"
        )
        XCTAssertGreaterThan(
            dockedFrameLeft.origin.x,
            0.0,
            "CONFIRMED BUG: Docked panel was teleported out of the left-hand secondary display (x < 0) and onto the primary display!"
        )
    }
}
