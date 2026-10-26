import XCTest
import AppKit
@testable import ShortcutsBarCore

final class OptimizationFeaturesTests: XCTestCase {
    // 1. Test ShortcutIconRenderer
    func testShortcutIconRendererProducesValidImages() {
        let renderer = ShortcutIconRenderer.shared

        // Item with full glyph and color
        let itemWithIcon = ShortcutItem(
            name: "Test Shortcut",
            folderName: "Work",
            glyph: 59520,
            colorValue: 946986751,
            actionCount: 18
        )
        let icon1 = renderer.icon(for: itemWithIcon, size: 16)
        XCTAssertNotNil(icon1)
        XCTAssertEqual(icon1.size.width, 16)
        XCTAssertEqual(icon1.size.height, 16)

        // Item with color only (fallback squircle)
        let itemWithColor = ShortcutItem(
            name: "Color Only",
            folderName: nil,
            glyph: nil,
            colorValue: 1440408063,
            actionCount: 2
        )
        let icon2 = renderer.icon(for: itemWithColor, size: 16)
        XCTAssertNotNil(icon2)
        XCTAssertEqual(icon2.size.width, 16)
        XCTAssertEqual(icon2.size.height, 16)

        // Default item (fallback command symbol)
        let defaultItem = ShortcutItem(
            name: "Default Shortcut"
        )
        let icon3 = renderer.icon(for: defaultItem, size: 16)
        XCTAssertNotNil(icon3)
        XCTAssertEqual(icon3.size.width, 16)
        XCTAssertEqual(icon3.size.height, 16)
    }

    // 2. Test ShortcutsIconFactory
    func testShortcutsIconFactoryGeometry() {
        let menuBarIcon = ShortcutsIconFactory.createMenuBarIcon(size: 18)
        XCTAssertNotNil(menuBarIcon)
        XCTAssertTrue(menuBarIcon.isTemplate)
        XCTAssertEqual(menuBarIcon.size.width, 18)
        XCTAssertEqual(menuBarIcon.size.height, 18)

        let runningIcon = ShortcutsIconFactory.createRunningShortcutsIcon(size: 18)
        XCTAssertNotNil(runningIcon)
        XCTAssertFalse(runningIcon.isTemplate)
        XCTAssertEqual(runningIcon.size.width, 18)
        XCTAssertEqual(runningIcon.size.height, 18)

        let appIcon = ShortcutsIconFactory.createAppIcon(size: 512)
        XCTAssertNotNil(appIcon)
        XCTAssertEqual(appIcon.size.width, 512)
        XCTAssertEqual(appIcon.size.height, 512)
    }

    // 3. Test ShortcutsMetadataReader with safe fallback
    func testShortcutsMetadataReaderSafety() {
        // Non-existent path returns empty dict safely without crashing
        let dummyReader = ShortcutsMetadataReader(dbPath: "/tmp/non_existent_shortcuts_test.sqlite")
        let metadata = dummyReader.fetchAllMetadata()
        XCTAssertTrue(metadata.isEmpty)

        // Default reader reads from user directory without throwing
        let defaultReader = ShortcutsMetadataReader.shared
        let realMetadata = defaultReader.fetchAllMetadata()
        // If the user has shortcuts in macOS, this will contain them safely
        XCTAssertNotNil(realMetadata)
    }

    // 4. Test ShortcutsDatabaseWatcher freshness timestamp check
    func testShortcutsDatabaseWatcherFreshness() {
        let watcher = ShortcutsDatabaseWatcher.shared
        // In the distant past, database has definitely changed
        let pastDate = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(watcher.hasChanged(since: pastDate))

        // In the distant future, database has not changed
        let futureDate = Date(timeIntervalSinceNow: 3600 * 24 * 365)
        XCTAssertFalse(watcher.hasChanged(since: futureDate))
    }

    // 5. Test RunningTask and RunningTaskView progress tracking
    @MainActor
    func testRunningTaskProgressModel() throws {
        let startTime = Date().addingTimeInterval(-15) // Started 15s ago
        let task = RunningTask(
            shortcutName: "Batch Resize Photos",
            startTime: startTime,
            actionCount: 42
        )

        XCTAssertEqual(task.shortcutName, "Batch Resize Photos")
        XCTAssertEqual(task.actionCount, 42)
        XCTAssertEqual(task.startTime, startTime)

        var stoppedId: UUID?
        let taskView = RunningTaskView(
            taskId: task.id,
            taskName: task.shortcutName,
            startTime: task.startTime,
            actionCount: task.actionCount,
            onStop: { id in
                stoppedId = id
            }
        )

        XCTAssertNil(stoppedId)
        XCTAssertNotNil(taskView)
        XCTAssertEqual(taskView.frame.height, 36)
    }
}
