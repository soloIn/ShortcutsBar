---
title: "Real-time SQLite WAL Change Detection via CoreServices FSEvents and Unified Cross-View Ordering"
date: "2026-11-01"
category: "database-issues"
module: "Core / Database & Ordering"
problem_type: "database_issue"
component: "database"
symptoms:
  - "Shortcuts database modifications not perceived in real-time by kqueue directory watcher"
  - "Shortcuts.sqlite-wal transaction frames appended by siriactionsd bypassed VNODE directory notifications"
  - "Custom drag-and-drop order was fragmented between FloatingPanel tabs and MenuBar dropdown"
  - "Sequential CLI fetching over multiple folders caused significant refresh lag"
root_cause: "wrong_api"
resolution_type: "code_fix"
severity: "high"
tags:
  - "macos-26"
  - "sqlite-wal"
  - "fsevents"
  - "coreservices"
  - "structured-concurrency"
  - "taskgroup"
  - "strict-weak-ordering"
  - "shortcuts"
---

# Real-time SQLite WAL Change Detection via CoreServices FSEvents and Unified Cross-View Ordering

## Problem
In a native macOS status bar and floating panel application managing macOS Shortcuts, changes made to the user's shortcuts library (creating, editing, renaming, or deleting shortcuts in the macOS Shortcuts App) were not reflected in real time. Concurrently, custom ordering applied by users in the floating panel was desynchronized from the menu bar dropdown and suffered from slow, serial CLI folder fetching.

## Symptoms
- After adding or modifying a shortcut in macOS Shortcuts App, Shortcuts Bar took dozens of seconds or required an application restart to reflect the new state.
- Under SQLite Write-Ahead Logging (`WAL`) mode, transaction frames appended to `Shortcuts.sqlite-wal` by macOS system daemon `siriactionsd` were completely missed by directory-level file system monitors.
- In `MenuBarView`, shortcuts in subfolders and root view did not match the custom order established in `FloatingPanelViewModel`, causing items to appear in inconsistent positions across the two views.
- Sequential CLI invocation (`shortcuts list --folder-name <name>`) over numerous folders introduced cumulative multi-second latency during cache refresh.

## What Didn't Work

### 1. Traditional `kqueue` Directory Monitoring (`DispatchSource.makeFileSystemObjectSource`)
The legacy implementation watched `~/Library/Shortcuts` using `open(dir, O_EVTONLY)` and subscribed to `[.write, .extend, .attrib, .link]`.
- **Why it failed**: In SQLite WAL mode, when transactions are committed, data is written directly to the existing file descriptor of `Shortcuts.sqlite-wal`. Neither file creation, deletion, nor directory entry modification occurs. POSIX `kqueue` directory monitoring only detects `VNODE` modifications to the directory structure itself, not internal file payload modifications of files within the directory.

### 2. Writing Custom Sort Orders Back to macOS `Shortcuts.sqlite`
Attempting to persist custom user drag-and-drop ordering directly into macOS's internal database (`~/Library/Shortcuts/Shortcuts.sqlite`) was investigated and firmly rejected:
- **Why it failed**: macOS Shortcuts synchronizes via CloudKit across iOS, iPadOS, and macOS using Conflict-free Replicated Data Types (CRDT). Directly mutating private SQLite tables (`WFWorkflow`, `WFShortcut`) outside `siriactionsd` triggers CloudKit reconciliation conflicts, database schema lock contention, and sandbox permission violations under macOS System Integrity Protection (SIP).

### 3. Asymmetric Manual Sorting in Individual Views
Previously, `MenuBarView` re-implemented ad-hoc sorting logic via a local dictionary mapping `[String: Int]`, while `FloatingPanelViewModel` relied on `ShortcutsSearchEngine.project`.
- **Why it failed**: Missing items (orphans) were sorted arbitrarily or left unhandled in `MenuBarView`, violating mathematical strict weak ordering and producing visual divergence between the floating panel and the menu bar extra dropdown.

## Solution

### 1. Kernel-Level File Monitoring with CoreServices FSEvents
Replaced the `kqueue` directory descriptor in `ShortcutsDatabaseWatcher.swift` with an `FSEventStreamRef` configured with fine-grained file-level tracking flags:
- `kFSEventStreamCreateFlagFileEvents`: Enables file-level event granular delivery (detecting writes directly to `Shortcuts.sqlite-wal`).
- `kFSEventStreamCreateFlagNoDefer`: Delivers events immediately without system throttling.
- Combined with a 250ms adaptive debounce to coalesce high-frequency SQLite WAL transaction frames.

```swift
// Sources/ShortcutsBarCore/Services/ShortcutsDatabaseWatcher.swift:66-88
let flags = FSEventStreamCreateFlags(
    kFSEventStreamCreateFlagUseCFTypes |
    kFSEventStreamCreateFlagFileEvents |
    kFSEventStreamCreateFlagNoDefer
)

guard let newStream = FSEventStreamCreate(
    kCFAllocatorDefault,
    callback,
    &context,
    pathsToWatch,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
    0.05, // 50ms kernel aggregation latency
    flags
) else { return }

FSEventStreamSetDispatchQueue(newStream, queue)
FSEventStreamStart(newStream)
self.stream = newStream
```

