import AppKit
import ShortcutsBarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let shortcutsService = ShortcutsService()
    public let processManager = ProcessManager()
    public let preferencesStore = PreferencesStore.shared

    public private(set) var statusItemController: StatusItemController!
    public private(set) var menuBuilder: MenuBuilder!
    public private(set) var settingsWindowController: SettingsWindowController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory status bar app (no Dock icon, desktop agent)
        NSApp.setActivationPolicy(.accessory)

        // Initialize UI components
        statusItemController = StatusItemController(processManager: processManager)
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
        Task {
            _ = try? await shortcutsService.refreshCache()
            self.statusItemController.menu = self.menuBuilder.buildMenu()
        }

        // Listen for preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferencesChanged),
            name: PreferencesStore.preferencesChangedNotification,
            object: nil
        )
    }

    @objc private func handlePreferencesChanged() {
        menuBuilder.currentScope = preferencesStore.folderScope
        statusItemController.menu = menuBuilder.buildMenu()
    }
}
