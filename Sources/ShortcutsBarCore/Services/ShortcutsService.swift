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

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()

                        // Concurrently read stdout and stderr to prevent 64KB kernel pipe buffer deadlock
                        var outData = Data()
                        var errData = Data()
                        let group = DispatchGroup()

                        group.enter()
                        DispatchQueue.global().async {
                            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }

                        group.enter()
                        DispatchQueue.global().async {
                            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }

                        process.waitUntilExit()
                        group.wait()

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
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

public final class ShortcutsService: @unchecked Sendable {
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
        let existingTask: Task<[ShortcutsFolder], Error>? = lock.withLock {
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

        if let task = existingTask {
            return try await task.value
        }
        return try await performRefresh()
    }

    private func performRefresh() async throws -> [ShortcutsFolder] {
        // 1. Fetch metadata dictionary from SQLite in read-only mode
        let metadataMap = metadataReader.fetchAllMetadata()

        // 2. Fetch folders
        let foldersOutput = try await executor.execute(arguments: ["list", "--folders"])
        let folderNames = parseLines(foldersOutput)

        var newFolders: [ShortcutsFolder] = []

        // 3. Fetch shortcuts for each folder
        for folderName in folderNames {
            let shortcutsOutput = try? await executor.execute(arguments: ["list", "--folder-name", folderName])
            let names = parseLines(shortcutsOutput ?? "")
            let items = makeShortcutItems(names: names, folderName: folderName, metadata: metadataMap)
            newFolders.append(ShortcutsFolder(name: folderName, shortcuts: items))
        }

        // 4. Fetch unfiled shortcuts
        let unfiledOutput = try? await executor.execute(arguments: ["list", "--folder-name", "none"])
        let unfiledNames = parseLines(unfiledOutput ?? "")
        let unfiledItems = makeShortcutItems(names: unfiledNames, folderName: nil, metadata: metadataMap)

        lock.withLock {
            self._cachedFolders = newFolders
            self._unfiledShortcuts = unfiledItems
            self._lastRefreshed = Date()
        }

        return newFolders
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
