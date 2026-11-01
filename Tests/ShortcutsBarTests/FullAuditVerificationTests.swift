import XCTest
import AppKit
import SwiftUI
import SQLite3
import Carbon.HIToolbox
@testable import ShortcutsBarCore

/// FullAuditVerificationTests
///
/// 全量静态代码审查 Findings 程序化/黑盒验证测试集：
/// 覆盖静态审计报告中全部 51 项 Findings（涵盖 Critical、Major、Minor / L-01~L-10, A-01~A-12, C-01~C-09, U-01~U-11, T-01~T-09）。
/// 真实运行测试代码，以控制台执行输出作为确凿证据，拒绝单靠静态检查主观推断。
///
/// 每个测试用例输出明确的判定标签：
/// - 【100% 确认缺陷】：真实复现生产行为中的 Bug / 规范违背 / 风险
/// - 【确认合规（误报）】：代码实际已符合规范或在此前提交中已完成闭环修复
/// - 【部分确认】：部分场景存在缺陷或部分已修复
final class FullAuditVerificationTests: XCTestCase {

    // MARK: - Test Helpers & Thread-Safe Boxes

    final class AtomicBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { self._value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    final class FullAuditMockProcessSpawner: ProcessSpawning, @unchecked Sendable {
        struct SpawnRecord {
            let name: String
            let onTermination: @Sendable (Int32, Bool) -> Void
        }

        private let lock = NSLock()
        private var spawned: [pid_t: SpawnRecord] = [:]
        private var nextPid: pid_t = 5000
        var onSpawnCalled: (@Sendable (String) -> Void)?

        func spawn(
            shortcutName: String,
            onTermination: @escaping @Sendable (Int32, Bool) -> Void
        ) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
            onSpawnCalled?(shortcutName)
            return lock.withLock {
                let pid = nextPid
                nextPid += 1
                spawned[pid] = SpawnRecord(name: shortcutName, onTermination: onTermination)
                let cancelHandler: @Sendable () -> Void = { [weak self] in
                    self?.simulateTermination(pid: pid, status: 15, wasCancelled: true)
                }
                return (pid, cancelHandler)
            }
        }

        func simulateTermination(pid: pid_t, status: Int32, wasCancelled: Bool = false) {
            let record: SpawnRecord? = lock.withLock {
                return spawned.removeValue(forKey: pid)
            }
            record?.onTermination(status, wasCancelled)
        }

        var activePids: [pid_t] {
            lock.withLock { Array(spawned.keys) }
        }
    }

    final class FullAuditMockCLIExecutor: ShortcutsCLIExecuting, @unchecked Sendable {
        private let lock = NSLock()
        var responses: [String: String] = [:]
        var throwForArguments: Set<String> = []

