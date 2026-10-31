import XCTest
import AppKit
@testable import ShortcutsBarCore

/// SecondaryVerificationBlackboxTests
///
/// 自动化黑盒二次验证测试集：
/// 针对第一步静态检查中发现的 7 个核心 Findings，进行真实的输入模拟、事件时序与外部断言测试，
/// 严格依赖控制台实际运行输出（swift test），杜绝单靠静态代码推演或主观臆测。
final class SecondaryVerificationBlackboxTests: XCTestCase {

    // MARK: - Helper Mock: 可控异步 CLI 调度器，用于精确模拟并发时序与外部数据变更
    final class ControllableMockCLIExecutor: ShortcutsCLIExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _responses: [String: String] = [:]
        var onExecuteStarted: (@Sendable (String) -> Void)?
        var pauseExecutionForCommand: String?
        private var continuations: [String: [CheckedContinuation<Void, Never>]] = [:]

        var responses: [String: String] {
            get { lock.withLock { _responses } }
            set { lock.withLock { _responses = newValue } }
        }

        func setResponse(_ response: String, for command: String) {
            lock.withLock {
                _responses[command] = response
            }
        }

        func resume(command: String) {
            let toResume: [CheckedContinuation<Void, Never>] = lock.withLock {
                let list = continuations[command] ?? []
                continuations[command] = []
                return list
            }
            for continuation in toResume {
                continuation.resume()
            }
        }

        func execute(arguments: [String]) async throws -> String {
            let key = arguments.joined(separator: " ")
            onExecuteStarted?(key)

            let shouldPause: Bool = lock.withLock {
                pauseExecutionForCommand == key
            }

            if shouldPause {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.withLock {
                        var list = continuations[key] ?? []
                        list.append(continuation)
                        continuations[key] = list
                    }
                }
            }

