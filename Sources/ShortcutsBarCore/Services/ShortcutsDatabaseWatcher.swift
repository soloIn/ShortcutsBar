import Foundation

public final class ShortcutsDatabaseWatcher: @unchecked Sendable {
    public static let shared = ShortcutsDatabaseWatcher()

    private let shortcutsDirectoryPath: String
    private let walFilePath: String
    private let sqliteFilePath: String

    private let lock = NSLock()
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.shortcutsbar.database-watcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    private var _onDatabaseChanged: (@Sendable () -> Void)?

    public var onDatabaseChanged: (@Sendable () -> Void)? {
        get { lock.withLock { _onDatabaseChanged } }
        set { lock.withLock { _onDatabaseChanged = newValue } }
    }

    public init(directoryPath: String? = nil) {
        let dir: String
        if let custom = directoryPath {
            dir = custom
        } else {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            dir = homeURL.appending(path: "Library/Shortcuts").path(percentEncoded: false)
        }
        self.shortcutsDirectoryPath = dir
        self.walFilePath = "\(dir)/Shortcuts.sqlite-wal"
        self.sqliteFilePath = "\(dir)/Shortcuts.sqlite"
    }

    deinit {
        stopWatching()
    }

    public func startWatching() {
        lock.withLock {
            guard source == nil else { return }

            let fd = open(shortcutsDirectoryPath, O_EVTONLY)
            guard fd >= 0 else {
                return
            }
            self.fileDescriptor = fd

            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link],
                queue: queue
            )

            newSource.setEventHandler { [weak self] in
                self?.scheduleDebouncedChange()
            }

            newSource.setCancelHandler {
                close(fd)
            }

            self.source = newSource
            newSource.resume()
        }
    }

    public func stopWatching() {
        lock.withLock {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            if let s = source {
                s.cancel()
                source = nil
            }
            fileDescriptor = -1
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
        lock.withLock {
            debounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                let callback = self?.lock.withLock { self?._onDatabaseChanged }
                callback?()
            }

            self.debounceWorkItem = workItem
            queue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }
    }
}
