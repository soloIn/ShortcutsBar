import Foundation
import OSLog

/// 💡 ShortcutsBar 统一结构化日志中枢
/// 严格遵循 Apple Unified Logging (os.Logger) 规范，支持按 Subsystem 和 Category 进行高性能过滤与排障
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.shortcutsbar"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let process = Logger(subsystem: subsystem, category: "process")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let watcher = Logger(subsystem: subsystem, category: "watcher")
}