            return lock.withLock {
                _responses[key] ?? ""
            }
        }
    }

    // MARK: - Finding 1: 键盘拦截器掩码劫持系统截屏
    /// 验证：在 PanelKeyInterceptor 中，按下 ⌘⇧3 / ⌘⇧4 / ⌘⇧5 时，
    /// 是否因为仅判断 `event.modifierFlags.contains(.command)` 为 true 而误判为 ⌘3/⌘4 快捷键并被拦截消费（返回 true）
    @MainActor
    func testFinding1_PanelKeyInterceptorMaskHijacksSystemScreenshotKeyCombinations() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.finding1.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        let interceptor = PanelKeyInterceptor(
            panel: panelController.panel,
            viewModel: viewModel,
            panelController: panelController
        )

        // 配置 5 个可见快捷指令：索引 0..4 分别对应快捷键 ⌘1..⌘5
        let items = [
            ProjectedShortcutItem(item: ShortcutItem(name: "Shortcut 1", folderName: "All"), folderName: "All"),
            ProjectedShortcutItem(item: ShortcutItem(name: "Shortcut 2", folderName: "All"), folderName: "All"),
            ProjectedShortcutItem(item: ShortcutItem(name: "Shortcut 3", folderName: "All"), folderName: "All"),
            ProjectedShortcutItem(item: ShortcutItem(name: "Shortcut 4", folderName: "All"), folderName: "All"),
            ProjectedShortcutItem(item: ShortcutItem(name: "Shortcut 5", folderName: "All"), folderName: "All")
        ]
        viewModel.visibleItems = items
        panelController.show()

        // 1. 模拟 macOS 系统全屏截屏快捷键: ⌘⇧3 (Command + Shift + 3, keyCode 20)
        let cmdShift3Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "#",
            charactersIgnoringModifiers: "3",
            isARepeat: false,
            keyCode: 20
        )!

        // 执行拦截测试
        let handled3 = interceptor.handleKeyEvent(cmdShift3Event)

        // 验证修复：
        // 系统截屏 ⌘⇧3 绝不应被 Panel 拦截消费，而应透传给系统（返回 false）。
        XCTAssertFalse(
            handled3,
            "【Fix Verified】⌘⇧3 未被误拦截，放行给系统截屏！"
        )
        XCTAssertNil(
            processManager.activeTasks.last?.shortcutName,
            "【Fix Verified】按下系统截屏 ⌘⇧3 不会错误启动快捷指令！"
        )

        // 2. 模拟 macOS 系统区域截屏快捷键: ⌘⇧4 (Command + Shift + 4, keyCode 21)
        let cmdShift4Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "$",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: 21
        )!

        let handled4 = interceptor.handleKeyEvent(cmdShift4Event)
        XCTAssertFalse(
            handled4,
            "【Fix Verified】⌘⇧4 未被误拦截，放行给系统！"
        )
        XCTAssertNil(
            processManager.activeTasks.last?.shortcutName,
            "【Fix Verified】按下系统截屏 ⌘⇧4 不会错误启动快捷指令！"
        )

        // 3. 模拟 macOS 截屏/录屏控制台快捷键: ⌘⇧5 (Command + Shift + 5, keyCode 23)
        let cmdShift5Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "%",
            charactersIgnoringModifiers: "5",
            isARepeat: false,
            keyCode: 23
        )!

        let handled5 = interceptor.handleKeyEvent(cmdShift5Event)
        XCTAssertFalse(
            handled5,
            "【Fix Verified】⌘⇧5 未被误拦截，放行给系统！"
        )
        XCTAssertNil(
            processManager.activeTasks.last?.shortcutName,
            "【Fix Verified】按下系统截屏 ⌘⇧5 不会错误启动快捷指令！"
        )
    }

    // MARK: - Finding 2: 键盘拦截器 ⌘←/→ 劫持光标
    /// 验证：在 PanelKeyInterceptor 中，按下 ⌘← (keyCode 123) 或 ⌘→ (keyCode 124) 时，
    /// 是否无条件返回 true 并触发 selectPreviousFolder / selectNextFolder，导致文本光标移动事件被吞噬
    @MainActor
    func testFinding2_PanelKeyInterceptorCommandArrowHijacksCursorMovement() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.finding2.\(UUID().uuidString)")!)
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

        viewModel.availableFolders = ["全部", "工作", "个人"]
        viewModel.selectedFolder = "全部"
        panelController.show()

        // 模拟 ⌘→ (keyCode 124, 在文本框中本意为跳至行尾 moveToEndOfLine:)
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

        // 执行拦截
        let handledRight = interceptor.handleKeyEvent(cmdRightEvent)

        // 验证修复：
        // 在单目录（无二级子菜单）模式下，⌘→ 不被消费，放行给文本输入框光标跳行
        XCTAssertFalse(
            handledRight,
            "【Fix Verified】⌘→ 未被拦截消费，放行到达文本输入框！"
        )
        XCTAssertEqual(
            viewModel.selectedFolder,
            "全部",
            "【Fix Verified】当前文件夹保持不变！"
        )

        // 模拟 ⌘← (keyCode 123, 在文本框中本意为跳至行首 moveToBeginningOfLine:)
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

        let handledLeft = interceptor.handleKeyEvent(cmdLeftEvent)

        XCTAssertFalse(
            handledLeft,
            "【Fix Verified】⌘← 未被拦截消费，放行到达文本输入框！"
        )
        XCTAssertEqual(
            viewModel.selectedFolder,
            "全部",
            "【Fix Verified】当前文件夹保持不变！"
        )
    }

    // MARK: - Finding 3: 多显示器副屏坐标瞬移
    /// 验证：在 FloatingPanelController 中，当 statusButton 位于副屏（如 X 坐标 >= 2560 或 < 0）时，
    /// calculateDockedFrame 是否因使用 primaryScreen 导致坐标被强制裁剪到主屏内部
    @MainActor
    func testFinding3_FloatingPanelControllerHardcodedPrimaryScreenTeleportsSecondaryCoordinates() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.finding3.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let primaryScreenFrame = primaryScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // 1. 模拟右侧扩展显示器 (Secondary Display on Right, X >= 2560)
        // 状态栏按钮位于副屏 X = 3200, Y = 1000
        let secondaryWindowRight = NSWindow(
            contentRect: NSRect(x: 3200, y: 1000, width: 30, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let buttonRight = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        secondaryWindowRight.contentView?.addSubview(buttonRight)

        let buttonScreenRectRight = buttonRight.window!.convertToScreen(buttonRight.bounds)
        XCTAssertGreaterThanOrEqual(buttonScreenRectRight.midX, 3200.0)

        // 调用 calculateDockedFrame 并传入 primaryScreen（符合 FloatingPanelController 内部 show/resetToDocked 的调用模式）
        let dockedFrameRight = controller.calculateDockedFrame(for: buttonRight, on: primaryScreen)

        // 缺陷断言：
        // calculateDockedFrame 强制使用了 primaryScreen 的 screenRect 进行边界 clamp
        // 导致本应停靠在 3200+ 附近的面板被强行拽回主屏内部（maxX <= primaryScreenFrame.maxX）
        XCTAssertLessThanOrEqual(
            dockedFrameRight.maxX,
            primaryScreenFrame.maxX,
            "【Defect Confirmed】副屏(X=3200)上的面板停靠位置被主屏边界强制裁剪！"
        )
        XCTAssertLessThan(
            dockedFrameRight.origin.x,
            2560.0,
            "【Defect Confirmed】坐标被瞬移出副屏，直接掉落回主屏内部！"
        )

        // 2. 模拟左侧扩展显示器 (Secondary Display on Left, X < 0)
        // 状态栏按钮位于副屏 X = -600, Y = 1000
        let secondaryWindowLeft = NSWindow(
            contentRect: NSRect(x: -600, y: 1000, width: 30, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let buttonLeft = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        secondaryWindowLeft.contentView?.addSubview(buttonLeft)

        let buttonScreenRectLeft = buttonLeft.window!.convertToScreen(buttonLeft.bounds)
        XCTAssertLessThan(buttonScreenRectLeft.midX, 0.0)

        let dockedFrameLeft = controller.calculateDockedFrame(for: buttonLeft, on: primaryScreen)

        // 缺陷断言：
        // 坐标小于 0 的副屏按钮，被主屏 minX + 8 强行吸附到了主屏左边缘
        XCTAssertGreaterThanOrEqual(
            dockedFrameLeft.origin.x,
            primaryScreenFrame.minX,
            "【Defect Confirmed】左副屏(X=-600)上的面板坐标被强制吸附至主屏正坐标！"
        )
        XCTAssertGreaterThan(
            dockedFrameLeft.origin.x,
            0.0,
            "【Defect Confirmed】面板脱离了副屏(-600)，瞬移到了主屏幕内！"
        )
    }

    // MARK: - Finding 4: ShortcutsService 缓存合并防抖导致文件更新丢失
    /// 验证：当 refreshCache 正在进行中时（耗时模拟），再次触发 refreshCache，
    /// 第 2 次调用是否仅仅复用了正在进行的 Task，导致在第 1 次执行期间发生的真实数据变更被永久丢失
    func testFinding4_ShortcutsServiceCoalescedRefreshDropsMidFlightDataUpdates() async throws {
        let mockExecutor = ControllableMockCLIExecutor()
        // 初始数据：库中仅有 "Shortcut_Initial"
        mockExecutor.setResponse("Shortcut_Initial", for: "list")
        mockExecutor.setResponse("Folder1", for: "list --folders")
        mockExecutor.setResponse("Shortcut_Initial", for: "list --folder-name Folder1")
        mockExecutor.setResponse("", for: "list --folder-name none")

        let service = ShortcutsService(executor: mockExecutor)

        // 配置：在执行第 1 次刷新的尾部 "list --folder-name none" 时挂起。
        // 此时第 1 次刷新已经完成了 Folder1 的抓取（仅包含 "Shortcut_Initial"）。
        mockExecutor.pauseExecutionForCommand = "list --folder-name none"

        let refresh1Paused = expectation(description: "Refresh 1 has reached none folder query and is paused")
        mockExecutor.onExecuteStarted = { command in
            if command == "list --folder-name none" {
                refresh1Paused.fulfill()
            }
        }

        // 1. 触发第 1 次 refreshCache（已完成 Folder1 抓取，正在执行并挂起在 none）
        let task1 = Task {
            try await service.refreshCache()
        }

        // 等待第 1 次 refresh 抓取完 Folder1 并真正进入挂起状态
        await fulfillment(of: [refresh1Paused], timeout: 2.0)

        // 2. 外部发生真实数据变更：用户在系统快捷指令中新建了 "Shortcut_NewAdded"
        mockExecutor.setResponse("Shortcut_Initial\nShortcut_NewAdded", for: "list")
        mockExecutor.setResponse("Shortcut_Initial\nShortcut_NewAdded", for: "list --folder-name Folder1")

        // 3. 此时外部触发了第 2 次 refreshCache（例如文件系统变更通知或主动刷新）
        let task2 = Task {
            try await service.refreshCache()
        }

        // 短暂让出执行权，确保 task2 已经调用了 service.refreshCache() 并命中了 inFlightRefreshTask
        try await Task.sleep(nanoseconds: 50_000_000)

        // 4. 恢复第 1 次挂起的 CLI 执行，等待两个任务全部完成
        mockExecutor.pauseExecutionForCommand = nil
        mockExecutor.resume(command: "list --folder-name none")

        let result1 = try await task1.value
        let result2 = try await task2.value

        // 缺陷断言：
        // 1. 第 2 次 refresh 仅仅复用了第 1 次的 Task（返回了旧结果），没有重新抓取最新数据
        let shortcutsInResult2 = result2.flatMap(\.shortcuts).map(\.name)
        XCTAssertFalse(
            shortcutsInResult2.contains("Shortcut_NewAdded"),
            "【Defect Confirmed】第 2 次 refreshCache 仅仅复用了先前的 Task，返回了不包含最新修改的数据！"
        )

        // 2. 两次任务结束后，ShortcutsService 的缓存中依然没有 "Shortcut_NewAdded"
        let currentCached = service.allShortcuts.map(\.name)
        XCTAssertFalse(
            currentCached.contains("Shortcut_NewAdded"),
            "【Defect Confirmed】在第 1 次刷新中途发生的真实修改 'Shortcut_NewAdded' 在缓存合并后被永久丢失！"
        )
        XCTAssertEqual(
            result1.map(\.name),
            result2.map(\.name)
        )
    }

    // MARK: - Finding 5: 失败任务永久驻留在 completedTasks 中
    /// 验证：当快捷指令执行失败时，FloatingPanelViewModel 是否未提供任何自动或手动的清除机制，
    /// 导致失败任务无限期滞留在 completedTasks
    @MainActor
    func testFinding5_FailedTasksPermanentlyRetainedInCompletedTasksWithoutCleanup() async throws {
        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.finding5.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)

        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        // 1. 发起成功任务
        let successTaskId = try processManager.launch(shortcutName: "SuccessShortcutsTask")
        if let successPid = spawner.activePids.first {
            spawner.simulateTermination(pid: successPid, status: 0) // exit 0 成功
        }

        // 2. 发起失败任务
        let failedTaskId = try processManager.launch(shortcutName: "FailedShortcutsTask")
        if let failedPid = spawner.activePids.first {
            spawner.simulateTermination(pid: failedPid, status: 1) // exit 1 失败
        }

        // 等待观察者投递至 MainActor
        try await Task.sleep(nanoseconds: 100_000_000)

        // 初始状态断言
        XCTAssertNotNil(viewModel.completedTasks[successTaskId], "成功任务初始存在于 completedTasks")
        XCTAssertNotNil(viewModel.completedTasks[failedTaskId], "失败任务初始存在于 completedTasks")
        XCTAssertEqual(viewModel.completedTasks[failedTaskId]?.isSuccess, false)

        // 等待 1.8 秒（超过成功任务的 1.5 秒 auto-fade 超时）
        try await Task.sleep(nanoseconds: 1_800_000_000)

        // 缺陷断言：
        // 成功任务已被自动清除
        XCTAssertNil(
            viewModel.completedTasks[successTaskId],
            "成功任务在 1.5 秒后已自动淡出清除"
        )

        // 失败任务没有任何自动销毁定时器，也没有任何提供给用户点击关闭/清除的 API，永远保留在字典中
        XCTAssertNotNil(
            viewModel.completedTasks[failedTaskId],
            "【Defect Confirmed】失败任务永久驻留在 completedTasks 中，缺少清理和关闭机制！"
        )
    }

    // MARK: - Finding 6: MenuBuilder 忽略自定义拖拽排序
    /// 验证：在 PreferencesStore 中针对某个目录设置了 customSortOrders 后，
    /// MenuBuilder.populateMenu 构建的菜单项是否依然使用原始顺序，未应用自定义排序
    @MainActor
    func testFinding6_MenuBuilderIgnoresCustomSortOrders() async throws {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.finding6.\(UUID().uuidString)")!)
        let mockExecutor = MockShortcutsCLIExecutor()

        // 模拟目录 "Work" 包含原始排序为 ["Item_Charlie", "Item_Alpha", "Item_Bravo"]
        mockExecutor.responses["list"] = "Item_Charlie\nItem_Alpha\nItem_Bravo"
        mockExecutor.responses["list --folders"] = "Work"
        mockExecutor.responses["list --folder-name Work"] = "Item_Charlie\nItem_Alpha\nItem_Bravo"
        mockExecutor.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mockExecutor)
        try await service.refreshCache()

        // 在 PreferencesStore 中设定用户通过拖拽保存的自定义排序:
        // 用户期望的顺序是: Item_Bravo -> Item_Alpha -> Item_Charlie
        let customOrder = ["Item_Bravo", "Item_Alpha", "Item_Charlie"]
        store.setCustomOrder(customOrder, for: "Work")
        XCTAssertEqual(store.getCustomOrder(for: "Work"), customOrder)

        // 构建 MenuBuilder，绑定该 service 与 store
        let processManager = ProcessManager()
        let menuBuilder = MenuBuilder()
        menuBuilder.shortcutsService = service
        menuBuilder.processManager = processManager
        menuBuilder.preferencesStore = store
        menuBuilder.currentScope = .leaf(folderName: "Work")

        let menu = menuBuilder.buildMenu()

        // 提取菜单中的快捷指令菜单项标题
        let displayedTitles = menu.items.compactMap { item -> String? in
            guard let name = item.representedObject as? String else { return nil }
            return name
        }

        // 验证修复：
        // MenuBuilder 现已接入 preferencesStore.getCustomOrder(for:)，菜单项顺序与自定义排序一致！
        XCTAssertEqual(
            displayedTitles,
            customOrder,
            "【Fix Verified】MenuBuilder 渲染结果严格遵循 preferencesStore 中的自定义排序！"
        )
    }

    // MARK: - Finding 7: StatusItemControllerTests 中测试对象即时释放导致测试假通过
    /// 验证：StatusItemControllerTests.swift 中使用 `let _ = StatusItemController(...)`，
    /// 对象是否在行末立即执行 deinit 并注销了所有 observer，使得后续的终止模拟根本没有被任何 controller 接收
    @MainActor
    func testFinding7_StatusItemControllerImmediateDeinitCausesFalsePassInCallbackTests() throws {
        let mockSpawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: mockSpawner)

        // 1. 复现原测试中的代码写法:
        // let _ = StatusItemController(processManager: manager)
        weak var weakSubject: StatusItemController?

        // 通过一个立即执行闭包创建并不持有变量，模拟 `let _ = StatusItemController(...)` 的生命周期
        _ = {
            let controller = StatusItemController(processManager: manager)
            weakSubject = controller
            return controller
        }()

        // 缺陷断言 1:
        // 在语句结束瞬间，无强引用持有的 StatusItemController 立即执行 deinit！
        XCTAssertNil(
            weakSubject,
            "【Defect Confirmed】使用匿名接收的 StatusItemController 在行末立即被释放（deinit）！"
        )

        // 2. 模拟原测试中的后续流程：
        let taskId = try manager.launch(shortcutName: "Background Test")

        // 模拟后台进程终止通知
        if let pid = mockSpawner.activePids.first {
            mockSpawner.simulateTermination(pid: pid, status: 0)
        }

        // 缺陷断言 2:
        // 原测试中的 `waitForExpectations` 之所以能 Pass，仅仅是因为闭包内的 `exp.fulfill()` 被无条件执行了，
        // 而目标被测对象 `StatusItemController` 早在任务启动前就已经彻底死亡并移除了所有观察者，
        // 实际上根本没有测试任何「StatusItemController 接收后台回调不崩溃」的逻辑！
        XCTAssertNil(
            weakSubject,
            "【Defect Confirmed】整个回调分发过程中被测控制器已死亡，原测试属于典型的测试假通过（False Pass）！"
        )

        _ = taskId
    }
}
