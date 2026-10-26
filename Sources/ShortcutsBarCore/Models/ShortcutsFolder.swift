import Foundation

public struct ShortcutsFolder: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public var shortcuts: [ShortcutItem]

    public init(name: String, shortcuts: [ShortcutItem] = []) {
        self.name = name
        self.shortcuts = shortcuts
    }
}
