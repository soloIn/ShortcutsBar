import XCTest
import Foundation
@testable import ShortcutsBarCore

final class ShortcutsDatabaseWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("watcher_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testWalFileModificationTriggersDatabaseChanged() throws {
        // Pre-create database files in temp directory
        let walFile = tempDir.appendingPathComponent("Shortcuts.sqlite-wal")
        let dbFile = tempDir.appendingPathComponent("Shortcuts.sqlite")
        try "initial db".write(to: dbFile, atomically: true, encoding: .utf8)
        try "initial wal".write(to: walFile, atomically: true, encoding: .utf8)

        let watcher = ShortcutsDatabaseWatcher(directoryPath: tempDir.path)

        let expectation = XCTestExpectation(description: "Database changed triggered on WAL append")

        watcher.onDatabaseChanged = {
            expectation.fulfill()
        }

        watcher.startWatching()

        // Give FSEventStream / watcher brief moment to initialize
        Thread.sleep(forTimeInterval: 0.15)

        // Modify the WAL file by appending content (mimics siriactionsd writing WAL frame)
        let handle = try FileHandle(forWritingTo: walFile)
        handle.seekToEndOfFile()
        handle.write(Data("new transaction frame\n".utf8))
        handle.closeFile()

        // Wait for debounced callback
        wait(for: [expectation], timeout: 2.0)

        watcher.stopWatching()
    }

    func testStopWatchingPreventsSubsequentEvents() throws {
        let walFile = tempDir.appendingPathComponent("Shortcuts.sqlite-wal")
        try "initial wal".write(to: walFile, atomically: true, encoding: .utf8)

        let watcher = ShortcutsDatabaseWatcher(directoryPath: tempDir.path)

        final class SafeCounter: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func increment() {
                lock.withLock { count += 1 }
            }
            var value: Int {
                lock.withLock { count }
            }
        }
        let counter = SafeCounter()

        watcher.onDatabaseChanged = {
            counter.increment()
        }

        watcher.startWatching()
        Thread.sleep(forTimeInterval: 0.1)
        watcher.stopWatching()

        // Modify after stopping
        let handle = try FileHandle(forWritingTo: walFile)
        handle.seekToEndOfFile()
        handle.write(Data("after stop write\n".utf8))
        handle.closeFile()

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(counter.value, 0, "Callback should not be invoked after stopWatching")
    }
}
