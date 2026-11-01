import Foundation
import SwiftUI
import AppKit

@MainActor
public final class FloatingPanelViewModel: ObservableObject {
    public let shortcutsService: ShortcutsService
    public let processManager: ProcessManager
    public let preferencesStore: PreferencesStore
    public let searchEngine: ShortcutsSearchEngine
    public weak var panelController: FloatingPanelController?

    public var onOpenSettings: (() -> Void)?
    private var queueObserverId: UUID?
    private var completionObserverId: UUID?
    private var cacheUpdateObserver: NSObjectProtocol?

    @Published public var searchQuery: String = "" {
        didSet {
            updateVisibleItems()
            // Reset highlighted index and scroll target to 0 whenever search query changes
            highlightedIndex = 0
            keyboardScrollTargetIndex = 0
        }
    }

    @Published public var selectedFolder: String = "全部" {
        didSet {
            updateVisibleItems()
            highlightedIndex = 0
            keyboardScrollTargetIndex = 0
        }
    }

    @Published public var availableFolders: [String] = ["全部"]
    @Published public var allFolders: [ShortcutsFolder] = []
    @Published public var visibleItems: [ProjectedShortcutItem] = []
    @Published public var highlightedIndex: Int = 0
    @Published public var keyboardScrollTargetIndex: Int? = nil
    @Published public var focusToken: UUID = UUID()

    @Published public var runningTasks: [RunningTask] = []
    @Published public var completedTasks: [UUID: TaskFeedback] = [:]
    @Published public var completedTaskOrder: [UUID] = []
    @Published public var isKeyboardNavigating: Bool = false
    @Published public var selectedErrorTask: ErrorWrapper? = nil {
        didSet {
            panelController?.panel.isPopoverPresented = (selectedErrorTask != nil)
            if selectedErrorTask == nil {
                panelController?.panel.checkAndHideIfNeeded()
            }
        }
    }
    @Published public var isPinned: Bool = false

    public struct TaskFeedback: Equatable, Sendable {
        public let shortcutName: String
        public let isSuccess: Bool
        public let errorSnippet: String?
        public let elapsed: TimeInterval
    }

    public init(
        shortcutsService: ShortcutsService,
        processManager: ProcessManager,
        preferencesStore: PreferencesStore = .shared,
        searchEngine: ShortcutsSearchEngine = ShortcutsSearchEngine(),
        panelController: FloatingPanelController? = nil
    ) {
        self.shortcutsService = shortcutsService
        self.processManager = processManager
        self.preferencesStore = preferencesStore
        self.searchEngine = searchEngine
        self.panelController = panelController
        self.isPinned = preferencesStore.isPinned
        self.runningTasks = processManager.activeTasks

        setupProcessObservers()
        setupCacheObserver()
        refreshData()
    }

    isolated deinit {
        if let qId = queueObserverId {
            processManager.removeQueueObserver(qId)
        }
        if let cId = completionObserverId {
            processManager.removeTaskCompletedObserver(cId)
        }
        if let obs = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setupCacheObserver() {
        cacheUpdateObserver = NotificationCenter.default.addObserver(
            forName: ShortcutsService.didUpdateCacheNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshData()
            }
        }
    }

