import Foundation

public enum FolderScope: Equatable, Hashable, Codable, Sendable {
    /// Show all folders as submenus
    case root
    /// Show a specific folder flatly (default: "Menu Bar" if available)
    case leaf(folderName: String)

    public var displayName: String {
        switch self {
        case .root:
            return "所有快捷指令 (层级子菜单)"
        case .leaf(let folderName):
            return "\(folderName) (纯扁平)"
        }
    }

    public var folderName: String? {
        switch self {
        case .root:
            return nil
        case .leaf(let folderName):
            return folderName
        }
    }
}
