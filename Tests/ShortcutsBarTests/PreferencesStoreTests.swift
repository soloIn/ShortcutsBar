import XCTest
@testable import ShortcutsBarCore

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesStorage() {
        let suiteName = "test.shortcutsbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(defaults: defaults)

        // Default
        let expectedDefaultFolder = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? "快捷指令" : "Menu Bar"
        XCTAssertEqual(store.folderScope, .leaf(folderName: expectedDefaultFolder))
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(store.notifyOnFailure)

        // Change to root
        store.folderScope = .root
        XCTAssertEqual(store.folderScope, .root)

        // Change to specific leaf
        store.folderScope = .leaf(folderName: "Production")
        XCTAssertEqual(store.folderScope, .leaf(folderName: "Production"))

        // Change flags
        store.launchAtLogin = true
        XCTAssertTrue(store.launchAtLogin)

        store.notifyOnFailure = true
        XCTAssertTrue(store.notifyOnFailure)

        // Primary click action
        XCTAssertEqual(store.primaryClickAction, .classicMenu)
        store.primaryClickAction = .floatingPanel
        XCTAssertEqual(store.primaryClickAction, .floatingPanel)

        // Panel origin
        XCTAssertNil(store.panelOrigin)
        store.panelOrigin = CGPoint(x: 250, y: 350)
        XCTAssertEqual(store.panelOrigin?.x, 250)
        XCTAssertEqual(store.panelOrigin?.y, 350)
        store.panelOrigin = nil
        XCTAssertNil(store.panelOrigin)

        // Pinning
        XCTAssertFalse(store.isPinned)
        store.isPinned = true
        XCTAssertTrue(store.isPinned)

        // Custom sort orders
        XCTAssertEqual(store.getCustomOrder(for: "Work"), [])
        store.setCustomOrder(["TaskB", "TaskA"], for: "Work")
        XCTAssertEqual(store.getCustomOrder(for: "Work"), ["TaskB", "TaskA"])

        // Global hotkey
        XCTAssertFalse(store.globalHotkeyEnabled)
        store.globalHotkeyEnabled = true
        XCTAssertTrue(store.globalHotkeyEnabled)

        XCTAssertNil(store.globalHotkeyCode)
        store.globalHotkeyCode = 49 // Space
        XCTAssertEqual(store.globalHotkeyCode, 49)

        XCTAssertNil(store.globalHotkeyModifiers)
        store.globalHotkeyModifiers = 2048 // Option
        XCTAssertEqual(store.globalHotkeyModifiers, 2048)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testSettingsViewModelFolderLoading() async throws {
        let suiteName = "test.shortcutsbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(defaults: defaults)

        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Alpha\nBeta"
        mock.responses["list --folder-name Alpha"] = "A1\nA2"
        mock.responses["list --folder-name Beta"] = "B1"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let vm = SettingsViewModel(preferencesStore: store, shortcutsService: service)
        XCTAssertEqual(vm.availableFolders, ["Alpha", "Beta"])
        XCTAssertEqual(vm.totalShortcutsCount, 3)

        // Switch to root via viewModel
        vm.selectedScopeTag = "__ROOT__"
        XCTAssertEqual(store.folderScope, .root)

        // Switch to Alpha
        vm.selectedScopeTag = "Alpha"
        XCTAssertEqual(store.folderScope, .leaf(folderName: "Alpha"))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
