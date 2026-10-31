import Foundation
import CoreFoundation

public struct ProjectedShortcutItem: Identifiable, Equatable, Sendable {
    public var id: String { item.id }
    public let item: ShortcutItem
    public let inPanelShortcut: String?
    public let folderName: String?

    public init(item: ShortcutItem, inPanelShortcut: String? = nil, folderName: String? = nil) {
        self.item = item
        self.inPanelShortcut = inPanelShortcut
        self.folderName = folderName
    }
}

public struct ShortcutsSearchEngine: Sendable {
    public init() {}

    /// Converts Chinese text into normalized lowercase Pinyin and initials
    public static func pinyinRepresentations(for text: String) -> (full: String, initials: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let cfString = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, trimmed as CFString)
        CFStringTransform(cfString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(cfString, nil, kCFStringTransformStripDiacritics, false)

        let transformed = (cfString as String?)?.lowercased() ?? trimmed.lowercased()
        let words = transformed.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }

        let fullPinyin = words.joined()
        let initials = words.compactMap { $0.first }.map { String($0) }.joined()

        return (fullPinyin, initials)
    }

    private static let pinyinLock = NSLock()
    nonisolated(unsafe) private static var pinyinCache: [String: (full: String, initials: String)] = [:]

    /// Cached Pinyin representation to prevent repeated ICU transforms
    public static func cachedPinyinRepresentations(for text: String) -> (full: String, initials: String) {
        pinyinLock.withLock {
            if let cached = pinyinCache[text] {
                return cached
            }
            let res = pinyinRepresentations(for: text)
            pinyinCache[text] = res
            return res
        }
    }

    /// Evaluates match score between query and target shortcut name
    /// Higher score indicates higher match quality (0 = no match)
    public func matchScore(query: String, targetName: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = targetName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !q.isEmpty else { return 100 }
        if t == q { return 100 }
        if t.hasPrefix(q) { return 90 }

        // Multi-word / space-separated search support (e.g. "run test" matches "Run Swift Test")
        let queryTokens = q.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if queryTokens.count > 1 {
            let (fullPinyin, initials) = Self.cachedPinyinRepresentations(for: targetName)
            let allMatched = queryTokens.allSatisfy { token in
                t.contains(token) || fullPinyin.contains(token) || initials.contains(token)
            }
            if allMatched { return 88 }
        }

        // Word boundary match (e.g. "Run Tests" matches "test")
        let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if words.contains(where: { $0.hasPrefix(q) }) { return 85 }

        // Substring match
        if t.contains(q) { return 75 }

        // Pinyin representations (cached for high performance)
        let (fullPinyin, initials) = Self.cachedPinyinRepresentations(for: targetName)
        if initials == q { return 70 }
        if initials.hasPrefix(q) { return 65 }
        if fullPinyin.hasPrefix(q) { return 60 }
        if fullPinyin.contains(q) { return 50 }
        if initials.contains(q) { return 40 }

        return 0
    }

    /// Projects a list of shortcuts into visible items, applying folder filtering, custom sorting, search filtering, and ⌘1~⌘9 key equivalents
    public func project(
        allFolders: [ShortcutsFolder],
        selectedFolder: String?, // nil or "全部" means all
        searchQuery: String,
        customSortOrders: [String: [String]] = [:]
    ) -> [ProjectedShortcutItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmedQuery.isEmpty

        let filteredPairs: [(folder: String, item: ShortcutItem)]

        if isSearching {
            // Search across all folders provided in allFolders
            var unique: [(folder: String, item: ShortcutItem)] = []
            var seen = Set<String>()
            for folder in allFolders {
                for item in folder.shortcuts {
                    if !seen.contains(item.name) {
                        seen.insert(item.name)
                        unique.append((folder.name, item))
                    }
                }
            }

            struct ScoredPair {
                let folder: String
                let item: ShortcutItem
                let score: Int
            }

            var scored: [ScoredPair] = []
            for pair in unique {
                let score = self.matchScore(query: trimmedQuery, targetName: pair.item.name)
                if score > 0 {
                    scored.append(ScoredPair(folder: pair.folder, item: pair.item, score: score))
                }
            }
            scored.sort { a, b in
                if a.score != b.score {
                    return a.score > b.score
                }
                return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
            }
            filteredPairs = scored.map { ($0.folder, $0.item) }
        } else {
            // Tab browsing mode
            let folderItems: [(folder: String, item: ShortcutItem)]
            if let selected = selectedFolder, selected != "全部" {
                // IMPORTANT: Directly get items for the selected folder to guarantee 100% data consistency!
                if let folder = allFolders.first(where: { $0.name == selected }) {
                    folderItems = folder.shortcuts.map { (selected, $0) }
                } else {
                    folderItems = []
                }
            } else {
                // "全部" mode: flatten all folders, de-duplicating by shortcut name
                var uniqueItems: [(folder: String, item: ShortcutItem)] = []
                var seenNames = Set<String>()
                for folder in allFolders {
                    for item in folder.shortcuts {
                        if !seenNames.contains(item.name) {
                            seenNames.insert(item.name)
                            uniqueItems.append((folder.name, item))
                        }
                    }
                }
                folderItems = uniqueItems
            }

            // Apply custom sort order if specified (Strict Weak Ordering compliant)
            let targetFolder = selectedFolder ?? "全部"
            let customOrder = customSortOrders[targetFolder] ?? []
            if !customOrder.isEmpty {
                var orderMap = [String: Int]()
                for (index, name) in customOrder.enumerated() {
                    orderMap[name] = index
                }
                filteredPairs = folderItems.sorted { a, b in
                    let rankA = orderMap[a.item.name] ?? Int.max
                    let rankB = orderMap[b.item.name] ?? Int.max
                    if rankA != rankB {
                        return rankA < rankB
                    }
                    return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
                }
            } else {
                filteredPairs = folderItems
            }
        }

        // Dynamically assign ⌘1 ~ ⌘9 to top 9 items
        return filteredPairs.enumerated().map { index, pair in
            let shortcutBadge: String? = (index < 9) ? "⌘\(index + 1)" : nil
            return ProjectedShortcutItem(
                item: pair.item,
                inPanelShortcut: shortcutBadge,
                folderName: pair.folder
            )
        }
    }
}
