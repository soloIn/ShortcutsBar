import Foundation

public protocol ShortcutsCLIExecuting: Sendable {
    func execute(arguments: [String]) async throws -> String
}

public struct DefaultShortcutsCLIExecutor: ShortcutsCLIExecuting {
    public init() {}

    public func execute(arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let output = String(data: data, encoding: .utf8) ?? ""
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ShortcutsCLI",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "shortcuts CLI failed with code \(process.terminationStatus)"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
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

    /// Refresh folder and shortcut data from CLI and enrich with SQLite metadata
    @discardableResult
    public func refreshCache() async throws -> [ShortcutsFolder] {
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
            let items = names.map { name in
                let meta = metadataMap[name]
                return ShortcutItem(
                    name: name,
                    folderName: folderName,
                    glyph: meta?.glyph,
                    colorValue: meta?.colorValue,
                    actionCount: meta?.actionCount ?? 0
                )
            }
            newFolders.append(ShortcutsFolder(name: folderName, shortcuts: items))
        }

        // 4. Fetch unfiled shortcuts
        let unfiledOutput = try? await executor.execute(arguments: ["list", "--folder-name", "none"])
        let unfiledNames = parseLines(unfiledOutput ?? "")
        let unfiledItems = unfiledNames.map { name in
            let meta = metadataMap[name]
            return ShortcutItem(
                name: name,
                folderName: nil,
                glyph: meta?.glyph,
                colorValue: meta?.colorValue,
                actionCount: meta?.actionCount ?? 0
            )
        }

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
                return []
            }
        }
    }

    private func parseLines(_ text: String) -> [String] {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
