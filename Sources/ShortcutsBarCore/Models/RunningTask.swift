import Foundation

public struct RunningTask: Identifiable, Equatable, @unchecked Sendable {
    public let id: UUID
    public let shortcutName: String
    public let startTime: Date
    public var pid: pid_t?
    public let actionCount: Int

    public init(
        id: UUID = UUID(),
        shortcutName: String,
        startTime: Date = Date(),
        pid: pid_t? = nil,
        actionCount: Int = 0
    ) {
        self.id = id
        self.shortcutName = shortcutName
        self.startTime = startTime
        self.pid = pid
        self.actionCount = actionCount
    }

    public static func == (lhs: RunningTask, rhs: RunningTask) -> Bool {
        return lhs.id == rhs.id && lhs.shortcutName == rhs.shortcutName && lhs.pid == rhs.pid && lhs.actionCount == rhs.actionCount
    }
}