Clean teardown and deallocation is enforced in `stopWatching()` (`ShortcutsDatabaseWatcher.swift:93-105`):
```swift
if let s = stream {
    FSEventStreamStop(s)
    FSEventStreamInvalidate(s)
    FSEventStreamRelease(s)
    self.stream = nil
}
```

### 2. Concurrent TaskGroup Fetching with Lifecycle Defense
In `ShortcutsService.swift:224-250`, transformed sequential CLI folder queries into concurrent structured concurrency tasks via `withThrowingTaskGroup`:

```swift
// Sources/ShortcutsBarCore/Services/ShortcutsService.swift:224-250
try await withThrowingTaskGroup(of: FolderFetchResult.self) { group in
    for folderName in folderNames {
        group.addTask {
            try Task.checkCancellation()
            let shortcutsOutput = try await self.executeOrEmpty(arguments: ["list", "--folder-name", folderName])
            let names = self.parseLines(shortcutsOutput)
            return .folder(name: folderName, names: names)
        }
    }
    // Concurrently fetch unfiled shortcuts
    group.addTask {
        try Task.checkCancellation()
        let unfiledOutput = try await self.executeOrEmpty(arguments: ["list", "--folder-name", "none"])
        return .unfiled(names: self.parseLines(unfiledOutput))
    }
    for try await result in group {
        // Collect results into folderShortcutsMap strictly preserving folder order
    }
}
```

In `AppDelegate.swift:115-124`, added an opportunistic double-check defense when opening the floating panel:
```swift
// Sources/ShortcutsBar/AppDelegate.swift:115-124
public func triggerFloatingPanel() {
    if let lastRefreshed = shortcutsService.lastRefreshed,
       databaseWatcher.hasChanged(since: lastRefreshed) {
        refreshShortcuts()
    } else {
        floatingPanelViewModel.refreshData()
    }
    floatingPanelController.toggle(attachedTo: statusItemController?.statusItem?.button)
}
```

### 3. Unified Strict Weak Ordering Pipeline
Centralized all shortcut and folder ordering logic into `ShortcutsSearchEngine.swift:95-146`, guaranteeing mathematical strict weak ordering:
- If `customOrder.isEmpty`: Preserves macOS system order 1:1.
- If `customOrder` exists: Items present in `customOrder` sort by their respective index (`rankA < rankB`); unpinned items sort via `localizedStandardCompare` consistently at the tail.

```swift
// Sources/ShortcutsBarCore/Services/ShortcutsSearchEngine.swift:95-119
public static func sortShortcuts(_ items: [ShortcutItem], customOrder: [String]) -> [ShortcutItem] {
    guard !customOrder.isEmpty else { return items }

    var orderMap = [String: Int]()
    for (index, name) in customOrder.enumerated() {
        orderMap[name] = index
    }

    return items.sorted { a, b in
        let rankA = orderMap[a.name]
        let rankB = orderMap[b.name]

        if let rA = rankA, let rB = rankB {
            return rA < rB
        } else if rankA != nil {
            return true
        } else if rankB != nil {
            return false
        } else {
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
```

Both `FloatingPanelViewModel` and `MenuBarView:214-229` consume this single source of truth. Additionally, `PreferencesStore.swift:161-177` and `SettingsView.swift:178-185` provide users with a "Reset to Shortcuts App Default Order" action.

## Why This Works
1. **CoreServices FSEvents Kernel Hooks**: Unlike `kqueue` vnode monitoring, `FSEvents` connects to macOS's `/dev/fsevents` kernel device, capturing atomic writes and file-extent mutations across all subpaths even when files are kept open with persistent file descriptors by SQLite.
2. **Coalesced Debounce Window**: SQLite WAL commits often write several blocks in rapid succession (WAL frame write -> index update -> checkpoint). A 250ms debounce window collapses multi-stage transactions into a single refresh execution.
3. **Structured Concurrency Scaling**: Utilizing `withThrowingTaskGroup` decouples CLI query latency from folder count, reducing total refresh wall-clock time from O(N * T) to O(max(T)).
4. **App-Local Persistence Layer**: Storing custom order strictly in application preferences (`UserDefaults`) completely isolates the app from CloudKit sync churn while ensuring 100% deterministic visual presentation.

## Prevention
1. **Never use directory-level kqueue descriptors to watch SQLite databases**: When monitoring SQLite databases operating in WAL or rollback-journal modes on macOS, always utilize `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`.
2. **Never attempt to write internal state back into third-party Apple SQLite databases**: Apple platform databases managed by daemons (`siriactionsd`, `callservicesd`, etc.) must be treated as strictly read-only.
3. **Audit sorting predicates for Strict Weak Ordering**: When combining user-defined manual index ranks with fallback natural language sorting, ensure:
   - Irreflexivity: x not < x.
   - Asymmetry: if x < y, then y not < x.
   - Transitivity: if x < y and y < z, then x < z.
4. **Automated Verification**: Include integration tests writing to isolated temporary SQLite WAL files (`Tests/ShortcutsBarTests/ShortcutsDatabaseWatcherTests.swift:21-51`) to catch any regressions in file event propagation.

## Related Issues
- Related: `docs/solutions/ui-bugs/dynamic-menubar-keyboard-shortcut-sync-and-carbon-modifier-collision.md` (MenuBarExtra presentation and hotkey synchronization)
- Related: `docs/solutions/ui-bugs/menubar-native-highlight-and-script-monitor-architecture.md` (Task execution lifecycle and status item architecture)
