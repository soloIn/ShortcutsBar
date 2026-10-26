import XCTest
@testable import ShortcutsBarCore

final class MockShortcutsCLIExecutor: ShortcutsCLIExecuting, @unchecked Sendable {
    var responses: [String: String] = [:]

    func execute(arguments: [String]) async throws -> String {
        let key = arguments.joined(separator: " ")
        if let response = responses[key] {
            return response
        }
        throw NSError(domain: "MockError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No mock for '\(key)'"])
    }
}

final class ShortcutsServiceTests: XCTestCase {
    func testRefreshCacheAndQuery() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Mac\niPhone\nMenu Bar"
        mock.responses["list --folder-name Mac"] = "Compress Video\nCopy File Name"
        mock.responses["list --folder-name iPhone"] = "Take GIF"
        mock.responses["list --folder-name Menu Bar"] = "Clean Clipboard\nQuick OCR"
        mock.responses["list --folder-name none"] = "Unfiled 1"

        let service = ShortcutsService(executor: mock)
        let folders = try await service.refreshCache()

        XCTAssertEqual(folders.count, 3)
        XCTAssertEqual(service.cachedFolders.count, 3)
        XCTAssertEqual(service.unfiledShortcuts.count, 1)

        // Query leaf folder "Menu Bar"
        let menuBarItems = service.getShortcuts(for: .leaf(folderName: "Menu Bar"))
        XCTAssertEqual(menuBarItems.count, 2)
        XCTAssertEqual(menuBarItems[0].name, "Clean Clipboard")
        XCTAssertEqual(menuBarItems[1].name, "Quick OCR")

        // Query leaf folder "Mac"
        let macItems = service.getShortcuts(for: .leaf(folderName: "Mac"))
        XCTAssertEqual(macItems.count, 2)
        XCTAssertEqual(macItems[0].name, "Compress Video")

        // Query root
        let rootItems = service.getShortcuts(for: .root)
        XCTAssertEqual(rootItems.count, 6) // 1 unfiled + 2 + 1 + 2
    }

    func testEmptyFolderHandling() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "EmptyFolder"
        mock.responses["list --folder-name EmptyFolder"] = ""
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        let folders = try await service.refreshCache()

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].shortcuts.count, 0)
        let items = service.getShortcuts(for: .leaf(folderName: "EmptyFolder"))
        XCTAssertTrue(items.isEmpty)
    }
}
