import XCTest
import AppKit
import SwiftUI
@testable import ShortcutsBarCore

@MainActor
final class MenuBarRunningTaskReproductionTests: XCTestCase {

    final class SafeBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { self._value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

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

    func testPureSwiftUIArchitecture_ZeroZombieRunningTasks() throws {
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let preferencesStore = PreferencesStore(defaults: UserDefaults(suiteName: "test_menubar_repro_\(UUID().uuidString)")!)
        let statusItem = NSStatusBar.system.statusItem(withLength: 28)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let _ = StatusItemController(
            processManager: processManager,
            preferencesStore: preferencesStore,
            statusItem: statusItem
        )

        // 1. 监听 ProcessManager.taskQueueChangedNotification
        let notificationReceivedCount = SafeBox(0)
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: ProcessManager.taskQueueChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceivedCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(notificationObserver) }

        // 2. 启动模拟任务
        let taskId = try processManager.launch(shortcutName: "图库壁纸", actionCount: 20)
        XCTAssertEqual(processManager.activeTaskCount, 1)
        XCTAssertEqual(processManager.activeTasks.count, 1)
        XCTAssertEqual(processManager.activeTasks.first?.id, taskId)
        XCTAssertEqual(notificationReceivedCount.value, 1, "任务启动时应广播 taskQueueChangedNotification")

        // 3. 模拟纯 SwiftUI MenuBarView 数据驱动绑定：初始任务状态包含 1 个任务
        var viewActiveTasks = processManager.activeTasks
        XCTAssertEqual(viewActiveTasks.count, 1)

        // 4. 模拟任务在后台结束
        let finishExp = expectation(description: "Wait for task queue update after process finish")
        let finishNotificationFired = SafeBox(false)
        let finishObserver = NotificationCenter.default.addObserver(
            forName: ProcessManager.taskQueueChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            finishNotificationFired.value = true
            finishExp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(finishObserver) }

        spawner.finishProcess(status: 0, wasCancelled: false)
        wait(for: [finishExp], timeout: 2.0)

        // 5. 验证广播后 processManager.activeTasks 立即清空，零死尸任务残留
        XCTAssertTrue(finishNotificationFired.value)
        XCTAssertEqual(processManager.activeTaskCount, 0, "任务结束后 activeTaskCount 立即为 0")
        XCTAssertTrue(processManager.activeTasks.isEmpty, "任务结束后 activeTasks 立即清空")

        // 6. 纯 SwiftUI 数据流同步：驱动视图渲染的任务列表同样清空，杜绝旧 AppKit NSMenu 的 View 残留
        viewActiveTasks = processManager.activeTasks
        XCTAssertTrue(viewActiveTasks.isEmpty, "纯 SwiftUI 架构数据驱动彻底消除死尸运行中任务残留")
    }
}