    private func setupProcessObservers() {
        queueObserverId = processManager.addQueueObserver { [weak self] tasks in
            Task { @MainActor [weak self] in
                self?.runningTasks = tasks
            }
        }

        completionObserverId = processManager.addTaskCompletedObserver { [weak self] task, success in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let elapsed = Date().timeIntervalSince(task.startTime)
                let feedback = TaskFeedback(
                    shortcutName: task.shortcutName,
                    isSuccess: success,
                    errorSnippet: success ? nil : (task.errorMessage ?? "执行失败"),
                    elapsed: elapsed
                )
                self.completedTasks[task.id] = feedback
                self.completedTaskOrder.removeAll(where: { $0 == task.id })
                self.completedTaskOrder.append(task.id)

                // Limit capacity to max 5 items to avoid unbounded memory growth (FIFO eviction)
                while self.completedTaskOrder.count > 5 {
                    let oldestKey = self.completedTaskOrder.removeFirst()
                    self.completedTasks.removeValue(forKey: oldestKey)
                }

                // Auto fade out completed tasks: 1.5s for success, 3.5s for failed
                let sleepTime: UInt64 = success ? 1_500_000_000 : 3_500_000_000
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: sleepTime)
                    self?.dismissCompletedTask(id: task.id)
                }
            }
        }
    }

    public func dismissCompletedTask(id: UUID) {
        completedTasks.removeValue(forKey: id)
        completedTaskOrder.removeAll(where: { $0 == id })
    }

    public var hasSubmenus: Bool {
        switch preferencesStore.folderScope {
        case .leaf:
            return false
        case .root:
            return availableFolders.count > 1
        }
    }

    public func refreshData() {
        self.focusToken = UUID()
        self.runningTasks = processManager.activeTasks
        let currentScope = preferencesStore.folderScope
        switch currentScope {
        case .leaf(let folderName):
            let items = shortcutsService.getShortcuts(for: currentScope)
            let folder = ShortcutsFolder(name: folderName, shortcuts: items)
            self.allFolders = [folder]
            self.availableFolders = [folderName]
            self.selectedFolder = folderName
        case .root:
            let folders = shortcutsService.allFoldersWithUnfiled
            self.allFolders = folders

            var names = ["全部"]
            for f in folders where f.name != "none" && !f.name.isEmpty {
                if !names.contains(f.name) {
                    names.append(f.name)
                }
            }
            self.availableFolders = names
            if !names.contains(selectedFolder) {
                selectedFolder = "全部"
            }
        }
        updateVisibleItems()
    }

    public func updateVisibleItems() {
        let customOrders: [String: [String]] = [
            selectedFolder: preferencesStore.getCustomOrder(for: selectedFolder)
        ]
        self.visibleItems = searchEngine.project(
            allFolders: allFolders,
            selectedFolder: selectedFolder,
            searchQuery: searchQuery,
            customSortOrders: customOrders
        )

        if highlightedIndex >= visibleItems.count && !visibleItems.isEmpty {
            highlightedIndex = visibleItems.count - 1
        }
    }

    public func togglePin() {
        isPinned.toggle()
        preferencesStore.isPinned = isPinned
        panelController?.updateWindowLevel(isPinned: isPinned)
    }

    public func selectPreviousFolder() {
        guard !availableFolders.isEmpty else { return }
        guard let currentIndex = availableFolders.firstIndex(of: selectedFolder) else {
            selectedFolder = availableFolders[0]
            return
        }
        let prevIndex = (currentIndex - 1 + availableFolders.count) % availableFolders.count
        selectedFolder = availableFolders[prevIndex]
    }

    public func selectNextFolder() {
        guard !availableFolders.isEmpty else { return }
        guard let currentIndex = availableFolders.firstIndex(of: selectedFolder) else {
            selectedFolder = availableFolders[0]
            return
        }
        let nextIndex = (currentIndex + 1) % availableFolders.count
        selectedFolder = availableFolders[nextIndex]
    }

    public func execute(item: ShortcutItem) {
        _ = try? processManager.launch(shortcutName: item.name, actionCount: item.actionCount)

        if !isPinned {
            panelController?.hide()
        }
    }

    public func executeHighlighted() {
        guard !visibleItems.isEmpty, highlightedIndex < visibleItems.count else { return }
        execute(item: visibleItems[highlightedIndex].item)
    }

    public func executeNumbered(index: Int) {
        // index 0..8 corresponds to ⌘1..⌘9
        guard index >= 0 && index < visibleItems.count else { return }
        execute(item: visibleItems[index].item)
    }

    public func moveHighlight(down: Bool) {
        guard !visibleItems.isEmpty else { return }
        if down {
            highlightedIndex = min(highlightedIndex + 1, visibleItems.count - 1)
        } else {
            highlightedIndex = max(highlightedIndex - 1, 0)
        }
        keyboardScrollTargetIndex = highlightedIndex
    }

    public func reorderVisibleItems(from source: IndexSet, to destination: Int) {
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Reordering locked during active search
            return
        }

        var names = visibleItems.map { $0.item.name }
        names.move(fromOffsets: source, toOffset: destination)
        preferencesStore.setCustomOrder(names, for: selectedFolder)
        updateVisibleItems()
    }

    public func clearCompletedTask(id: UUID) {
        dismissCompletedTask(id: id)
    }

    public func terminateTask(id: UUID) {
        processManager.terminate(taskId: id)
    }

    public func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    public func openSettings() {
        if !isPinned {
            panelController?.hide()
        }
        onOpenSettings?()
    }
}
