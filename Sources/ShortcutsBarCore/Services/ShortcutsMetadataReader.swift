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
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            self.dbPath = homeURL.appending(path: "Library/Shortcuts/Shortcuts.sqlite").path(percentEncoded: false)
        }
    }

    /// Reads metadata from Shortcuts.sqlite in read-only mode with busy timeout handling
    public func fetchAllMetadata() -> [String: ShortcutMetadata] {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return [:]
        }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(dbPath, &db, openFlags, nil)
        guard openResult == SQLITE_OK, let database = db else {
            if let db = db { sqlite3_close_v2(db) }
            return [:]
        }
        defer { sqlite3_close_v2(database) }

        // Set busy timeout to 2000ms so concurrent WAL commits by system daemons do not fail immediately
        sqlite3_busy_timeout(database, 2000)

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
        while true {
            let stepResult = sqlite3_step(stmt)
            if stepResult == SQLITE_ROW {
                guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
                let name = String(cString: namePtr)

                let actionCount: Int
                if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                    actionCount = Int(sqlite3_column_int(stmt, 1))
                } else {
                    actionCount = 0
                }

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
            } else {
                break
            }
        }

        return result
    }
}
