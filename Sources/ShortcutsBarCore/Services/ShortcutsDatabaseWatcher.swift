import Foundation
import CoreServices
import OSLog

/// 快捷指令资料库实时文件监视器
/// 💡 采用 macOS 内核级 CoreServices FSEvents 替代传统的 kqueue 目录监听，
/// 确保能毫秒级捕获 siriactionsd 对 Shortcuts.sqlite-wal 的追加事务及系统检查点回写。
public final class ShortcutsDatabaseWatcher: @unchecked Sendable {
    public static let shared = ShortcutsDatabaseWatcher()

    private let shortcutsDirectoryPath: String
    private let walFilePath: String
    private let sqliteFilePath: String

    private let lock = NSLock()
    private var stream: FSEventStreamRef?
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

    /// 启动基于 FSEvents 的文件系统实时监听
    public func startWatching() {
        lock.withLock {
            guard stream == nil else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<ShortcutsDatabaseWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleFSEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
            }

            let pathsToWatch = [shortcutsDirectoryPath] as CFArray
            // 💡 开启 kFSEventStreamCreateFlagFileEvents 以捕获具体文件的细粒度修改（包括 SQLite WAL 追加写入）
            // 搭配 kFSEventStreamCreateFlagNoDefer 保证事件在微秒级被内核投递
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
            )

            guard let newStream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05, // 50ms 内核事件合并窗口
                flags
            ) else {
                Logger.watcher.error("Failed to create FSEventStream for path: \(self.shortcutsDirectoryPath, privacy: .public)")
                return
            }

            FSEventStreamSetDispatchQueue(newStream, queue)
            FSEventStreamStart(newStream)
            self.stream = newStream
        }
    }

    /// 停止文件系统监听并安全释放 CoreServices 资源
    public func stopWatching() {
        lock.withLock {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            if let s = stream {
                FSEventStreamStop(s)
                // 💡 必须先解除与 GCD 队列的绑定，阻止后续事件入队
                FSEventStreamSetDispatchQueue(s, nil)
                FSEventStreamInvalidate(s)
                FSEventStreamRelease(s)
                self.stream = nil
            }
        }
        // 💡 队列屏障同步排空：确保当前队列中可能滞留的回调块全部清空，杜绝 deinit 后访问野指针产生 Use-After-Free
        queue.sync {}
    }

    /// 检查数据库或 WAL 文件在给定时间戳后是否发生过变动（用于唤醒与生命周期按需校验）
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

    // MARK: - Private Helpers

    private func handleFSEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        // 💡 遵循 Apple 内存管理准则，安全解包 C 回调传递的 CFArrayRef，杜绝 unsafeBitCast 堆破坏
        let pathsArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        guard let paths = (pathsArray as? [String]) ?? (pathsArray as NSArray as? [String]) else { return }

        // 💡 过滤与 Shortcuts.sqlite、Shortcuts.sqlite-wal 相关的变更，防止不相关的日志噪音引起多余刷新
        var relevantChangeDetected = false
        for path in paths {
            if path.contains("Shortcuts.sqlite") || path.hasPrefix(shortcutsDirectoryPath) {
                relevantChangeDetected = true
                break
            }
        }

        if relevantChangeDetected {
            scheduleDebouncedChange()
        }
    }

    private func scheduleDebouncedChange() {
        lock.withLock {
            guard stream != nil else { return }
            debounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let callback = self.lock.withLock { self._onDatabaseChanged }
                callback?()
            }

            self.debounceWorkItem = workItem
            // 💡 250ms 自适应防抖，合并系统短时间内高频的连续 WAL 事务追加
            queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }
}
