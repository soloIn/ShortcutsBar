import XCTest
@testable import ShortcutsBarCore

final class SafeIntegrationTests: XCTestCase {
    private var initialShortcuts: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        // Record baseline shortcuts
        initialShortcuts = try getLiveShortcutsList()
    }

    override func tearDown() async throws {
        // Assert non-destructive invariant: existing library MUST be 100% identical
        let currentShortcuts = try getLiveShortcutsList()
        XCTAssertEqual(
            initialShortcuts,
            currentShortcuts,
            "CRITICAL VIOLATION: Existing shortcuts library was modified or polluted during test execution!"
        )
        try await super.tearDown()
    }

    func testLiveShortcutsIntrospectionIsNonDestructive() async throws {
        let service = ShortcutsService()
        let folders = try await service.refreshCache()

        // Service successfully inspects folders and cached shortcuts
        XCTAssertGreaterThanOrEqual(folders.count, 0)
        let allItems = service.allShortcuts
        XCTAssertGreaterThanOrEqual(allItems.count, 0)

        // Verify folder scope filtering logic with live data
        let rootItems = service.getShortcuts(for: .root)
        XCTAssertEqual(rootItems.count, allItems.count)
    }

    func testSafeProcessLifecycleSimulation() throws {
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        // Create tasks with safe test identifiers (never touching live shortcuts)
        let safeTestName = "ShortcutsBarTest_\(UUID().uuidString.prefix(8))"
        let taskId = try manager.launch(shortcutName: safeTestName)

        XCTAssertEqual(manager.activeTaskCount, 1)
        XCTAssertEqual(manager.activeTasks.first?.shortcutName, safeTestName)

        // Cancel test task
        manager.terminate(taskId: taskId)
        XCTAssertEqual(manager.activeTaskCount, 0)
    }

    private func getLiveShortcutsList() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
