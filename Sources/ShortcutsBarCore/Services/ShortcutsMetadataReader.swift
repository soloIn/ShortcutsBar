import Foundation
import SQLite3

public struct ShortcutMetadata: Equatable, Sendable {
    public let glyph: Int?
    public let colorValue: Int64?
    public let actionCount: Int

    public init(glyph: Int? = nil, colorValue: Int64? = nil, actionCount: Int = 0) {
        self.glyph = glyph
        self.colorValue = colorValue
        self.actionCount = actionCount
    }
}

public final class ShortcutsMetadataReader: Sendable {
    public static let shared = ShortcutsMetadataReader()

    private let dbPath: String

    public init(dbPath: String? = nil) {
        if let custom = dbPath {
            self.dbPath = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.dbPath = "\(home)/Library/Shortcuts/Shortcuts.sqlite"
        }
    }

    /// Reads metadata from Shortcuts.sqlite in read-only mode without locking the database
    public func fetchAllMetadata() -> [String: ShortcutMetadata] {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return [:]
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database = db else {
            if let db = db { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT s.ZNAME, s.ZACTIONCOUNT, i.ZGLYPHNUMBER, i.ZBACKGROUNDCOLORVALUE
        FROM ZSHORTCUT s
        LEFT JOIN ZSHORTCUTICON i ON s.ZICON = i.Z_PK;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            if let stmt = statement { sqlite3_finalize(stmt) }
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: ShortcutMetadata] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: namePtr)
            let actionCount = Int(sqlite3_column_int(stmt, 1))

            let glyph: Int?
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                glyph = Int(sqlite3_column_int(stmt, 2))
            } else {
                glyph = nil
            }

            let colorValue: Int64?
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                colorValue = sqlite3_column_int64(stmt, 3)
            } else {
                colorValue = nil
            }

            result[name] = ShortcutMetadata(glyph: glyph, colorValue: colorValue, actionCount: actionCount)
        }

        return result
    }
}
