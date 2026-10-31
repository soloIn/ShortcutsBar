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
    public static let taskQueueChangedNotification = Notification.Name("ProcessManager.taskQueueChanged")
    public static let taskCompletedNotification = Notification.Name("ProcessManager.taskCompleted")

    public struct ActiveTaskItem: Sendable {
        public var task: RunningTask
        public var cancel: @Sendable () -> Void
        public var isCancelled: Bool
        public var isSpawnCompleted: Bool
        public var pendingExit: (status: Int32, wasCancelled: Bool)?

        public init(
            task: RunningTask,
            cancel: @escaping @Sendable () -> Void,
            isCancelled: Bool = false,
            isSpawnCompleted: Bool = false,
            pendingExit: (status: Int32, wasCancelled: Bool)? = nil
        ) {
            self.task = task
            self.cancel = cancel
            self.isCancelled = isCancelled
            self.isSpawnCompleted = isSpawnCompleted
            self.pendingExit = pendingExit
        }
    }

    private let spawner: ProcessSpawning
    private let lock = NSLock()
    private var tasks: [UUID: ActiveTaskItem] = [:]

    private var queueObservers: [UUID: @Sendable ([RunningTask]) -> Void] = [:]
    private var taskCompletedObservers: [UUID: @Sendable (RunningTask, Bool) -> Void] = [:]
    private var legacyQueueObserverId: UUID?
    private var legacyTaskCompletedObserverId: UUID?

    @discardableResult
    public func addQueueObserver(_ observer: @escaping @Sendable ([RunningTask]) -> Void) -> UUID {
        let id = UUID()
        lock.withLock {
            queueObservers[id] = observer
        }
        return id
    }

    public func removeQueueObserver(_ id: UUID) {
        lock.withLock {
            _ = queueObservers.removeValue(forKey: id)
        }
    }

    @discardableResult
    public func addTaskCompletedObserver(_ observer: @escaping @Sendable (RunningTask, Bool) -> Void) -> UUID {
        let id = UUID()
        lock.withLock {
            taskCompletedObservers[id] = observer
        }
        return id
    }

    public func removeTaskCompletedObserver(_ id: UUID) {
        lock.withLock {
            _ = taskCompletedObservers.removeValue(forKey: id)
        }
    }

    public var onQueueChanged: (@Sendable ([RunningTask]) -> Void)? {
        get { nil }
        set {
            lock.withLock {
                if let oldId = legacyQueueObserverId {
                    queueObservers.removeValue(forKey: oldId)
                    legacyQueueObserverId = nil
                }
                if let closure = newValue {
                    let id = UUID()
                    queueObservers[id] = closure
                    legacyQueueObserverId = id
                }
            }
        }
    }

    public var onTaskCompleted: (@Sendable (RunningTask, Bool) -> Void)? {
        get { nil }
        set {
            lock.withLock {
                if let oldId = legacyTaskCompletedObserverId {
                    taskCompletedObservers.removeValue(forKey: oldId)
                    legacyTaskCompletedObserverId = nil
                }
                if let closure = newValue {
                    let id = UUID()
                    taskCompletedObservers[id] = closure
                    legacyTaskCompletedObserverId = id
                }
            }
        }
    }

    public init(spawner: ProcessSpawning = DefaultProcessSpawner()) {
        self.spawner = spawner
    }

    public var activeTasks: [RunningTask] {
        lock.withLock {
            tasks.values.filter { !$0.isCancelled }.map { $0.task }.sorted { $0.startTime < $1.startTime }
        }
    }

    public var activeTaskCount: Int {
        lock.withLock { tasks.values.filter { !$0.isCancelled }.count }
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
        let placeholderItem = ActiveTaskItem(
            task: initialTask,
            cancel: {},
            isCancelled: false,
            isSpawnCompleted: false
        )
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

        var shouldCancelSpawned = false
        var instantExitAction: (@Sendable () -> Void)? = nil

        lock.withLock {
            if var existing = tasks[taskId] {
                existing.task.pid = handle.pid
                existing.cancel = handle.cancel
                existing.isSpawnCompleted = true

                if let pending = existing.pendingExit {
                    // Process exited during spawn! Remove and prepare completion action now with real PID & cancel!
                    tasks.removeValue(forKey: taskId)
                    instantExitAction = self.buildCompletionAction(for: existing, status: pending.status, wasCancelled: pending.wasCancelled)
                } else if existing.isCancelled {
                    shouldCancelSpawned = true
                    tasks[taskId] = existing
                } else {
                    tasks[taskId] = existing
                }
            }
        }

        if shouldCancelSpawned {
            handle.cancel()
        }

        if let exitAction = instantExitAction {
            if Thread.isMainThread {
                exitAction()
            } else {
                DispatchQueue.main.async(execute: exitAction)
            }
        } else {
            notifyQueueChanged()
        }
        return taskId
    }

    public func terminate(taskId: UUID) {
        let cancelToCall: (@Sendable () -> Void)? = lock.withLock {
            if var item = tasks[taskId] {
                item.isCancelled = true
                tasks[taskId] = item
                return item.cancel
            }
            return nil
        }
        cancelToCall?()
        let stillInTasks = lock.withLock { tasks[taskId] != nil }
        if stillInTasks {
            notifyQueueChanged()
        }
    }

    public func terminateAll() {
        let items: [ActiveTaskItem] = lock.withLock {
            var allItems: [ActiveTaskItem] = []
            for (id, var item) in tasks {
                item.isCancelled = true
                tasks[id] = item
                allItems.append(item)
            }
            return allItems
        }
        for item in items {
            item.cancel()
        }
        let anyRemaining = lock.withLock { !tasks.isEmpty }
        if anyRemaining {
            notifyQueueChanged()
        }
    }

    private func handleProcessTermination(taskId: UUID, status: Int32, wasCancelled: Bool) {
        let actionToDispatch: (@Sendable () -> Void)? = lock.withLock {
            guard var item = tasks[taskId] else { return nil }
            if !item.isSpawnCompleted {
                // If spawn hasn't returned yet, record the exit status and let launch() finish dispatching!
                item.pendingExit = (status, wasCancelled)
                tasks[taskId] = item
                return nil
            }
            tasks.removeValue(forKey: taskId)
            return buildCompletionAction(for: item, status: status, wasCancelled: wasCancelled)
        }
        if let action = actionToDispatch {
            if Thread.isMainThread {
                action()
            } else {
                DispatchQueue.main.async(execute: action)
            }
        }
    }

    private func buildCompletionAction(for item: ActiveTaskItem, status: Int32, wasCancelled: Bool) -> (@Sendable () -> Void) {
        let userCancelled = item.isCancelled
        let effectiveCancelled = wasCancelled || userCancelled
        let success = (status == 0 && !effectiveCancelled)

        var finishedTask = item.task
        if !success {
            if userCancelled {
                finishedTask.errorMessage = "用户主动终止"
            } else if wasCancelled {
                finishedTask.errorMessage = "快捷指令异常终止 (信号退出)"
            } else {
                finishedTask.errorMessage = "shortcuts CLI 退出代码: \(status)"
            }
        }
        let taskToSend = finishedTask

        return { [weak self] in
            guard let self = self else { return }
            self.notifyQueueChanged()

            let completionCallbacks: [@Sendable (RunningTask, Bool) -> Void] = self.lock.withLock {
                Array(self.taskCompletedObservers.values)
            }
            for callback in completionCallbacks {
                callback(taskToSend, success)
            }

            NotificationCenter.default.post(
                name: Self.taskCompletedNotification,
                object: self,
                userInfo: [
                    "task": taskToSend,
                    "success": success
                ]
            )
        }
    }

    private func notifyQueueChanged() {
        let dispatchNotification: @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }
            let currentTasks = self.activeTasks
            let queueCallbacks: [@Sendable ([RunningTask]) -> Void] = self.lock.withLock {
                Array(self.queueObservers.values)
            }
            for callback in queueCallbacks {
                callback(currentTasks)
            }

            NotificationCenter.default.post(
                name: Self.taskQueueChangedNotification,
                object: self,
                userInfo: [
                    "tasks": currentTasks
                ]
            )
        }

        if Thread.isMainThread {
            dispatchNotification()
        } else {
            DispatchQueue.main.async(execute: dispatchNotification)
        }
    }
}
