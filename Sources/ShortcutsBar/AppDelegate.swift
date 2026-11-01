import AppKit
import ShortcutsBarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let shortcutsService = ShortcutsService()
    public let processManager = ProcessManager()
    public let preferencesStore = PreferencesStore.shared
    public let databaseWatcher = ShortcutsDatabaseWatcher.shared
    public let globalHotkeyManager = GlobalHotkeyManager.shared

    public private(set) var statusItemController: StatusItemController?
    @available(*, deprecated, message: "Replaced by direct MenuBarExtra and MenuBarView")
    public private(set) var menuBarDropdownController: MenuBarDropdownController?
    public private(set) var settingsWindowController: SettingsWindowController!
    public private(set) var floatingPanelController: FloatingPanelController!
    public private(set) var floatingPanelViewModel: FloatingPanelViewModel!
    public private(set) var keyInterceptor: PanelKeyInterceptor!

    private var preferencesObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory status bar app (no Dock icon, desktop agent)
        NSApp.setActivationPolicy(.accessory)

        // Initialize helper builders & controllers
        statusItemController = StatusItemController(
            processManager: processManager,
            preferencesStore: preferencesStore
        )
        statusItemController?.onTriggerFloatingPanel = { [weak self] in
            self?.triggerFloatingPanel()
        }
        statusItemController?.onTriggerDropdown = { [weak self] in
            self?.triggerDropdownMenu()
        }

        settingsWindowController = SettingsWindowController(
            preferencesStore: preferencesStore,
            shortcutsService: shortcutsService
        )

        // Initialize modern Liquid Glass Floating Panel subsystem
        floatingPanelController = FloatingPanelController(preferencesStore: preferencesStore)
        floatingPanelController.onPresentationChanged = { [weak self] isPresented in
            self?.statusItemController?.setHighlighted(isPresented)
        }
        floatingPanelViewModel = FloatingPanelViewModel(
            shortcutsService: shortcutsService,
            processManager: processManager,
            preferencesStore: preferencesStore,
            panelController: floatingPanelController
        )
        floatingPanelViewModel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        floatingPanelController.setContent(FloatingPanelView(viewModel: floatingPanelViewModel))

        // Connect panel key cancellation and dismissal
        floatingPanelController.panel.onCancelOperation = { [weak self] in
            guard let self = self else { return }
            if !self.floatingPanelViewModel.searchQuery.isEmpty {
                self.floatingPanelViewModel.searchQuery = ""
            } else if !self.floatingPanelController.panel.isPinned {
                self.floatingPanelController.panel.closeWithAnimation()
            }
        }

        // Initialize keyboard event interceptor
        keyInterceptor = PanelKeyInterceptor(
            panel: floatingPanelController.panel,
            viewModel: floatingPanelViewModel,
            panelController: floatingPanelController
        )
        keyInterceptor.startMonitoring()

        // Configure Global Hotkey
        globalHotkeyManager.onHotkeyPressed = { [weak self] in
            self?.triggerFloatingPanel()
        }
        updateGlobalHotkeyRegistration()

        // Initial shortcuts refresh
        refreshShortcuts()

        // Start live filesystem watching for automatic instant library sync
        databaseWatcher.onDatabaseChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshShortcuts()
            }
        }
        databaseWatcher.startWatching()

        // Request notification authorization for failure alerts
        StatusItemController.requestNotificationAuthorization()

        // Listen for preference changes with explicit queue: .main dispatch to strictly uphold @MainActor UI boundaries
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                guard let self = self else { return }
                // Filter out panel origin and pin state changes so window moves don't trigger reload storms
                if key == "panelOrigin" || key == "isPinned" {
                    return
                }
                self.floatingPanelViewModel.refreshData()
                self.updateGlobalHotkeyRegistration()
            }
        }
    }

    public func setStatusItemController(_ controller: StatusItemController) {
        self.statusItemController = controller
    }

    public func triggerFloatingPanel() {
        if menuBarDropdownController?.isPresented == true {
            menuBarDropdownController?.close()
        }
        floatingPanelViewModel.refreshData()
        floatingPanelController.toggle(attachedTo: statusItemController?.statusItem?.button)
    }

    public func triggerDropdownMenu() {
        if floatingPanelController?.isPresented == true {
            floatingPanelController.hide()
        }
        menuBarDropdownController?.toggle(attachedTo: statusItemController?.statusItem?.button)
    }

    public func openSettings() {
        if let controller = settingsWindowController {
            controller.show()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        processManager.terminateAll()
        databaseWatcher.stopWatching()
        keyInterceptor?.stopMonitoring()
        globalHotkeyManager.unregister()
        menuBarDropdownController?.close()

        if let obs = preferencesObserver {
            NotificationCenter.default.removeObserver(obs)
            preferencesObserver = nil
        }
    }

    private func refreshShortcuts() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            _ = try? await self.shortcutsService.refreshCache()
            self.floatingPanelViewModel.refreshData()
        }
    }

    private func updateGlobalHotkeyRegistration() {
        if preferencesStore.globalHotkeyEnabled,
           let code = preferencesStore.globalHotkeyCode,
           let mods = preferencesStore.globalHotkeyModifiers {
            _ = globalHotkeyManager.register(keyCode: code, modifiers: mods)
        } else {
            globalHotkeyManager.unregister()
        }
    }
}