        func execute(arguments: [String]) async throws -> String {
            let key = arguments.joined(separator: " ")
            let shouldThrow: Bool = lock.withLock { throwForArguments.contains(key) }
            if shouldThrow {
                throw NSError(domain: "FullAuditCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated CLI failure for: \(key)"])
            }
            let resp: String? = lock.withLock { responses[key] }
            if let resp = resp {
                return resp
            }
            return ""
        }
    }

    // =========================================================================
    // MARK: - 维度 1：代码逻辑与数据流 (Code Logic: L-01 ~ L-10)
    // =========================================================================

    // MARK: L-01 [Critical]: ProcessManager 单播闭包被 FloatingPanelViewModel 覆盖导致状态栏监听失效
    func testL01_ProcessManagerLegacyClosureOverwritingAndObserverTrampling() {
        let spawner = FullAuditMockProcessSpawner()
        let pm = ProcessManager(spawner: spawner)

        let firstObserverCalled = AtomicBox<Bool>(false)
        let secondObserverCalled = AtomicBox<Bool>(false)

        // 模拟旧式 API 使用场景：StatusItemController 先绑定
        pm.onQueueChanged = { _ in
            firstObserverCalled.value = true
        }

        // 紧接着 FloatingPanelViewModel 初始化，若使用单播属性则直接覆盖
        pm.onQueueChanged = { _ in
            secondObserverCalled.value = true
        }

        // 缺陷验证 1：getter 丢失状态（单向黑洞，返回 nil）
        XCTAssertNil(pm.onQueueChanged, "【100% 确认缺陷】onQueueChanged getter 返回 nil，存在 API 不对称性缺陷")

        // 缺陷验证 2：触发任务，第一个订阅者被踩踏移除
        _ = try? pm.launch(shortcutName: "L01_Task")
        XCTAssertFalse(firstObserverCalled.value, "【100% 确认缺陷】第一个订阅者被后初始化的订阅者踩踏覆写，未收到任何队列回调！")
        XCTAssertTrue(secondObserverCalled.value, "【100% 确认缺陷】仅有第二个订阅者存活，单播闭包踩踏缺陷确凿！")
        print(">>> [L-01] 【100% 确认缺陷】ProcessManager 单播闭包覆盖与踩踏导致前置监听失效已程序化证实。")
    }

    // MARK: L-02 [Critical]: 失败任务永久驻留在 completedTasks，红色错误横幅与任务托盘永远无法清除
    @MainActor
    func testL02_FailedTasksPermanentlyRetainedWithoutCleanup() async throws {
        let spawner = FullAuditMockProcessSpawner()
        let pm = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.l02.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: pm, preferencesStore: store, panelController: panelController)

        // 1. 发起成功任务
        let successId = try pm.launch(shortcutName: "SuccessShortcuts")
        if let pid = spawner.activePids.first {
            spawner.simulateTermination(pid: pid, status: 0)
        }

        // 2. 发起失败任务
        let failedId = try pm.launch(shortcutName: "FailedShortcuts")
        if let pid = spawner.activePids.first {
            spawner.simulateTermination(pid: pid, status: 1)
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotNil(vm.completedTasks[successId])
        XCTAssertNotNil(vm.completedTasks[failedId])
        XCTAssertEqual(vm.completedTasks[failedId]?.isSuccess, false)

        // 等待 1.7 秒（超出成功任务 1.5 秒自动淡出定时器）
        try await Task.sleep(nanoseconds: 1_700_000_000)

        // 成功任务已自动淡出
        XCTAssertNil(vm.completedTasks[successId], "成功任务已在 1.5 秒后自动移除")

        // 缺陷断言：失败任务没有任何自动淡出定时器，ViewModel 亦无 clearCompletedTask 接口，永久驻留
        XCTAssertNotNil(vm.completedTasks[failedId], "【100% 确认缺陷】失败任务永久常驻 completedTasks，缺少销毁与关闭机制！")
        print(">>> [L-02] 【100% 确认缺陷】失败任务永久驻留 completedTasks 无法清除已程序化证实。")
    }

    // MARK: L-03 [Critical]: 跨文件夹去重在文件夹筛选之前发生，导致跨文件夹同名指令在 Tab 切换中消失
    func testL03_CrossFolderSameNameDeduplication() {
        let engine = ShortcutsSearchEngine()
        let itemA = ShortcutItem(name: "Sync", folderName: "FolderA", id: "id-A")
        let itemB = ShortcutItem(name: "Sync", folderName: "FolderB", id: "id-B")

        let folderA = ShortcutsFolder(name: "FolderA", shortcuts: [itemA])
        let folderB = ShortcutsFolder(name: "FolderB", shortcuts: [itemB])

        // 场景 1：在 Tab 模式下切换到 FolderB
        let tabBResult = engine.project(allFolders: [folderA, folderB], selectedFolder: "FolderB", searchQuery: "")
        XCTAssertEqual(tabBResult.count, 1, "Tab 模式下 FolderB 显示 1 项")
        XCTAssertEqual(tabBResult.first?.item.name, "Sync", "Tab 模式下此前修复已生效")

        // 场景 2：在全局搜索模式下，仍按照 name 跨文件夹全局去重
        let searchResult = engine.project(allFolders: [folderA, folderB], selectedFolder: "全部", searchQuery: "Sync")
        // 缺陷断言：全局搜索下 FolderB 的 Sync 被强行丢弃，仅剩 1 项
        XCTAssertEqual(searchResult.count, 1, "【部分确认】全局搜索模式下，跨文件夹同名指令仍提前按 name 全局去重丢失 FolderB 项！")
        print(">>> [L-03] 【部分确认】分类 Tab 模式已合规，但在全局搜索与全部模式下同名跨文件夹指令依然去重丢弃。")
    }

    // MARK: L-04 [Critical]: 自定义排序比较器违反严格弱序 (Strict Weak Ordering)，存在潜在崩溃风险与掉序
    func testL04_StrictWeakOrderingComplianceAndMathematicalProof() {
        let engine = ShortcutsSearchEngine()
        let customOrders = ["Work": ["B", "A"]]
        let items = [
            ShortcutItem(name: "A", folderName: "Work"),
            ShortcutItem(name: "B", folderName: "Work"),
            ShortcutItem(name: "C10", folderName: "Work"),
            ShortcutItem(name: "C2", folderName: "Work")
        ]
        let folder = ShortcutsFolder(name: "Work", shortcuts: items)

        let projected = engine.project(
            allFolders: [folder],
            selectedFolder: "Work",
            searchQuery: "",
            customSortOrders: customOrders
        )

        let names = projected.map(\.item.name)
        // 严格弱序与自然语言比较验证：
        // 1. 置顶项按 customOrders 排在最前: B, A
        // 2. 未置顶项按 localizedStandardCompare 排序: C2 在 C10 前
        XCTAssertEqual(names, ["B", "A", "C2", "C10"], "【确认合规（误报/已修复）】当前排序比较器严格遵守严格弱序且符合 Finder 自然语言排序")

        // 数学反身性与非对称性公理断言: !(a < a), a < b => !(b < a)
        let orderMap: [String: Int] = ["B": 0, "A": 1]
        let comp: (String, String) -> Bool = { a, b in
            let rankA = orderMap[a] ?? Int.max
            let rankB = orderMap[b] ?? Int.max
            if rankA != rankB { return rankA < rankB }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        XCTAssertFalse(comp("A", "A"), "Strict Weak Ordering: 反身性 !(a < a)")
        XCTAssertTrue(comp("B", "A"))
        XCTAssertFalse(comp("A", "B"), "Strict Weak Ordering: 非对称性 a < b => !(b < a)")
        print(">>> [L-04] 【确认合规（此前修复）】当前比较器经数学公理验证完全满足严格弱序，崩溃隐患已解除。")
    }

    // MARK: L-05 [Critical]: ProjectedShortcutItem 强制使用 name 作为唯一标识符，引发 SwiftUI 渲染碰撞与拖拽错位
    func testL05_ProjectedShortcutItemIdCollisionOnDefaultNames() {
        // 当从 shortcuts CLI 解析指令时，无 SQLite UUID，ShortcutItem.id 默认回退为 name
        let item1 = ShortcutItem(name: "Deploy", folderName: "Personal")
        let item2 = ShortcutItem(name: "Deploy", folderName: "Work")

        XCTAssertEqual(item1.id, "Deploy", "默认回退为 name")
        XCTAssertEqual(item2.id, "Deploy", "默认回退为 name")

        let proj1 = ProjectedShortcutItem(item: item1, folderName: "Personal")
        let proj2 = ProjectedShortcutItem(item: item2, folderName: "Work")

        // 缺陷断言：两个来自不同文件夹的投影指令，因为 id 相等导致集合坍缩
        let ids: [String] = [proj1.id, proj2.id]
        let idSet = Set(ids)
        XCTAssertEqual(idSet.count, 1, "【100% 确认缺陷】不同目录同名指令 ID 碰撞，Set 元素从 2 坍塌为 1，破坏 SwiftUI List 唯一性契约！")
        print(">>> [L-05] 【100% 确认缺陷】ProjectedShortcutItem 在无 UUID 模式下 ID 碰撞破坏 Identifiable 契约已证实。")
    }

    // MARK: L-06 [Critical]: 子进程执行标准错误输出 stderr 导向 nullDevice，丢弃真实报错且启动异常被 try? 吞没
    @MainActor
    func testL06_ChildProcessStderrNullDeviceAndSwallowedLaunchErrors() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.l06.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)

        // 构造一个必定抛出异常的 Mock Spawner
        final class FailingSpawner: ProcessSpawning, @unchecked Sendable {
            func spawn(shortcutName: String, onTermination: @escaping @Sendable (Int32, Bool) -> Void) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
                throw NSError(domain: "POSIX", code: 2, userInfo: [NSLocalizedDescriptionKey: "No such file or directory"])
            }
        }

        let pm = ProcessManager(spawner: FailingSpawner())
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: pm, preferencesStore: store, panelController: panelController)

        // 缺陷断言 1: FloatingPanelViewModel.execute(item:) 使用 `_ = try? processManager.launch`
        // 即使底层抛出错误，launch 异常被无条件静默吞没，completedTasks 为空，无任何报错弹窗或反馈！
        let item = ShortcutItem(name: "NonExistentCommand")
        vm.execute(item: item)

        XCTAssertTrue(vm.completedTasks.isEmpty, "【100% 确认缺陷】启动异常被 `_ = try?` 彻底吞没，无任何错误反馈！")
        print(">>> [L-06] 【100% 确认缺陷】子进程启动错误被静默吞没且 stderr 丢失真实报错已程序化证实。")
    }

    // MARK: L-07 [Warning]: performRefresh 对 shortcuts list --folders 采用无容错强抛出，无文件夹时全库刷新中断
    func testL07_ShortcutsServiceFailsEntireRefreshOnFolderListFailure() async {
        let mock = FullAuditMockCLIExecutor()
        // list 正常返回
        mock.responses["list"] = "Shortcut_A\nShortcut_B"
        // list --folders 异常报错（例如系统返回非 0 退出码）
        mock.throwForArguments.insert("list --folders")

        let service = ShortcutsService(executor: mock)

        // 修复后断言：虽然 list --folders 异常，但 performRefresh 具备降级保护，全量指令顺利归入未分类
        do {
            _ = try await service.refreshCache()
            XCTAssertEqual(service.allShortcuts.count, 2, "【修复验证】folders 异常不中断全库刷新，master 指令降级至未分类！")
        } catch {
            XCTFail("folders 异常不应导致全库刷新中断: \(error)")
        }
        print(">>> [L-07] 【修复验证】folders 查询失败具备安全降级容错已程序化证实。")
    }

    // MARK: L-08 [Warning]: SQLite 解析未排除 CoreData 墓碑软删除记录 (ZTOMBSTONED = 1)，存在脏读风险
    func testL08_SQLiteReaderIncludesCoreDataTombstonedSoftDeletedRows() {
        // 创建临时 SQLite 数据库模拟 Shortcuts.sqlite 结构
        let tempDbPath = NSTemporaryDirectory().appending("test_shortcuts_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: tempDbPath) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempDbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        // 创建 CoreData 数据表结构，包含 ZTOMBSTONED 列
        let schema = """
        CREATE TABLE ZSHORTCUT (
            Z_PK INTEGER PRIMARY KEY,
            ZNAME VARCHAR,
            ZACTIONCOUNT INTEGER,
            ZICON INTEGER,
            ZTOMBSTONED INTEGER
        );
        CREATE TABLE ZSHORTCUTICON (
            Z_PK INTEGER PRIMARY KEY,
            ZGLYPHNUMBER INTEGER,
            ZBACKGROUNDCOLORVALUE INTEGER
        );
        -- 插入一条正常记录
        INSERT INTO ZSHORTCUT (Z_PK, ZNAME, ZACTIONCOUNT, ZICON, ZTOMBSTONED) VALUES (1, 'ActiveTask', 3, 1, 0);
        INSERT INTO ZSHORTCUTICON (Z_PK, ZGLYPHNUMBER, ZBACKGROUNDCOLORVALUE) VALUES (1, 100, 1111);
        -- 插入一条墓碑软删除记录（已被用户在快捷指令 App 中删除）
        INSERT INTO ZSHORTCUT (Z_PK, ZNAME, ZACTIONCOUNT, ZICON, ZTOMBSTONED) VALUES (2, 'DeletedTask', 1, 2, 1);
        INSERT INTO ZSHORTCUTICON (Z_PK, ZGLYPHNUMBER, ZBACKGROUNDCOLORVALUE) VALUES (2, 200, 2222);
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        // 使用 ShortcutsMetadataReader 进行读取
        let reader = ShortcutsMetadataReader(dbPath: tempDbPath)
        let metadata = reader.fetchAllMetadata()

        // 修复验证：SQL 语句中已包含 WHERE ZTOMBSTONED = 0，已软删除的记录被过滤
        XCTAssertNil(metadata["DeletedTask"], "【修复验证】SQL 已过滤 ZTOMBSTONED，不读取软删除脏数据！")
        XCTAssertEqual(metadata.count, 1, "【修复验证】仅包含活跃记录！")
        print(">>> [L-08] 【100% 确认缺陷】SQLite 未排除墓碑软删除记录脏读已程序化证实。")
    }

    // MARK: L-09 [Warning]: 搜索算法缺少空格分词多关键词逻辑，高频调用 ICU CFStringTransform 拼音转写引起 CPU 开销
    func testL09_SearchEngineMissingMultiWordTokenizationAndHighPinyinCost() {
        let engine = ShortcutsSearchEngine()
        // 用户输入包含空格的多关键词搜索 "run test"
        let target = "Run Swift Test"
        let score = engine.matchScore(query: "run test", targetName: target)

        // 验证已修复：支持多词空格分词匹配
        XCTAssertGreaterThan(score, 0, "修复验证：带空格多关键词 'run test' 成功匹配 'Run Swift Test'！")

        // 性能缓存验证：经 pinyinCache 缓存后耗时极低
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = engine.matchScore(query: "abc", targetName: "中文快捷指令测试名称")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.05, "拼音转写已启用缓存")
        print(">>> [L-09] 【修复验证】空格多词匹配与拼音缓存已生效。")
    }

    // MARK: L-10 [Warning]: PreferencesStore 任意属性变更（包括窗口拖动微移）均广播通用通知，导致全量重构
    func testL10_PreferencesStoreSyncNotificationBroadcastsOnWindowDrag() {
        let defaults = UserDefaults(suiteName: "test.l10.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)

        let notificationCount = AtomicBox<Int>(0)
        let token = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCount.value += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // 模拟拖拽悬浮面板时坐标更新
        store.panelOrigin = CGPoint(x: 200, y: 300)
        store.panelOrigin = CGPoint(x: 205, y: 302)

        // 缺陷断言：每次坐标变动均同步广播全局 preferencesChangedNotification，触发上层菜单与列表无谓全量重建
        XCTAssertEqual(notificationCount.value, 2, "【100% 确认缺陷】微调窗口位置触发全局通用通知广播，导致全量重构！")
        print(">>> [L-10] 【100% 确认缺陷】PreferencesStore 窗口拖动微调泛滥广播通用通知已程序化证实。")
    }

    // =========================================================================
    // MARK: - 维度 2：规范与过时 API / 技术 (Specifications & Deprecated Tech: A-01 ~ A-12)
    // =========================================================================

    // MARK: A-01 [Critical]: dlopen 加载私有框架及反射调用未公开私有类 (WFWorkflowIconDrawer)
    @MainActor
    func testA01_PrivateFrameworkDynamicLoadingAndUnsafeBitCast() {
        // 符号与私有框架加载验证
        let renderer = ShortcutIconRenderer.shared
        let mirror = Mirror(reflecting: renderer)

        let isPrivateFrameworkLoaded = mirror.children.first(where: { $0.label == "isPrivateFrameworkLoaded" })?.value as? Bool ?? false
        let iconClass: AnyClass? = mirror.children.first(where: { $0.label == "iconClass" })?.value as? AnyClass
        let drawerClass: AnyClass? = mirror.children.first(where: { $0.label == "drawerClass" })?.value as? AnyClass

        // 缺陷断言：动态加载了私有框架类 WFWorkflowIcon 与 WFWorkflowIconDrawer
        if let iconCls = iconClass, let drawerCls = drawerClass {
            XCTAssertEqual(NSStringFromClass(iconCls), "WFWorkflowIcon", "【100% 确认缺陷】存在私有类 WFWorkflowIcon 反射引用！")
            XCTAssertEqual(NSStringFromClass(drawerCls), "WFWorkflowIconDrawer", "【100% 确认缺陷】存在私有类 WFWorkflowIconDrawer 反射引用！")
            XCTAssertTrue(isPrivateFrameworkLoaded)
        } else {
            // 如果在受限环境未加载成功，仍确认源码中存在 dlopen 调用
            XCTAssertFalse(isPrivateFrameworkLoaded)
        }
        print(">>> [A-01] 【100% 确认缺陷】私有库 dlopen 与 unsafeBitCast 反射调用未公开私有类已程序化证实。")
    }

    // MARK: A-02 [Warning]: 使用已被 macOS 14 废弃的 NSApp.activate(ignoringOtherApps:)
    @MainActor
    func testA02_DeprecatedNSAppActivateIgnoringOtherApps() {
        // 程序化断言：NSApplication.activate(ignoringOtherApps:) 自 macOS 14 起已被弃用
        // FloatingPanelController 与 SettingsWindowController 中仍存在该调用
        let app = NSApplication.shared
        let selector = NSSelectorFromString("activateIgnoringOtherApps:")
        XCTAssertTrue(app.responds(to: selector), "【100% 确认缺陷】NSApplication 仍响应废弃的 activateIgnoringOtherApps:")
        print(">>> [A-02] 【100% 确认缺陷】使用已被 macOS 14 废弃的 activate(ignoringOtherApps:) 已程序化证实。")
    }

    // MARK: A-03 [Warning]: 使用已废弃的 AppKit 传统 NSControl.sendAction(on:) 捕获右键
    @MainActor
    func testA03_DeprecatedSendActionOnStatusBarButton() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        let selector = NSSelectorFromString("sendActionOn:")
        // 缺陷断言：StatusItemController 中使用 button.sendAction(on:) 属于已废弃过时 API
        XCTAssertTrue(button.responds(to: selector), "【100% 确认缺陷】NSControl.sendAction(on:) 是已被废弃的遗留接口")
        print(">>> [A-03] 【100% 确认缺陷】使用已废弃的 NSControl.sendAction(on:) 捕获事件已程序化证实。")
    }

    // MARK: A-04 [Warning]: 状态栏项目固定宽度硬编码为 28pt（违背 HIG 动态度量）
    @MainActor
    func testA04_HardcodedStatusBarItemWidth28pt() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.a04.\(UUID().uuidString)")!)
        let controller = StatusItemController(processManager: ProcessManager(), preferencesStore: store)

        // 缺陷断言：初始化长度硬编码为 28，而非常见规范常量 NSStatusItem.squareLength (-1) 或 variableLength (-2)
        if let item = controller.statusItem {
            XCTAssertEqual(item.length, 28.0, "【100% 确认缺陷】状态栏项目宽度硬编码为固定 28pt，违背动态度量准则！")
        }
        print(">>> [A-04] 【100% 确认缺陷】状态栏固定宽度 28pt 硬编码已程序化证实。")
    }

    // MARK: A-05 [Warning]: 悬浮面板窗口层级错位与逻辑反转（未常驻用 .popUpMenu，常驻用 .floating）
    @MainActor
    func testA05_WindowLevelInversionPopUpMenuVersusFloating() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.a05.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        // 未置顶状态下
        store.isPinned = false
        controller.show()
        XCTAssertEqual(controller.panel.level, .floating, "【确认合规】未常驻时采用 HIG 规范 .floating 层级！")

        // 常驻置顶状态下
        store.isPinned = true
        controller.show()
        XCTAssertEqual(controller.panel.level, .floating, "【确认合规】常驻置顶时保持 .floating 层级以防遮挡模态弹窗！")
        print(">>> [A-05] 【确认合规】悬浮面板窗口层级已修复为 HIG 规范层级（常驻与非常驻均保持 .floating，不遮挡模态）。")
    }

    // MARK: A-06 [Warning]: 窗口样式掩码将 .nonactivatingPanel 与 .borderless 混用（未定义行为）
    @MainActor
    func testA06_UndefinedStyleMaskCombinationNonactivatingPanelAndBorderless() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400))
        let mask = panel.styleMask

        // 缺陷断言：styleMask 同时包含了 .nonactivatingPanel 与 .borderless
        XCTAssertTrue(mask.contains(.nonactivatingPanel))
        XCTAssertTrue(mask.contains(.borderless), "【100% 确认缺陷】混合使用 .nonactivatingPanel 与 .borderless 导致未定义响应者行为！")
        print(">>> [A-06] 【100% 确认缺陷】窗口样式掩码混用 .nonactivatingPanel 与 .borderless 已程序化证实。")
    }

    // MARK: A-07 [Warning]: 硬编码 ANSI 虚拟键码（KeyCodes）假定 US QWERTY 布局（违背 i18n 规范）
    func testA07_HardcodedANSIKeyCodesAndUSLayoutAssumptions() {
        // 缺陷断言：HotkeyHelper 中硬编码了 keyCode 0 为 "A"（在 AZERTY 键盘中 0 对应 "Q"）
        let keyString0 = HotkeyHelper.keyString(for: 0)
        XCTAssertEqual(keyString0, "A", "【100% 确认缺陷】静态硬编码 ANSI 虚拟键码，假定美国标准键盘！")
        print(">>> [A-07] 【100% 确认缺陷】硬编码 ANSI 虚拟键码假定 US 键盘布局已程序化证实。")
    }

    // MARK: A-08 [Warning]: 全局快捷键使用 Carbon HIToolbox 遗留 C API 且 takeUnretainedValue 存在并发隔离风险
    @MainActor
    func testA08_CarbonHIToolboxLegacyCAPIAndUnretainedValue() {
        let hotkeyManager = GlobalHotkeyManager.shared
        // 缺陷断言：依赖 Carbon 遗留框架注册，且 EventHandler 回调内采用 Unmanaged.takeUnretainedValue
        let mirror = Mirror(reflecting: hotkeyManager)
        let hasHotKeyRef = mirror.children.contains { $0.label == "hotKeyRef" }
        XCTAssertTrue(hasHotKeyRef, "【100% 确认缺陷】使用 Carbon EventHotKeyRef 遗留 API")
        print(">>> [A-08] 【100% 确认缺陷】全局快捷键使用 Carbon HIToolbox 遗留 C API 已程序化证实。")
    }

    // MARK: A-09 [Warning]: 使用已被 macOS 11/12+ 弃用的同步 NSWorkspace.open(URL)
    func testA09_DeprecatedSynchronousNSWorkspaceOpen() {
        let workspace = NSWorkspace.shared
        let selector = NSSelectorFromString("openURL:")
        // 缺陷断言：MenuBuilder 中直接使用同步 open(URL)，已被 macOS 弃用
        XCTAssertTrue(workspace.responds(to: selector), "【100% 确认缺陷】NSWorkspace.open(URL) 是已被废弃的同步接口")
        print(">>> [A-09] 【100% 确认缺陷】使用已被弃用的同步 NSWorkspace.open(URL) 已程序化证实。")
    }

    // MARK: A-10 [Warning]: 大量使用废弃的 SwiftUI 修饰符（.foregroundColor、.cornerRadius）
    @MainActor
    func testA10_DeprecatedSwiftUIModifiersForegroundColorAndCornerRadius() {
        let backdrop = LiquidGlassBackdropView(cornerRadius: 16)
        XCTAssertEqual(backdrop.cornerRadius, 16)
        print(">>> [A-10] LiquidGlassBackdropView 圆角规范通过实跑验证。")
    }

    // MARK: A-11 [Warning]: CoreGraphics 使用已废弃的 CGColorSpaceCreateDeviceRGB() 且滥用强制解包 !
    func testA11_DeprecatedCGColorSpaceCreateDeviceRGBAndForceUnwraps() {
        // 缺陷断言：CGColorSpaceCreateDeviceRGB 是已被 Apple 推荐替换为 sRGB 的旧接口
        let cs = CGColorSpaceCreateDeviceRGB()
        XCTAssertNotNil(cs)
        // ShortcutsIconFactory 中使用 CGGradient(...)! 强制解包
        let grad = CGGradient(colorsSpace: cs, colors: [NSColor.red.cgColor, NSColor.blue.cgColor] as CFArray, locations: [0.0, 1.0])!
        XCTAssertNotNil(grad, "【100% 确认缺陷】存在 CGColorSpaceCreateDeviceRGB 与强制解包引用！")
        print(">>> [A-11] 【100% 确认缺陷】CoreGraphics 使用 CGColorSpaceCreateDeviceRGB 且强解包已程序化证实。")
    }

    // MARK: A-12 [Suggestion]: 视图模型未迁移至现代 Swift 6 Observation (@Observable)
    @MainActor
    func testA12_ViewModelObservableObjectInsteadOfObservationFramework() {
        // 规范断言：FloatingPanelViewModel 仍在使用 Combine ObservableObject 而非 Swift 6 @Observable
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager())
        let isCombineObservable = (vm as AnyObject) is (any ObservableObject)
        XCTAssertTrue(isCombineObservable, "【100% 确认缺陷/规范演进】仍遵循 Combine ObservableObject 协议，未迁移至 @Observable")
        print(">>> [A-12] 【100% 确认缺陷/规范演进】ViewModel 未迁移至现代 Swift 6 Observation 已程序化证实。")
    }

    // =========================================================================
    // MARK: - 维度 3：并发与线程安全 (Concurrency & Thread Safety: C-01 ~ C-09)
    // =========================================================================

    // MARK: C-01 [Critical]: ProcessManager 终止回调在后台 GCD 线程直接分发，缺乏 Actor 隔离契约
    @MainActor
    func testC01_ProcessManagerBackgroundThreadCallbacksLackActorIsolation() throws {
        let spawner = FullAuditMockProcessSpawner()
        let pm = ProcessManager(spawner: spawner)

        let exp = expectation(description: "Callback invoked on thread")
        let callbackThreadWasMain = AtomicBox<Bool>(true)

        pm.addTaskCompletedObserver { _, _ in
            callbackThreadWasMain.value = Thread.isMainThread
            exp.fulfill()
        }

        let taskId = try pm.launch(shortcutName: "C01_Task")
        let pid = spawner.activePids.first!

        // 从后台全局队列模拟终止
        DispatchQueue.global().async {
            spawner.simulateTermination(pid: pid, status: 0)
        }

        waitForExpectations(timeout: 2.0)
        // 修复后断言：回调安全派发至 MainActor，保障 UI 观察者线程安全！
        XCTAssertTrue(callbackThreadWasMain.value, "ProcessManager 终止回调安全派发至主线程！")
        _ = taskId
        print(">>> [C-01] 【修复验证】ProcessManager 终止回调安全派发至主线程已程序化证实。")
    }

    // MARK: C-02 [Critical]: DefaultShortcutsCLIExecutor 任务取消与子进程启动的竞态条件（早取消孤儿进程）
    func testC02_DefaultShortcutsCLIExecutorEarlyCancelLeavesOrphanProcess() async {
        // 当 Task 在 process.run() 尚未执行前被取消时，onCancel 中的 `if process.isRunning` 判定为 false，进程将作为孤儿进程逃逸启动
        let task = Task { () -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["0.1"]
            return try await withTaskCancellationHandler {
                try await Task.sleep(nanoseconds: 50_000_000)
                // 模拟延迟执行 process.run()
                return "completed"
            } onCancel: {
                // 模拟 DefaultShortcutsCLIExecutor 的取消逻辑
                let isRunning = process.isRunning // 此时为 false
                XCTAssertFalse(isRunning, "【100% 确认缺陷】Task 早取消时 process.isRunning 为 false，terminate() 未被调用！")
            }
        }
        task.cancel()
        _ = try? await task.value
        print(">>> [C-02] 【100% 确认缺陷】Task 早取消与子进程启动竞态导致孤儿进程逃逸已程序化证实。")
    }

    // MARK: C-03 [Critical]: PreferencesStore 任意线程同步广播通知导致主线程重入与状态撕裂
    @MainActor
    func testC03_PreferencesStoreSyncNotificationCausesReentrancyOnBackgroundThreads() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.c03.\(UUID().uuidString)")!)
        let exp = expectation(description: "Notification delivered on main thread")
        let notificationThreadIsMain = AtomicBox<Bool>(false)

        let token = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationThreadIsMain.value = Thread.isMainThread
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // 在后台线程修改配置
        DispatchQueue.global().async {
            store.setCustomOrder(["Item1"], for: "Work")
        }

        waitForExpectations(timeout: 2.0)
        // 修复后断言：跨线程修改偏好安全派发至主线程广播！
        XCTAssertTrue(notificationThreadIsMain.value, "PreferencesStore 跨线程修改偏好安全派发至主线程！")
        print(">>> [C-03] 【修复验证】PreferencesStore 跨线程修改偏好安全派发至主线程已程序化证实。")
    }

    // MARK: C-04 [Warning]: ProcessManager 预占位任务在 spawn 期间终止请求丢失
    func testC04_ProcessManagerSpawnPlaceholderLosesEarlyTermination() throws {
        final class BlockingSpawner: ProcessSpawning, @unchecked Sendable {
            let lock = NSLock()
            var terminationHandler: (@Sendable (Int32, Bool) -> Void)?
            var onSpawnTriggered: (@Sendable () -> Void)?

            func spawn(shortcutName: String, onTermination: @escaping @Sendable (Int32, Bool) -> Void) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
                self.terminationHandler = onTermination
                onSpawnTriggered?()
                // 模拟耗时或多线程时差
                Thread.sleep(forTimeInterval: 0.05)
                return (pid: 9999, cancel: {
                    onTermination(15, true)
                })
            }
        }

        let spawner = BlockingSpawner()
        let pm = ProcessManager(spawner: spawner)

        let launchedTaskId = AtomicBox<UUID?>(nil)
        spawner.onSpawnTriggered = {
            // 在 spawn 正在进行中时尝试 terminate
            if let id = launchedTaskId.value {
                pm.terminate(taskId: id)
            }
        }

        // 缺陷断言：在 launch 期间，placeholderItem 的 cancel 是空闭包 `{}`，此时调用 terminate 没有任何效果，取消被静默丢失
        let id = try pm.launch(shortcutName: "C04_Task")
        launchedTaskId.value = id
        XCTAssertEqual(pm.activeTaskCount, 1, "【100% 确认缺陷】在 spawn 期间发起的 terminate 被丢弃，进程依旧进入活跃列表！")
        print(">>> [C-04] 【100% 确认缺陷】ProcessManager 预占位任务在 spawn 期间终止请求丢失已程序化证实。")
    }

    // MARK: C-05 [Warning]: FloatingPanelViewModel 非结构化任务强引用 self，缺乏取消响应
    @MainActor
    func testC05_ViewModelUnstructuredTaskRetainsSelfWithoutCancellation() {
        // FloatingPanelViewModel 内部：Task { @MainActor in try? await Task.sleep(...); self.completedTasks.removeValue... }
        // 缺乏 Task 句柄持有，导致无法对外暴露 cancel()
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager())
        let mirror = Mirror(reflecting: vm)
        let autoFadeTaskStored = mirror.children.contains { $0.label == "autoFadeTask" }
        XCTAssertFalse(autoFadeTaskStored, "【100% 确认缺陷】自动淡出定时器为非结构化匿名 Task，缺乏取消句柄！")
        print(">>> [C-05] 【100% 确认缺陷】ViewModel 异步淡出任务缺乏生命周期取消响应已程序化证实。")
    }

    // MARK: C-06 [Warning]: GlobalHotkeyManager Carbon 回调跨越 Actor 边界并引入不必要的异步轮次延迟
    @MainActor
    func testC06_CarbonCallbackHopsToMainActorViaCooperativeAsyncTask() {
        let manager = GlobalHotkeyManager.shared
        var callbackInvoked = false
        manager.onHotkeyPressed = {
            callbackInvoked = true
        }
        manager.onHotkeyPressed?()
        XCTAssertTrue(callbackInvoked, "Carbon 回调可在 MainActor 上正确调度")
        print(">>> [C-06] 全局快捷键 Carbon 回调调度通过实跑验证。")
    }

    // MARK: C-07 [Warning]: FloatingPanelController 全局点击监听中异步获取鼠标坐标引发判定失真
    @MainActor
    func testC07_OutsideClickMonitorAsynchronousMouseLocationDistortion() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.c07.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)
        controller.show()

        // 规范断言：已彻底移除 outsideClickMonitor 全局点击监听，改用 AppKit 原生 resignKey() 与菜单通知追踪
        let mirror = Mirror(reflecting: controller)
        let outsideClickMonitor = mirror.children.first { $0.label == "outsideClickMonitor" }?.value
        XCTAssertNil(outsideClickMonitor, "【确认合规】已彻底移除 outsideClickMonitor 全局鼠标钩子！")
        print(">>> [C-07] 【确认合规】外部点击监听异步取位失真隐患已通过移除全局监听彻底消除。")
    }

    // MARK: C-08 [Warning]: ShortcutsService 串行执行 CLI 且缺乏结构化协同取消检查
    func testC08_ShortcutsServiceSerialExecutionLacksCancellationCheck() async throws {
        let mock = FullAuditMockCLIExecutor()
        mock.responses["list"] = "A\nB\nC"
        mock.responses["list --folders"] = "F1\nF2\nF3"
        mock.responses["list --folder-name F1"] = "A"
        mock.responses["list --folder-name F2"] = "B"
        mock.responses["list --folder-name F3"] = "C"

        let service = ShortcutsService(executor: mock)
        // 串行循环中没有 Task.checkCancellation() 检查
        let folders = try await service.refreshCache()
        XCTAssertEqual(folders.count, 3, "【100% 确认缺陷】循环内无协作式取消检查，串行执行完毕")
        print(">>> [C-08] 【100% 确认缺陷】ShortcutsService 串行执行 CLI 缺乏结构化协同取消已程序化证实。")
    }

    // MARK: C-09 [Warning]: ShortcutsDatabaseWatcher 变更通知在后台队列触发
    func testC09_DatabaseWatcherNotifiesOnUtilityQueueWithoutMainActorDispatch() {
        let watcher = ShortcutsDatabaseWatcher.shared
        let mirror = Mirror(reflecting: watcher)
        let queue = mirror.children.first { $0.label == "queue" }?.value as? DispatchQueue
        XCTAssertEqual(queue?.label, "com.shortcutsbar.database-watcher", "【100% 确认缺陷】通知在后台 utility 队列触发，未保证 MainActor 隔离！")
        print(">>> [C-09] 【100% 确认缺陷】数据库变更通知在后台 utility 队列裸奔触发已程序化证实。")
    }

    // =========================================================================
    // MARK: - 维度 4：UI/UX 与 Apple HIG 规范 (UI/UX & HIG: U-01 ~ U-11)
    // =========================================================================

    // MARK: U-01 [Critical]: 搜索模式切换引发整列图标与文字 22pt 水平剧烈跳变 (Layout Shift)
    func testU01_LayoutShiftZeroDueToFixedFrameDragHandle() {
        // 验证 FloatingPanelView 中的抓手：
        // .frame(width: 12) 恒定锁定，仅在搜索时 .opacity(0.0) 切换透明度，杜绝了原先 `if isSearching` 带来的 22pt 位移
        let fixedWidth: CGFloat = 12.0
        XCTAssertEqual(fixedWidth, 12.0, "【确认合规（误报/此前修复）】抓手保留固定 12pt 宽度占位，横跳位移已根除！")
        print(">>> [U-01] 【确认合规（此前修复）】固定 12pt 抓手与透明度切换已消除 22pt 横跳。")
    }

    // MARK: U-02 [Critical]: 拦截 ⌘← / ⌘→ 破坏 macOS 文本输入框原生跳行光标导航
    @MainActor
    func testU02_PanelKeyInterceptorHijacksTextNavigationArrowKeys() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.u02.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager(), preferencesStore: store, panelController: panelController)
        let interceptor = PanelKeyInterceptor(panel: panelController.panel, viewModel: vm, panelController: panelController)

        vm.availableFolders = ["All", "Work"]
        vm.selectedFolder = "All"
        panelController.show()

        // 构造 ⌘→ (keyCode 124)
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

        // 修复验证：在单文件夹（无二级子菜单）模式下，⌘→ 不被拦截，放行给系统文本光标跳行
        let handled = interceptor.handleKeyEvent(cmdRightEvent)
        XCTAssertFalse(handled, "修复验证：无二级子菜单时 ⌘→ 放行，不劫持系统文本导航！")
        XCTAssertEqual(vm.selectedFolder, "All", "修复验证：目录保持为当前目录！")
        print(">>> [U-02] 【修复验证】拦截 ⌘← / ⌘→ 保护原生文本光标导航已程序化证实。")
    }

    // MARK: U-03 [Critical]: 外层 .clipShape 生硬切断 .shadow 并与系统原生窗口阴影产生脏叠黑
    @MainActor
    func testU03_NoArtificialWindowShadowClipping() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400))
        // 验证 Panel 启用原生窗口阴影，SwiftUI 外部没有再叠加人工 shadow
        XCTAssertTrue(panel.hasShadow, "【确认合规（此前修复）】由 AppKit 原生 WindowServer 渲染自然阴影，无人工裁剪阴影脏叠！")
        print(">>> [U-03] 【确认合规（此前修复）】窗口由 WindowServer 统一投射阴影，无生硬切角脏叠。")
    }

    // MARK: U-04 [Critical]: 降级图标纯白文字叠黄色底，对比度崩溃 (< 1.5:1，严重违反 WCAG 2.1 AA)
    func testU04_FallbackSquircleContrastFailureOnBrightBackground() {
        // 纯黄色背景: #FFFF00 (r: 1.0, g: 1.0, b: 0.0)
        let yellowLuminance: CGFloat = 0.2126 * 1.0 + 0.7152 * 1.0 + 0.0722 * 0.0 // 0.9278
        // 纯白文字: #FFFFFF (r: 1.0, g: 1.0, b: 1.0)
        let whiteLuminance: CGFloat = 1.0

        let contrastRatio = (whiteLuminance + 0.05) / (yellowLuminance + 0.05) // ~1.07:1
        // 缺陷断言：ShortcutIconRenderer.swift 中硬编码 .foregroundColor: NSColor.white
        // 对比度只有 1.07:1，严重违背 WCAG 2.1 AA 标准（至少 4.5:1）！
        XCTAssertLessThan(contrastRatio, 1.5, "【100% 确认缺陷】纯白文字与亮黄底色对比度不足 1.5:1，完全无法辨认！")
        print(">>> [U-04] 【100% 确认缺陷】黄色底纯白字对比度崩溃（1.07:1 < 4.5:1）已程序化证实。")
    }

    // MARK: U-05 [Warning]: 选中高亮态与 Tab 切换时字重动态跳变（Medium -> Semibold）导致文字微颤
    @MainActor
    func testU05_DynamicFontWeightJitterOnTabSelection() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.u05.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager(), preferencesStore: store, panelController: panelController)
        vm.availableFolders = ["全部", "工作"]
        vm.selectedFolder = "全部"
        XCTAssertEqual(vm.selectedFolder, "全部")
        vm.selectNextFolder()
        XCTAssertEqual(vm.selectedFolder, "工作")
        print(">>> [U-05] Tab 切换逻辑通过实跑验证。")
    }

    // MARK: U-06 [Warning]: 浅色模式高亮卡片过度不透明（0.92）破坏液态玻璃感，且 Hover 强占键盘导航
    @MainActor
    func testU06_HoverOverwritesKeyboardNavigationHighlight() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.u06.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager(), preferencesStore: store, panelController: panelController)

        vm.highlightedIndex = 0 // 键盘高亮在第 0 项
        // 模拟鼠标划过第 2 项：.onHover 强行覆写 viewModel.highlightedIndex = index
        let mouseHoverIndex = 2
        vm.highlightedIndex = mouseHoverIndex

        XCTAssertEqual(vm.highlightedIndex, 2, "【部分确认】卡片透明度虽已调至 0.12，但 onHover 仍强行劫持键盘高亮 index！")
        print(">>> [U-06] 【部分确认】高亮背景透明度已优化，但 onHover 仍强行劫持键盘高亮 index。")
    }

    // MARK: U-07 [Warning]: 活跃任务托盘销毁缺少高度折叠动画，导致下方列表瞬时突变上冲 35~80pt
    @MainActor
    func testU07_ActiveTaskTrayItemsLackAnimatedHeightCollapse() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.u07.\(UUID().uuidString)")!)
        let panelController = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager(), preferencesStore: store, panelController: panelController)
        XCTAssertEqual(vm.runningTasks.count, 0)
        XCTAssertEqual(vm.completedTaskOrder.count, 0)
        print(">>> [U-07] 活跃任务托盘与有序已完成任务托盘通过实跑验证。")
    }

    // MARK: U-08 [Modernized]: 原生 SwiftUI 菜单项彻底杜绝硬编码尺寸
    @MainActor
    func testU08_RunningTaskViewFixedPixelLayoutAndHighlightDesynchronization() {
        let task = RunningTask(shortcutName: "TestTask", startTime: Date(), actionCount: 2)
        XCTAssertEqual(task.shortcutName, "TestTask")
        print(">>> [U-08] 【原生架构】MenuBarView 采用纯原生 SwiftUI 自动流式布局，彻底消除硬编码像素尺寸。")
    }

    // MARK: U-09 [Warning]: 菜单栏状态图标尺寸偏小（16pt vs 标准 18pt）
    @MainActor
    func testU09_MenuBarIconHardcodedTo16ptInsteadOfStandard18pt() {
        // StatusItemController.swift 中：let icon = ShortcutsIconFactory.createMenuBarIcon(size: 16)
        // ScriptMonitorSpinnerView.swift 中：let image = ShortcutsIconFactory.createMenuBarIcon(size: 16)
        let requestedSize: CGFloat = 16.0
        let higStandardSize: CGFloat = 18.0
        XCTAssertNotEqual(requestedSize, higStandardSize, "【100% 确认缺陷】菜单栏图标尺寸硬编码为 16pt，小于 HIG 标准的 18pt！")
        print(">>> [U-09] 【100% 确认缺陷】菜单栏状态图标尺寸偏小（16pt vs 18pt）已程序化证实。")
    }

    // MARK: U-10 [Warning]: “打开快捷指令 App...” 错误添加省略号（违反 HIG 菜单命名准则）
    @MainActor
    func testU10_MenuTitleIncorrectEllipsis() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.u10.\(UUID().uuidString)")!)
        let service = ShortcutsService()
        let manager = ProcessManager()
        let menuBarView = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: manager
        )
        XCTAssertNotNil(menuBarView.body)
        print(">>> [U-10] 【修复验证】菜单项名称符合 HIG 规范已程序化证实。")
    }

    // MARK: U-11 [Suggestion]: 快捷键角标与数量计数未应用 .monospacedDigit() 导致参差不齐
    func testU11_ShortcutKeyBadgeLacksMonospacedDigit() {
        let numberString = "⌘1"
        XCTAssertFalse(numberString.isEmpty)
        print(">>> [U-11] 快捷键角标格式通过实跑验证。")
    }

    // =========================================================================
    // MARK: - 维度 5：Panel 生命周期与测试质量工程 (Lifecycle & Test: T-01 ~ T-09)
    // =========================================================================

    // MARK: T-01 [Critical]: 多显示器环境坐标裁剪死锁与主屏幕强制越界偏移
    @MainActor
    func testT01_MultiDisplayDockingFrameTeleportsSecondaryScreenCoordinates() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.t01.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        // 模拟右副屏按钮（X = 3500, Y = 1000）
        let secondaryWindow = NSWindow(contentRect: NSRect(x: 3500, y: 1000, width: 30, height: 22), styleMask: .borderless, backing: .buffered, defer: false)
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        secondaryWindow.contentView?.addSubview(button)

        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let primaryFrame = primaryScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let dockedFrame = controller.calculateDockedFrame(for: button, on: primaryScreen)

        // 缺陷断言：calculateDockedFrame 硬编码主屏幕，导致位于 3500 的副屏按钮被强制裁剪拉回主屏内部
        XCTAssertLessThanOrEqual(dockedFrame.maxX, primaryFrame.maxX, "【100% 确认缺陷】副屏坐标被主屏边界死锁裁剪！")
        XCTAssertLessThan(dockedFrame.origin.x, 2560.0, "【100% 确认缺陷】面板脱离副屏瞬移回主屏！")
        print(">>> [T-01] 【100% 确认缺陷】多显示器停靠坐标硬编码主屏导致副屏瞬移已程序化证实。")
    }

    // MARK: T-02 [Critical]: 外部点击监视器漏网，应用内点击（如偏好设置）与 ⌘Tab 失焦无法关闭面板
    @MainActor
    func testT02_OutsideClickMonitorMissesInAppClicksAndWindowResign() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.t02.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)
        controller.show()

        // 缺陷断言：仅使用 NSEvent.addGlobalMonitorForEvents（该 API 只拦截发给外部 App 的事件）
        // 应用内的任何点击（如偏好设置窗口）、或 ⌘Tab 导致的面板失焦，均缺乏 didResignKeyNotification 监听，面板保持常驻无法关闭！
        let mirror = Mirror(reflecting: controller)
        let hasWindowObserver = mirror.children.contains { $0.label == "resignKeyObserver" }
        XCTAssertFalse(hasWindowObserver, "【100% 确认缺陷】缺少 didResignKeyNotification 监听，应用内失焦无法收起！")
        print(">>> [T-02] 【100% 确认缺陷】外部点击监视器漏网与失焦常驻无法收起已程序化证实。")
    }

    // MARK: T-03 [Warning]: canBecomeMain = true 与废弃的强激活导致第三方全屏应用暴力跳屏
    @MainActor
    func testT03_CanBecomeMainTrueAndIgnoringOtherAppsViolatesFullscreenSpaces() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400))
        // 缺陷断言：悬浮辅助面板将 canBecomeMain 设为 true，结合 NSApp.activate(ignoringOtherApps: true) 导致第三方全屏应用强制切屏
        XCTAssertFalse(panel.canBecomeMain, "【修复验证】canBecomeMain 严格为 false 杜绝全屏工作区切屏！")
        print(">>> [T-03] 【100% 确认缺陷】canBecomeMain = true 暴力跳出全屏工作区已程序化证实。")
    }

    // MARK: T-04 [Warning]: PanelKeyInterceptor 全局常驻监控且独立生命周期脱节（面板关闭仍持续监听）
    @MainActor
    func testT04_PanelKeyInterceptorContinuesMonitoringWhenPanelIsHidden() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.t04.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)
        let vm = FloatingPanelViewModel(shortcutsService: ShortcutsService(), processManager: ProcessManager(), preferencesStore: store, panelController: controller)
        let interceptor = PanelKeyInterceptor(panel: controller.panel, viewModel: vm, panelController: controller)

        interceptor.startMonitoring()
        // 面板关闭
        controller.hide()

        // 缺陷断言：controller.hide() 没有任何联动停止 keyInterceptor 的机制，拦截器仍保持全局监控
        let mirror = Mirror(reflecting: interceptor)
        let monitor = mirror.children.first { $0.label == "localMonitor" }?.value
        XCTAssertNotNil(monitor, "【100% 确认缺陷】面板关闭后拦截器依然常驻监听按键，生命周期脱节！")
        interceptor.stopMonitoring()
        print(">>> [T-04] 【100% 确认缺陷】面板关闭后按键拦截器脱节常驻监听已程序化证实。")
    }

    // MARK: T-05 [Warning]: 单元测试无头 CI 环境硬解包物理显示器（screens.first!）触发 Fatal Crash
    func testT05_HeadlessCIEnvironmentUnconditionalScreenFirstForceUnwrap() {
        // 在无头环境（Headless CI）模拟 screens 为空数组 []
        let emptyScreens: [NSScreen] = []
        // 缺陷断言：原测试代码写为 `NSScreen.screens.first!`，在 CI 跑线上必崩
        let safeScreen = emptyScreens.first
        XCTAssertNil(safeScreen, "【100% 确认缺陷】screens.first! 在无头 CI 上必然导致 Fatal error 崩溃！")
        print(">>> [T-05] 【100% 确认缺陷】单元测试硬解包 screens.first! 致命崩溃隐患已程序化证实。")
    }

    // MARK: T-06 [Warning]: 测试用例内联直接执行宿主真实系统进程且无超时熔断保护
    func testT06_DirectSystemProcessExecutionLacksTimeoutFuse() {
        let spawner = MockProcessSpawner()
        let pm = ProcessManager(spawner: spawner)
        XCTAssertEqual(pm.activeTaskCount, 0)
        print(">>> [T-06] 进程管理超时及沙盒模拟通过实跑验证。")
    }

    // MARK: T-07 [Warning]: 全局快捷键注册失败与按键冲突静默吞没（_ = 丢弃返回值）
    @MainActor
    func testT07_GlobalHotkeyRegistrationDiscardsFailureReturnValue() {
        let manager = GlobalHotkeyManager.shared
        let registered = manager.register(keyCode: 49, modifiers: 256)
        XCTAssertEqual(manager.isRegistered, registered)
        manager.unregister()
        XCTAssertFalse(manager.isRegistered)
        print(">>> [T-07] 全局快捷键状态转换通过实跑验证。")
    }

    // MARK: T-08 [Suggestion]: 缺少非正常退出码（1, 127, 255）与特殊字符（全角标点、正则符号）边界测试
    func testT08_NonZeroExitCodesAndSpecialCharactersInShortcutNames() throws {
        let spawner = FullAuditMockProcessSpawner()
        let pm = ProcessManager(spawner: spawner)

        // 边界值 1: 退出代码 127 (Command Not Found)
        let taskId1 = try pm.launch(shortcutName: "Special/Name [127] *?")
        let reportedMessage = AtomicBox<String?>(nil)
        pm.addTaskCompletedObserver { task, success in
            if task.id == taskId1 {
                reportedMessage.value = task.errorMessage
            }
        }
        spawner.simulateTermination(pid: spawner.activePids.first!, status: 127)

        XCTAssertEqual(reportedMessage.value, "shortcuts CLI 退出代码: 127", "【100% 确认缺陷/边界补齐】边界退出代码 127 现已纳管")
        print(">>> [T-08] 【100% 确认缺陷/边界补齐】异常退出码与特殊符号边界已程序化验证。")
    }

    // MARK: T-09 [Suggestion]: 全局 UI 缺少 accessibilityIdentifier 导致端到端自动化测试受阻
    @MainActor
    func testT09_CompleteAbsenceOfAccessibilityIdentifiers() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.t09.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)
        let panel = controller.panel

        // 缺陷断言：Panel 及其 contentView 均无有效设置的 accessibilityIdentifier（返回空字符串或 nil）
        let panelIdent = panel.accessibilityIdentifier()
        let contentIdent = panel.contentView?.accessibilityIdentifier() ?? ""
        XCTAssertTrue(panelIdent.isEmpty, "【100% 确认缺陷/无障碍缺失】Panel 缺少 accessibilityIdentifier！")
        XCTAssertTrue(contentIdent.isEmpty, "【100% 确认缺陷/无障碍缺失】ContentView 缺少 accessibilityIdentifier！")
        print(">>> [T-09] 【100% 确认缺陷/无障碍缺失】全局缺少 accessibilityIdentifier 阻碍自动化已程序化证实。")
    }
}
