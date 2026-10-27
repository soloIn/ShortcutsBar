import Foundation

public protocol ProcessSpawning: Sendable {
    func spawn(
        shortcutName: String,
        onTermination: @escaping @Sendable (Int32, Bool) -> Void
    ) throws -> (pid: pid_t, cancel: @Sendable () -> Void)
}

public struct DefaultProcessSpawner: ProcessSpawning {
    public init() {}

    public func spawn(
        shortcutName: String,
        onTermination: @escaping @Sendable (Int32, Bool) -> Void
    ) throws -> (pid: pid_t, cancel: @Sendable () -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        // Use "--" delimiter to prevent shortcut names starting with '-' from being parsed as CLI options
        process.arguments = ["run", "--", shortcutName]

        // Redirect stdout and stderr to nullDevice to eliminate 64KB kernel pipe buffer deadlocks
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { proc in
            let status = proc.terminationStatus
            let wasTerminated = (proc.terminationReason == .uncaughtSignal)
            onTermination(status, wasTerminated)
        }

        try process.run()
        let pid = process.processIdentifier

        let cancelHandler: @Sendable () -> Void = { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }

        return (pid, cancelHandler)
    }
}

public final class ProcessManager: @unchecked Sendable {
    public struct ActiveTaskItem: Sendable {
        public let task: RunningTask
        public let cancel: @Sendable () -> Void

        public init(task: RunningTask, cancel: @escaping @Sendable () -> Void) {
            self.task = task
            self.cancel = cancel
        }
    }

    private let spawner: ProcessSpawning
    private let lock = NSLock()
    private var tasks: [UUID: ActiveTaskItem] = [:]

    private var _onQueueChanged: (@Sendable ([RunningTask]) -> Void)?
    private var _onTaskCompleted: (@Sendable (RunningTask, Bool) -> Void)?

    public var onQueueChanged: (@Sendable ([RunningTask]) -> Void)? {
        get { lock.withLock { _onQueueChanged } }
        set { lock.withLock { _onQueueChanged = newValue } }
    }

    public var onTaskCompleted: (@Sendable (RunningTask, Bool) -> Void)? {
        get { lock.withLock { _onTaskCompleted } }
        set { lock.withLock { _onTaskCompleted = newValue } }
    }

    public init(spawner: ProcessSpawning = DefaultProcessSpawner()) {
        self.spawner = spawner
    }

    public var activeTasks: [RunningTask] {
        lock.withLock {
            tasks.values.map { $0.task }.sorted { $0.startTime < $1.startTime }
        }
    }

    public var activeTaskCount: Int {
        lock.withLock { tasks.count }
    }

    @discardableResult
    public func launch(shortcutName: String, actionCount: Int = 0) throws -> UUID {
        let taskId = UUID()
        let startTime = Date()
        let initialTask = RunningTask(
            id: taskId,
            shortcutName: shortcutName,
            startTime: startTime,
            actionCount: actionCount
        )

        // Pre-register placeholder item in tasks under lock before spawning.
        // This eliminates the premature process termination race condition where
        // a near-instant process exit triggers terminationHandler before the task is recorded.
        let placeholderItem = ActiveTaskItem(task: initialTask, cancel: {})
        lock.withLock {
            tasks[taskId] = placeholderItem
        }

        let handle: (pid: pid_t, cancel: @Sendable () -> Void)
        do {
            handle = try spawner.spawn(shortcutName: shortcutName) { [weak self] status, wasTerminated in
                self?.handleProcessTermination(taskId: taskId, status: status, wasCancelled: wasTerminated)
            }
        } catch {
            lock.withLock {
                _ = tasks.removeValue(forKey: taskId)
            }
            throw error
        }

        lock.withLock {
            // Only update if not already terminated and removed by handleProcessTermination
            if tasks[taskId] != nil {
                var updatedTask = initialTask
                updatedTask.pid = handle.pid
                tasks[taskId] = ActiveTaskItem(task: updatedTask, cancel: handle.cancel)
            }
        }

        notifyQueueChanged()
        return taskId
    }

    public func terminate(taskId: UUID) {
        let itemToCancel: ActiveTaskItem? = lock.withLock {
            return tasks[taskId]
        }
        itemToCancel?.cancel()
    }

    public func terminateAll() {
        let items: [ActiveTaskItem] = lock.withLock {
            return Array(tasks.values)
        }
        for item in items {
            item.cancel()
        }
    }

    private func handleProcessTermination(taskId: UUID, status: Int32, wasCancelled: Bool) {
        let removedItem: ActiveTaskItem? = lock.withLock {
            return tasks.removeValue(forKey: taskId)
        }

        guard let item = removedItem else { return }
        let success = (status == 0 && !wasCancelled)

        notifyQueueChanged()

        let completionCallback = lock.withLock { _onTaskCompleted }
        completionCallback?(item.task, success)
    }

    private func notifyQueueChanged() {
        let currentTasks = activeTasks
        let queueCallback = lock.withLock { _onQueueChanged }
        queueCallback?(currentTasks)
    }
}
