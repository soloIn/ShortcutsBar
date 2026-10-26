import XCTest
@testable import ShortcutsBarCore

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesStorage() {
        let suiteName = "test.shortcutsbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PreferencesStore(defaults: defaults)

        // Default
        XCTAssertEqual(store.folderScope, .leaf(folderName: "Menu Bar"))
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
