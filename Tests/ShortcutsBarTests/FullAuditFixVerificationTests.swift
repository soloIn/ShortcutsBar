import XCTest
import AppKit
import SwiftUI
import Carbon.HIToolbox
@testable import ShortcutsBarCore

@MainActor
final class FullAuditFixVerificationTests: XCTestCase {

    private class TestMockScreen: NSScreen {
        private let _frame: NSRect
        private let _visibleFrame: NSRect

        init(frame: NSRect, visibleFrame: NSRect) {
            self._frame = frame
            self._visibleFrame = visibleFrame
            super.init()
        }

        override var frame: NSRect { _frame }
        override var visibleFrame: NSRect { _visibleFrame }
    }

    // MARK: - 1. MenuBarView 重复 Key 防崩溃验证
    func testFix1_MenuBarViewDuplicateCustomOrderDoesNotCrash() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.fix1.\(UUID().uuidString)")!)
        let service = ShortcutsService(executor: MockShortcutsCLIExecutor())
        let manager = ProcessManager(spawner: MockProcessSpawner())

        // 模拟用户排序数据中持久化了重复条目
        store.setCustomOrder(["DuplicateKey", "DuplicateKey", "Another"], for: "全部")

        let view = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: manager
        )
        // 渲染或初始化时加载 refreshData，确保不触发 Fatal Error 崩溃
        XCTAssertNotNil(view)
    }

    // MARK: - 2. ShortcutsService 弹性缓存保护验证
    func testFix2_ShortcutsServiceResilientCachePreservesExistingData() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Alpha"
        mock.responses["list --folder-name Alpha"] = "Shortcut A\nShortcut B"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let initialFolders = try await service.refreshCache()
        XCTAssertEqual(initialFolders.count, 1)
        XCTAssertEqual(service.cachedFolders.count, 1)

        // 模拟随后的刷新遭遇系统 CLI 瞬时故障，所有命令返回空
        mock.responses["list --folders"] = ""
        mock.responses["list --folder-name Alpha"] = ""
        mock.responses["list"] = ""

        let secondFolders = try await service.refreshCache()
        // 验证：由于开启了弹性缓存保护，已有的健康缓存不会被清空抹除
        XCTAssertEqual(secondFolders.count, 1, "弹性缓存保护机制应保留原有缓存")
        XCTAssertEqual(service.cachedFolders.count, 1)
        XCTAssertEqual(service.cachedFolders[0].shortcuts.count, 2)
    }

    // MARK: - 3. ProcessManager 并发上限防 Fork Storm 保护
    func testFix3_ProcessManagerConcurrencyLimitGuardsAgainstRunawayTasks() throws {
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        var launchedPids: [UUID] = []
        // 启动达到最大并发上限 (16)
        for i in 1...ProcessManager.maxConcurrentTasks {
            let id = try manager.launch(shortcutName: "Task \(i)")
            launchedPids.append(id)
        }
        XCTAssertEqual(manager.activeTaskCount, ProcessManager.maxConcurrentTasks)

        // 第 17 个任务应被拦截并抛出并发限制异常
        XCTAssertThrowsError(try manager.launch(shortcutName: "Exceeded Task")) { error in
            guard let pmError = error as? ProcessManagerError else {
                XCTFail("应抛出 ProcessManagerError")
                return
            }
            XCTAssertEqual(pmError, .concurrencyLimitExceeded)
        }
    }

    // MARK: - 4. PanelKeyInterceptor 回车长按防重（!event.isARepeat）
    func testFix4_PanelKeyInterceptorReturnKeyIgnoresKeyRepeats() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "General"
        mock.responses["list --folder-name General"] = "Target Shortcut"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.fix4.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: service, processManager: manager, preferencesStore: store, panelController: panelController)
        let interceptor = PanelKeyInterceptor(panel: panelController.panel, viewModel: vm, panelController: panelController)

        panelController.show()
        vm.highlightedIndex = 0

        // 模拟正常首次按下回车（isARepeat == false）
        let firstEnter = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        let handledFirst = interceptor.handleKeyEvent(firstEnter)
        XCTAssertTrue(handledFirst)
        XCTAssertEqual(manager.activeTaskCount, 1)

        // 模拟长按产生的连续重复事件（isARepeat == true）
        let repeatedEnter = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: true,
            keyCode: 36
        )!
        let handledRepeat = interceptor.handleKeyEvent(repeatedEnter)
        // 应该被拦截消费，但不触发任务启动
        XCTAssertTrue(handledRepeat)
        XCTAssertEqual(manager.activeTaskCount, 1, "长按回车不应导致多次连续启动")
    }

    // MARK: - 5. FloatingPanelController 隐形状态栏 Anchor 坐标安全回退
    func testFix5_FloatingPanelControllerInvisibleStatusItemFallsBackToTopRight() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.fix5.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        // 构造一个高度为 0 的未映射状态栏按钮窗口（模拟 item.isVisible == false 时的真实 AppKit 行为）
        let dummyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 44, height: 0),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let dummyButton = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 28, height: 0))
        dummyWindow.contentView?.addSubview(dummyButton)

        let testScreen = TestMockScreen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)
        )

        let frame = controller.calculateDockedFrame(for: dummyButton, on: testScreen)
        // 验证：不应坠落到 (minX + 8, minY + 8) 即 (8, 8)，而应安全停靠在屏幕右上角 (maxX - width - 16)
        let expectedX = 1440 - FloatingPanelController.panelWidth - 16
        XCTAssertEqual(frame.origin.x, expectedX, "当状态栏项不可见时，应优雅回退至屏幕右上角停靠")
        XCTAssertGreaterThan(frame.origin.y, 400, "Y 坐标应贴近屏幕顶部，绝不坠入左下角")
    }

    // MARK: - 6. FloatingPanelViewModel 每次唤醒刷新 focusToken
    func testFix6_FloatingPanelViewModelFocusTokenRefreshesOnAwaken() {
        let service = ShortcutsService(executor: MockShortcutsCLIExecutor())
        let manager = ProcessManager(spawner: MockProcessSpawner())
        let vm = FloatingPanelViewModel(shortcutsService: service, processManager: manager)

        let initialToken = vm.focusToken
        vm.refreshData()
        let newToken = vm.focusToken

        XCTAssertNotEqual(initialToken, newToken, "每次 refreshData 均应更新 focusToken 以触发搜索框自动聚焦")
    }

    // MARK: - 7. ShortcutsSearchEngine 单字母元音拼音匹配保护
    func testFix7_ShortcutsSearchEngineSingleCharacterPinyinDoesNotMatchAllWords() {
        let engine = ShortcutsSearchEngine()
        // "图库壁纸" 的全拼是 "tukubizhi"，虽然包含 'i'，但单字母 'i' 不应被模糊匹配
        let score = engine.matchScore(query: "i", targetName: "图库壁纸")
        XCTAssertEqual(score, 0, "单字母元音不应触发中文字符串的内部包含拼音匹配")

        // 正常以 't' 开头的拼音首字母匹配依然有效
        let prefixScore = engine.matchScore(query: "t", targetName: "图库壁纸")
        XCTAssertGreaterThan(prefixScore, 0, "以首字母开头的匹配应正常生效")
    }

    // MARK: - 8. PreferencesStore showMenuBarRunningStatus 偏好设置持久化
    func testFix8_PreferencesStoreShowMenuBarRunningStatusDefaultAndPersistence() {
        let suite = "test.fix8.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PreferencesStore(defaults: defaults)

        // 默认值应为 true
        XCTAssertTrue(store.showMenuBarRunningStatus, "默认应显示菜单栏运行状态")

        final class Box: @unchecked Sendable {
            var receivedNotification = false
            var receivedKey: String?
        }
        let box = Box()

        let cancellable = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: nil,
            queue: .main
        ) { notif in
            box.receivedNotification = true
            box.receivedKey = notif.userInfo?["key"] as? String
        }
        defer { NotificationCenter.default.removeObserver(cancellable) }

        // 设置为 false 并验证通知和持久化
        store.showMenuBarRunningStatus = false
        XCTAssertFalse(store.showMenuBarRunningStatus)
        XCTAssertTrue(box.receivedNotification)
        XCTAssertEqual(box.receivedKey, "showMenuBarRunningStatus")

        // 验证持久化到 UserDefaults
        let newStore = PreferencesStore(defaults: defaults)
        XCTAssertFalse(newStore.showMenuBarRunningStatus)
    }

    // MARK: - 9. StatusItemController 遵循 showMenuBarRunningStatus
    func testFix9_StatusItemControllerRespectsShowMenuBarRunningStatus() async throws {
        let suite = "test.fix9.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PreferencesStore(defaults: defaults)
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)
        let testStatusItem = NSStatusBar.system.statusItem(withLength: 28)
        let statusController = StatusItemController(
            processManager: manager,
            preferencesStore: store,
            statusItem: testStatusItem
        )

        // 1. 当关闭菜单栏运行状态时，启动任务后不应显示 ScriptMonitorSpinnerView
        store.showMenuBarRunningStatus = false
        _ = try manager.launch(shortcutName: "TaskA")
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasSpinnerWhenDisabled = statusController.statusItem?.button?.subviews.contains { $0 is ScriptMonitorSpinnerView } ?? false
        XCTAssertFalse(hasSpinnerWhenDisabled, "当 showMenuBarRunningStatus 为 false 时，不应在状态栏展示运行中微调指示器")

        // 2. 当开启菜单栏运行状态时，启动任务后应正常显示 ScriptMonitorSpinnerView
        store.showMenuBarRunningStatus = true
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasSpinnerWhenEnabled = statusController.statusItem?.button?.subviews.contains { $0 is ScriptMonitorSpinnerView } ?? false
        XCTAssertTrue(hasSpinnerWhenEnabled, "当 showMenuBarRunningStatus 为 true 且有任务在运行时，状态栏应正常显示微调指示器")

        manager.terminateAll()
        _ = statusController
    }

    // MARK: - 10. HotkeyHelper 快捷键与修饰符双向转换准确性
    func testFix10_HotkeyHelperKeyEquivalentAndModifiersTranslation() {
        // Space 键 (keyCode: 49)
        let spaceEquiv = HotkeyHelper.keyEquivalent(for: 49)
        XCTAssertEqual(spaceEquiv, .space)

        // K 键 (keyCode: 40)
        let kEquiv = HotkeyHelper.keyEquivalent(for: 40)
        XCTAssertEqual(kEquiv, KeyEquivalent("k"))

        // 修饰符转换: ⌘ + ⇧ (cmdKey | shiftKey)
        let carbonMods = UInt32(cmdKey) | UInt32(shiftKey)
        let eventMods = HotkeyHelper.eventModifiers(from: carbonMods)
        XCTAssertTrue(eventMods.contains(.command))
        XCTAssertTrue(eventMods.contains(.shift))
        XCTAssertFalse(eventMods.contains(.option))
        XCTAssertFalse(eventMods.contains(.control))
    }
}
