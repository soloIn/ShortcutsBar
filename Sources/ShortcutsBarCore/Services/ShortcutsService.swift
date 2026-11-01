import Foundation

public protocol ShortcutsCLIExecuting: Sendable {
    func execute(arguments: [String]) async throws -> String
}

public struct DefaultShortcutsCLIExecutor: ShortcutsCLIExecuting {
    public init() {}

    public func execute(arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try Task.checkCancellation()

        final class ProcessState: @unchecked Sendable {
            let lock = NSLock()
            var isCancelled = false
            var isRunning = false
        }
        let state = ProcessState()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let shouldRun: Bool = state.lock.withLock {
                        if state.isCancelled {
                            return false
                        }
                        return true
                    }
                    guard shouldRun else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    do {
                        try process.run()
                        state.lock.withLock {
                            state.isRunning = true
                            if state.isCancelled {
                                process.terminate()
                            }
                        }

                        // Concurrently read stdout and stderr to prevent 64KB kernel pipe buffer deadlock
                        final class DataBox: @unchecked Sendable {
                            var data = Data()
                        }
                        let outBox = DataBox()
                        let errBox = DataBox()
                        let group = DispatchGroup()

                        group.enter()
                        DispatchQueue.global().async {
                            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }

                        group.enter()
                        DispatchQueue.global().async {
                            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }

                        process.waitUntilExit()
                        group.wait()

                        try? outPipe.fileHandleForReading.close()
                        try? errPipe.fileHandleForReading.close()

                        let wasCancelled: Bool = state.lock.withLock { state.isCancelled }
                        if wasCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        let outData = outBox.data
                        let errData = errBox.data

                        if process.terminationStatus == 0 {
                            let output = String(data: outData, encoding: .utf8) ?? ""
                            continuation.resume(returning: output)
                        } else {
                            let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            continuation.resume(throwing: NSError(
                                domain: "ShortcutsCLI",
                                code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: "shortcuts CLI failed with code \(process.terminationStatus): \(errString)"]
                            ))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            state.lock.withLock {
                state.isCancelled = true
                if state.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

public final class ShortcutsService: @unchecked Sendable {
    public static let didUpdateCacheNotification = Notification.Name("ShortcutsService.didUpdateCacheNotification")
    public static let cacheUpdatedLegacyNotification = Notification.Name("ShortcutsServiceCacheUpdatedNotification")
    private let executor: ShortcutsCLIExecuting
    private let metadataReader: ShortcutsMetadataReader
    private let lock = NSLock()
    private var _cachedFolders: [ShortcutsFolder] = []
    private var _unfiledShortcuts: [ShortcutItem] = []
    private var _lastRefreshed: Date?
    private var inFlightRefreshTask: Task<[ShortcutsFolder], Error>?

    public init(
        executor: ShortcutsCLIExecuting = DefaultShortcutsCLIExecutor(),
        metadataReader: ShortcutsMetadataReader = .shared
    ) {
        self.executor = executor
        self.metadataReader = metadataReader
    }

    public var lastRefreshed: Date? {
        lock.withLock { _lastRefreshed }
    }

    public var cachedFolders: [ShortcutsFolder] {
        lock.withLock { _cachedFolders }
    }

    public var unfiledShortcuts: [ShortcutItem] {
        lock.withLock { _unfiledShortcuts }
    }

    public var allFoldersWithUnfiled: [ShortcutsFolder] {
        lock.withLock {
            var list = _cachedFolders
            if !_unfiledShortcuts.isEmpty {
                list.append(ShortcutsFolder(name: "未分类", shortcuts: _unfiledShortcuts))
            }
            return list
        }
    }

    public var allShortcuts: [ShortcutItem] {
        lock.withLock {
            var list = _unfiledShortcuts
            for folder in _cachedFolders {
                list.append(contentsOf: folder.shortcuts)
            }
            return list
        }
    }

    /// Refresh folder and shortcut data from CLI and enrich with SQLite metadata.
    /// In-flight concurrent refreshes are coalesced into a single execution to conserve resources.
    @discardableResult
    public func refreshCache() async throws -> [ShortcutsFolder] {
        let task = lock.withLock { () -> Task<[ShortcutsFolder], Error> in
            if let task = inFlightRefreshTask {
                return task
            }
            let task = Task<[ShortcutsFolder], Error> {
                defer {
                    self.lock.withLock {
                        self.inFlightRefreshTask = nil
                    }
                }
                return try await self.performRefresh()
            }
            self.inFlightRefreshTask = task
            return task
        }

        return try await task.value
    }

    private func executeOrEmpty(arguments: [String]) async throws -> String {
        do {
            return try await executor.execute(arguments: arguments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ""
        }
    }

    private enum FolderFetchResult: Sendable {
        case folder(name: String, names: [String])
        case unfiled(names: [String])
    }

    private func performRefresh() async throws -> [ShortcutsFolder] {
        try Task.checkCancellation()
        // 💡 记录事务开始时间，杜绝刷新耗时期间产生的 SQLite WAL 变更被漏读
        let refreshStartTime = Date()

        // 1. Fetch metadata dictionary from SQLite in read-only mode
        let metadataMap = metadataReader.fetchAllMetadata()

        // 2. Fetch master list of all shortcuts in library
        let allOutput = try await executeOrEmpty(arguments: ["list"])
        let allMasterNames = parseLines(allOutput)

        // 3. Fetch folders (gracefully fallback to empty list on error to preserve master shortcuts)
        let foldersOutput = try await executeOrEmpty(arguments: ["list", "--folders"])
        let folderNames = parseLines(foldersOutput)

        // 4. Fetch shortcuts for each folder and unfiled shortcuts concurrently using Swift structured concurrency
        var folderShortcutsMap: [String: [String]] = [:]
        var unfiledFromCli: [String] = []

        try await withThrowingTaskGroup(of: FolderFetchResult.self) { group in
            for folderName in folderNames {
                group.addTask {
                    try Task.checkCancellation()
                    let shortcutsOutput = try await self.executeOrEmpty(arguments: ["list", "--folder-name", folderName])
                    let names = self.parseLines(shortcutsOutput)
                    return .folder(name: folderName, names: names)
                }
            }

            // Also fetch unfiled shortcuts concurrently
            group.addTask {
                try Task.checkCancellation()
                let unfiledOutput = try await self.executeOrEmpty(arguments: ["list", "--folder-name", "none"])
                let names = self.parseLines(unfiledOutput)
                return .unfiled(names: names)
            }

            for try await result in group {
                switch result {
                case .folder(let name, let names):
                    folderShortcutsMap[name] = names
                case .unfiled(let names):
                    unfiledFromCli = names
                }
            }
        }

        // 5. Assemble folders strictly preserving original folderNames ordering
        var newFolders: [ShortcutsFolder] = []
        var assignedNames = Set<String>()

        for folderName in folderNames {
            let names = folderShortcutsMap[folderName] ?? []
            for name in names { assignedNames.insert(name) }
            let items = makeShortcutItems(names: names, folderName: folderName, metadata: metadataMap)
            newFolders.append(ShortcutsFolder(name: folderName, shortcuts: items))
        }

        // 6. Fetch unfiled shortcuts (both from unassigned in master list and unassigned folder)
        var unfiledNames = unfiledFromCli
        for masterName in allMasterNames {
            if !assignedNames.contains(masterName) && !unfiledNames.contains(masterName) {
                unfiledNames.append(masterName)
            }
        }
        let unfiledItems = makeShortcutItems(names: unfiledNames, folderName: "未分类", metadata: metadataMap)

        try Task.checkCancellation()

        // 💡 弹性缓存保护（Resilient Caching）：若抓取结果为空但已有老缓存，保留既有缓存，杜绝瞬时 CLI 异常清空全库
        let hasNewData = !newFolders.isEmpty || !unfiledItems.isEmpty
        lock.withLock {
            if hasNewData || (self._cachedFolders.isEmpty && self._unfiledShortcuts.isEmpty) {
                self._cachedFolders = newFolders
                self._unfiledShortcuts = unfiledItems
            }
            self._lastRefreshed = refreshStartTime
        }

        await MainActor.run { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(
                name: ShortcutsService.didUpdateCacheNotification,
                object: self
            )
            NotificationCenter.default.post(
                name: ShortcutsService.cacheUpdatedLegacyNotification,
                object: self
            )
        }

        return lock.withLock { self._cachedFolders }
    }

    /// Get items for a specific scope
    public func getShortcuts(for scope: FolderScope) -> [ShortcutItem] {
        lock.withLock {
            switch scope {
            case .root:
                var all = _unfiledShortcuts
                for folder in _cachedFolders {
                    all.append(contentsOf: folder.shortcuts)
                }
                return all
            case .leaf(let folderName):
                if let folder = _cachedFolders.first(where: { $0.name == folderName }) {
                    return folder.shortcuts
                }
                if folderName.lowercased() == "none" || folderName == "未分类" {
                    return _unfiledShortcuts
                }
                // Fallback: If designated leaf folder was deleted in Shortcuts, return all shortcuts as fallback
                var fallbackAll = _unfiledShortcuts
                for folder in _cachedFolders {
                    fallbackAll.append(contentsOf: folder.shortcuts)
                }
                return fallbackAll
            }
        }
    }

    private func makeShortcutItems(names: [String], folderName: String?, metadata: [String: ShortcutMetadata]) -> [ShortcutItem] {
        return names.map { name in
            let meta = metadata[name]
            return ShortcutItem(
                name: name,
                folderName: folderName,
                glyph: meta?.glyph,
                colorValue: meta?.colorValue,
                actionCount: meta?.actionCount ?? 0
            )
        }
    }

    private func parseLines(_ text: String) -> [String] {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
