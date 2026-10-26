import Foundation

public struct ShortcutItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let folderName: String?

    public init(name: String, folderName: String? = nil, id: String? = nil) {
        self.name = name
        self.folderName = folderName
        self.id = id ?? name
    }
}
