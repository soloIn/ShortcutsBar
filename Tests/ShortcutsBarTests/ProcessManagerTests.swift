import XCTest
@testable import ShortcutsBarCore

final class MockProcessSpawner: ProcessSpawning, @unchecked Sendable {
    struct SpawnRecord {
        let name: String
        let onTermination: @Sendable (Int32, Bool) -> Void
    }

    private let lock = NSLock()
    private var spawned: [pid_t: SpawnRecord] = [:]
    private var nextPid: pid_t = 1000

    func spawn(
        shortcutName: String,
        onTermination: @escaping @Sendable (Int32, Bool) -> Void
    ) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
        lock.withLock {
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

final class ProcessManagerTests: XCTestCase {
    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T

        init(_ value: T) {
            self._value = value
        }

        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }

        func modify(_ block: (inout T) -> Void) {
            lock.withLock { block(&_value) }
        }
    }

    func testConcurrentTaskTracking() throws {
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        XCTAssertEqual(manager.activeTaskCount, 0)

        let task1 = try manager.launch(shortcutName: "Task 1")
        let task2 = try manager.launch(shortcutName: "Task 2")
        let task3 = try manager.launch(shortcutName: "Task 3")

        XCTAssertEqual(manager.activeTaskCount, 3)
        let active = manager.activeTasks
        XCTAssertEqual(active.map { $0.shortcutName }, ["Task 1", "Task 2", "Task 3"])

        // Terminate task 2
        manager.terminate(taskId: task2)
        XCTAssertEqual(manager.activeTaskCount, 2)
        XCTAssertEqual(manager.activeTasks.map { $0.id }, [task1, task3])

        // Complete remaining tasks
        for pid in spawner.activePids {
            spawner.simulateTermination(pid: pid, status: 0)
        }

        XCTAssertEqual(manager.activeTaskCount, 0)
    }

    func testTerminateAll() throws {
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        _ = try manager.launch(shortcutName: "A")
        _ = try manager.launch(shortcutName: "B")
        _ = try manager.launch(shortcutName: "C")
        _ = try manager.launch(shortcutName: "D")

        XCTAssertEqual(manager.activeTaskCount, 4)
        manager.terminateAll()
        XCTAssertEqual(manager.activeTaskCount, 0)
    }

    func testQueueChangedCallback() throws {
        let spawner = MockProcessSpawner()
        let manager = ProcessManager(spawner: spawner)

        let queueCounts = Box<[Int]>([])
        manager.onQueueChanged = { tasks in
            queueCounts.modify { $0.append(tasks.count) }
        }

        let t1 = try manager.launch(shortcutName: "Job")
        XCTAssertEqual(queueCounts.value, [1])

        manager.terminate(taskId: t1)
        XCTAssertEqual(queueCounts.value, [1, 0])
    }
}
