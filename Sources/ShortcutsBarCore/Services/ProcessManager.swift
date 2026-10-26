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
        process.arguments = ["run", shortcutName]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

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
    public struct ActiveTaskItem: @unchecked Sendable {
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

    public var onQueueChanged: (@Sendable ([RunningTask]) -> Void)?
    public var onTaskCompleted: (@Sendable (RunningTask, Bool) -> Void)?

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
    public func launch(shortcutName: String) throws -> UUID {
        let taskId = UUID()
        var runningTask = RunningTask(id: taskId, shortcutName: shortcutName, startTime: Date())

        let handle = try spawner.spawn(shortcutName: shortcutName) { [weak self] status, wasTerminated in
            self?.handleProcessTermination(taskId: taskId, status: status, wasCancelled: wasTerminated)
        }

        runningTask.pid = handle.pid
        let activeItem = ActiveTaskItem(task: runningTask, cancel: handle.cancel)

        lock.withLock {
            tasks[taskId] = activeItem
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
        onTaskCompleted?(item.task, success)
    }

    private func notifyQueueChanged() {
        let currentTasks = activeTasks
        onQueueChanged?(currentTasks)
    }
}
