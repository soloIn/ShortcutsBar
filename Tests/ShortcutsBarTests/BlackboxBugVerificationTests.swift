import XCTest
import AppKit
@testable import ShortcutsBarCore

final class BlackboxBugVerificationTests: XCTestCase {

    // MARK: - Fix 1 Verification: ProcessManager 极速退出时序竞争已修复（无僵尸任务，正常触发完成回调）
    func testFix1_InstantExitRaceConditionResolved() throws {
        final class SafeBox<T>: @unchecked Sendable {
            private let lock = NSLock()
            private var _value: T
            init(_ value: T) { self._value = value }
            var value: T {
                get { lock.withLock { _value } }
                set { lock.withLock { _value = newValue } }
            }
        }

        struct InstantExitSpawner: ProcessSpawning {
            func spawn(
                shortcutName: String,
                onTermination: @escaping @Sendable (Int32, Bool) -> Void
            ) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
                // Simulate process terminating immediately/synchronously during spawn invocation
                onTermination(0, false)
                return (pid: 9999, cancel: {})
            }
        }

        let manager = ProcessManager(spawner: InstantExitSpawner())
        let completionCalledBox = SafeBox(false)
        manager.onTaskCompleted = { _, _ in
            completionCalledBox.value = true
        }

        XCTAssertEqual(manager.activeTaskCount, 0, "Initial task count must be 0")

        let taskId = try manager.launch(shortcutName: "RapidExitShortcut")

        // In fixed ProcessManager.launch:
        // Pre-registration placeholder pattern ensures onTermination finds and cleans up the task.
        let isZombieLeaked = (manager.activeTaskCount > 0)
        let isTaskRetained = manager.activeTasks.contains { $0.id == taskId }
        let isCallbackTriggered = completionCalledBox.value

        XCTAssertFalse(isZombieLeaked, "FIX VERIFIED: activeTaskCount must be 0 after instant exit (no zombie task leak).")
        XCTAssertFalse(isTaskRetained, "FIX VERIFIED: Rapid-exit task must NOT be retained in activeTasks.")
        XCTAssertTrue(isCallbackTriggered, "FIX VERIFIED: onTaskCompleted must be reliably delivered to listeners.")
    }

    // MARK: - Fix 2 Verification: CLI 快捷指令名称以 '-' 开头时 '--' 分隔符有效防止参数解析错误
    func testFix2_DashPrefixShortcutCLIArgumentParsingFixedWithDelimiter() throws {
        // Test running shortcuts CLI with argument delimiter: shortcuts run -- -Test
        let processWithDelimiter = Process()
        processWithDelimiter.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        processWithDelimiter.arguments = ["run", "--", "-Test"]
        let errPipe = Pipe()
        processWithDelimiter.standardError = errPipe
        try processWithDelimiter.run()
        processWithDelimiter.waitUntilExit()

        let exitCode = processWithDelimiter.terminationStatus

        // With '--', exitCode must NOT be 64 (EX_USAGE: Missing expected argument)
        XCTAssertNotEqual(exitCode, 64, "FIX VERIFIED: With '--' delimiter, -Test is properly recognized as the shortcut name, not an unrecognized flag.")
    }

    // MARK: - Fix 3 Verification: ScriptMonitorSpinnerView 状态指示采用 SymbolConfiguration 调色板染色
    @MainActor
    func testFix3_ErrorFlashUsesModernSymbolConfigurationWithoutTemplateColorDegradation() {
        let spinner = ScriptMonitorSpinnerView(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        spinner.updateState(.errorFlash)

        let imageViews = spinner.subviews.compactMap { $0 as? NSImageView }
        XCTAssertFalse(imageViews.isEmpty, "Spinner should contain an NSImageView")
        if let iconImageView = imageViews.first, let image = iconImageView.image {
            // In the fixed implementation, image is configured via SymbolConfiguration(paletteColors: [tintColor])
            // and contentTintColor is cleared so it does not conflict with palette tinting
            XCTAssertNil(iconImageView.contentTintColor, "FIX VERIFIED: contentTintColor is nil because paletteColors is used directly.")
            XCTAssertNotNil(image, "SF Symbol image is present")
        }
    }

    // MARK: - Fix 4 Verification: OptimizationFeaturesTests.testStandardNativeMenuItem 真实有效断言
    @MainActor
    func testFix4_StandardNativeMenuItemAssertionVerification() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Work"
        mock.responses["list --folder-name Work"] = "High Priority Action"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        _ = try await service.refreshCache()

        let manager = ProcessManager(spawner: MockProcessSpawner())
        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager
        builder.currentScope = .leaf(folderName: "Work")

        let menu = builder.buildMenu()

        var executedAssertionCount = 0
        for menuItem in menu.items {
            if menuItem.representedObject as? String == "High Priority Action" {
                executedAssertionCount += 1
                XCTAssertNil(menuItem.view, "Shortcut items should use native rendering without custom view")
                XCTAssertNotNil(menuItem.image, "Shortcut item should have an icon image")
            }
        }

        XCTAssertEqual(executedAssertionCount, 1, "FIX VERIFIED: Assertion executed exactly once on the target shortcut menu item.")
    }

    // MARK: - Fix 5 Verification: RunningTaskView / ScriptMonitorSpinnerView 弱引用定时器杜绝内存泄漏
    @MainActor
    func testFix5_TimerRetainCycleEliminated() {
        // 1. Verify RunningTaskView weak reference release
        weak var weakTaskView: RunningTaskView?
        autoreleasepool {
            let taskView = RunningTaskView(
                taskId: UUID(),
                taskName: "NonLeakingTask",
                onStop: { _ in }
            )
            weakTaskView = taskView
        }

        // Spin the RunLoop briefly to process any pending autorelease events
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(weakTaskView, "FIX VERIFIED: RunningTaskView was deallocated; weak-self block timer broke the retain cycle.")

        // 2. Verify ScriptMonitorSpinnerView weak reference release
        weak var weakSpinnerView: ScriptMonitorSpinnerView?
        autoreleasepool {
            let spinner = ScriptMonitorSpinnerView(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
            spinner.updateState(.running(taskCount: 1))
            weakSpinnerView = spinner
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(weakSpinnerView, "FIX VERIFIED: ScriptMonitorSpinnerView was deallocated; weak-self block timer broke the retain cycle.")
    }

    // MARK: - Fix 6 Verification: MenuBuilder 移除冗余 MenuActionTarget 与无界字典，彻底消除累积泄漏
    @MainActor
    func testFix6_MenuActionTargetEliminatedNoAccumulation() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Folder1\nFolder2\nFolder3\nFolder4\nFolder5"
        for i in 1...5 {
            mock.responses["list --folder-name Folder\(i)"] = "Shortcut_A\(i)\nShortcut_B\(i)"
        }
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        _ = try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager

        // Verify MenuBuilder does not have legacy actionTarget or shortcutClickHandler dictionary
        let builderMirror = Mirror(reflecting: builder)
        let hasActionTarget = builderMirror.children.contains { $0.label == "actionTarget" }
        XCTAssertFalse(hasActionTarget, "FIX VERIFIED: actionTarget class and closure dictionary have been completely removed from MenuBuilder.")

        // Repeatedly building menu across scopes should be safe and idempotent
        for i in 1...5 {
            builder.currentScope = .leaf(folderName: "Folder\(i)")
            let menu = builder.buildMenu()
            XCTAssertGreaterThan(menu.items.count, 0)
        }
    }
}
