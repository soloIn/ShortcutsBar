import Foundation

public struct RunningTask: Identifiable, Equatable, Sendable {
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
}
