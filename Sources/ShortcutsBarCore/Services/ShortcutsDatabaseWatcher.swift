import Foundation

public final class ShortcutsDatabaseWatcher: @unchecked Sendable {
    public static let shared = ShortcutsDatabaseWatcher()

    private let shortcutsDirectoryPath: String
    private let walFilePath: String
    private let sqliteFilePath: String

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.shortcutsbar.database-watcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    public var onDatabaseChanged: (@Sendable () -> Void)?

    public init(directoryPath: String? = nil) {
        let dir: String
        if let custom = directoryPath {
            dir = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            dir = "\(home)/Library/Shortcuts"
        }
        self.shortcutsDirectoryPath = dir
        self.walFilePath = "\(dir)/Shortcuts.sqlite-wal"
        self.sqliteFilePath = "\(dir)/Shortcuts.sqlite"
    }

    deinit {
        stopWatching()
    }

    public func startWatching() {
        guard source == nil else { return }

        fileDescriptor = open(shortcutsDirectoryPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .link],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.scheduleDebouncedChange()
        }

        newSource.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }

        self.source = newSource
        newSource.resume()
    }

    public func stopWatching() {
        if let s = source {
            s.cancel()
            source = nil
        }
    }

    /// Checks if the database or WAL file has been modified after the given timestamp
    public func hasChanged(since date: Date) -> Bool {
        let fm = FileManager.default
        let paths = [walFilePath, sqliteFilePath]

        for path in paths {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                if modDate > date {
                    return true
                }
            }
        }
        return false
    }

    private func scheduleDebouncedChange() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.onDatabaseChanged?()
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}
