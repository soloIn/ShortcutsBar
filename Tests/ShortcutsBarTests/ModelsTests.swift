import XCTest
@testable import ShortcutsBarCore

final class ModelsTests: XCTestCase {
    func testShortcutItemCreation() {
        let item = ShortcutItem(name: "Clean Clipboard", folderName: "Menu Bar")
        XCTAssertEqual(item.name, "Clean Clipboard")
        XCTAssertEqual(item.folderName, "Menu Bar")
        XCTAssertEqual(item.id, "Clean Clipboard")
    }

    func testShortcutsFolderCreation() {
        let item = ShortcutItem(name: "Test")
        let folder = ShortcutsFolder(name: "Work", shortcuts: [item])
        XCTAssertEqual(folder.name, "Work")
        XCTAssertEqual(folder.shortcuts.count, 1)
        XCTAssertEqual(folder.shortcuts[0].name, "Test")
    }

    func testRunningTask() {
        let task = RunningTask(shortcutName: "Batch Convert")
        XCTAssertEqual(task.shortcutName, "Batch Convert")
        XCTAssertNotNil(task.id)
    }

    func testFolderScope() {
        let root = FolderScope.root
        XCTAssertNil(root.folderName)
        XCTAssertTrue(root.displayName.contains("层级"))

        let leaf = FolderScope.leaf(folderName: "Mac")
        XCTAssertEqual(leaf.folderName, "Mac")
        XCTAssertTrue(leaf.displayName.contains("Mac"))
    }
}
