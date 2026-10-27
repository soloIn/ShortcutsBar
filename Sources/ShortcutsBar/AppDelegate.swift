import AppKit
import ShortcutsBarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let shortcutsService = ShortcutsService()
    public let processManager = ProcessManager()
    public let preferencesStore = PreferencesStore.shared
    public let databaseWatcher = ShortcutsDatabaseWatcher.shared

    public private(set) var statusItemController: StatusItemController!
    public private(set) var menuBuilder: MenuBuilder!
    public private(set) var settingsWindowController: SettingsWindowController!

    private var preferencesObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory status bar app (no Dock icon, desktop agent)
        NSApp.setActivationPolicy(.accessory)

        // Initialize UI components
        statusItemController = StatusItemController(
            processManager: processManager,
            preferencesStore: preferencesStore
        )
        menuBuilder = MenuBuilder()
        menuBuilder.shortcutsService = shortcutsService
        menuBuilder.processManager = processManager
        menuBuilder.currentScope = preferencesStore.folderScope

        settingsWindowController = SettingsWindowController(
            preferencesStore: preferencesStore,
            shortcutsService: shortcutsService
        )

        menuBuilder.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }

        // Attach dynamic menu to status item
        statusItemController.menu = menuBuilder.buildMenu()

        // Initial shortcuts refresh
        refreshShortcutsAndMenu()

        // Start live filesystem watching for automatic instant library sync
        databaseWatcher.onDatabaseChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshShortcutsAndMenu()
            }
        }
        databaseWatcher.startWatching()

        // Listen for preference changes with explicit queue: .main dispatch to strictly uphold @MainActor UI boundaries
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.menuBuilder.currentScope = self.preferencesStore.folderScope
                self.statusItemController.menu = self.menuBuilder.buildMenu()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        databaseWatcher.stopWatching()
        if let obs = preferencesObserver {
            NotificationCenter.default.removeObserver(obs)
            preferencesObserver = nil
        }
    }

    private func refreshShortcutsAndMenu() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            _ = try? await self.shortcutsService.refreshCache()
            self.statusItemController.menu = self.menuBuilder.buildMenu()
        }
    }
}
