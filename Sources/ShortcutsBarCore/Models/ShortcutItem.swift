import Foundation

public struct ShortcutItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let folderName: String?
    public let glyph: Int?
    public let colorValue: Int64?
    public let actionCount: Int

    public init(
        name: String,
        folderName: String? = nil,
        id: String? = nil,
        glyph: Int? = nil,
        colorValue: Int64? = nil,
        actionCount: Int = 0
    ) {
        self.name = name
        self.folderName = folderName
        self.id = id ?? name
        self.glyph = glyph
        self.colorValue = colorValue
        self.actionCount = actionCount
    }
}
