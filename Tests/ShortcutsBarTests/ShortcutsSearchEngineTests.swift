import XCTest
@testable import ShortcutsBarCore

final class ShortcutsSearchEngineTests: XCTestCase {
    func testRealShortcutsServiceData() async throws {
        let service = ShortcutsService()
        _ = try await service.refreshCache()
        let vm = await FloatingPanelViewModel(shortcutsService: service, processManager: ProcessManager())
        await MainActor.run {
            vm.refreshData()
            vm.searchQuery = "pdf"
            if !vm.visibleItems.isEmpty {
                XCTAssertTrue(vm.visibleItems.allSatisfy { $0.item.name.lowercased().contains("pdf") })
                XCTAssertFalse(vm.visibleItems.contains(where: { $0.item.name == "图库壁纸" }))
            }
        }
    }
    func testPinyinRepresentations() {
        let (full, initials) = ShortcutsSearchEngine.pinyinRepresentations(for: "工作流空间")
        XCTAssertEqual(full, "gongzuoliukongjian")
        XCTAssertEqual(initials, "gzlkj")

        let (emptyFull, emptyInitials) = ShortcutsSearchEngine.pinyinRepresentations(for: "")
        XCTAssertEqual(emptyFull, "")
        XCTAssertEqual(emptyInitials, "")
    }

    func testMatchScore() {
        let engine = ShortcutsSearchEngine()
        XCTAssertEqual(engine.matchScore(query: "pdf", targetName: "图库壁纸"), 0)
        XCTAssertEqual(engine.matchScore(query: "pdf", targetName: "pdf保存到相册"), 90)

        // Empty query matches everything
        XCTAssertEqual(engine.matchScore(query: "", targetName: "任意名称"), 100)

        // Exact match
        XCTAssertEqual(engine.matchScore(query: "Backup", targetName: "Backup"), 100)

        // Prefix match
        XCTAssertEqual(engine.matchScore(query: "Back", targetName: "Backup Work"), 90)

        // Substring match
        XCTAssertEqual(engine.matchScore(query: "kup", targetName: "Backup"), 75)

        // Chinese Pinyin initials match
        XCTAssertTrue(engine.matchScore(query: "gzl", targetName: "打开工作流") > 0)

        // Chinese full Pinyin match
        XCTAssertTrue(engine.matchScore(query: "gongzuo", targetName: "打开工作流") > 0)

        // Non-match
        XCTAssertEqual(engine.matchScore(query: "xyz", targetName: "整理下载目录"), 0)
    }

    func testProjectionFolderFilteringAndKeyEquivalents() {
        let engine = ShortcutsSearchEngine()

        let folderA = ShortcutsFolder(name: "办公", shortcuts: [
            ShortcutItem(name: "整理下载", folderName: "办公"),
            ShortcutItem(name: "发送邮件", folderName: "办公")
        ])
        let folderB = ShortcutsFolder(name: "开发", shortcuts: [
            ShortcutItem(name: "构建项目", folderName: "开发"),
            ShortcutItem(name: "运行测试", folderName: "开发")
        ])

        // Filter by folder "办公"
        let projected = engine.project(
            allFolders: [folderA, folderB],
            selectedFolder: "办公",
            searchQuery: ""
        )
        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected[0].id, "整理下载")
        XCTAssertEqual(projected[0].inPanelShortcut, "⌘1")
        XCTAssertEqual(projected[1].id, "发送邮件")
        XCTAssertEqual(projected[1].inPanelShortcut, "⌘2")

        // Filter "全部"
        let allProjected = engine.project(
            allFolders: [folderA, folderB],
            selectedFolder: "全部",
            searchQuery: ""
        )
        XCTAssertEqual(allProjected.count, 4)
        XCTAssertEqual(allProjected[0].inPanelShortcut, "⌘1")
        XCTAssertEqual(allProjected[3].inPanelShortcut, "⌘4")
    }

    func testProjectionCustomSortOrder() {
        let engine = ShortcutsSearchEngine()
        let items = (1...12).map { ShortcutItem(name: "Item \($0)", folderName: "Default") }
        let folder = ShortcutsFolder(name: "Default", shortcuts: items)

        // Custom order placing Item 5 and Item 10 at top
        let customOrder = ["Item 10", "Item 5"]
        let projected = engine.project(
            allFolders: [folder],
            selectedFolder: "Default",
            searchQuery: "",
            customSortOrders: ["Default": customOrder]
        )

        XCTAssertEqual(projected[0].id, "Item 10")
        XCTAssertEqual(projected[0].inPanelShortcut, "⌘1")
        XCTAssertEqual(projected[1].id, "Item 5")
        XCTAssertEqual(projected[1].inPanelShortcut, "⌘2")

        // Verify top 9 receive ⌘1~⌘9, and 10th+ receive nil
        XCTAssertEqual(projected[8].inPanelShortcut, "⌘9")
        XCTAssertNil(projected[9].inPanelShortcut)
        XCTAssertNil(projected[10].inPanelShortcut)
        XCTAssertNil(projected[11].inPanelShortcut)
    }

    func testProjectionGlobalSearchAcrossAllFolders() {
        let engine = ShortcutsSearchEngine()
        let folder1 = ShortcutsFolder(name: "Alpha", shortcuts: [
            ShortcutItem(name: "代码格式化", folderName: "Alpha")
        ])
        let folder2 = ShortcutsFolder(name: "Beta", shortcuts: [
            ShortcutItem(name: "格式化日志", folderName: "Beta"),
            ShortcutItem(name: "备份数据库", folderName: "Beta")
        ])

        // Even if selectedFolder is "Alpha", search query "格式化" searches GLOBALLY
        let results = engine.project(
            allFolders: [folder1, folder2],
            selectedFolder: "Alpha",
            searchQuery: "格式化"
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].inPanelShortcut, "⌘1")
        XCTAssertEqual(results[1].inPanelShortcut, "⌘2")
    }
}
