import XCTest
import AppKit
@testable import ShortcutsBarCore

final class PanelKeyInterceptorTests: XCTestCase {
    @MainActor
    func testKeyInterceptions() async throws {
        let mock = MockShortcutsCLIExecutor()
        mock.responses["list --folders"] = "Alpha"
        mock.responses["list --folder-name Alpha"] = "Shortcut A\nShortcut B\nShortcut C"
        mock.responses["list --folder-name none"] = ""

        let service = ShortcutsService(executor: mock)
        try await service.refreshCache()

        let spawner = MockProcessSpawner()
        let processManager = ProcessManager(spawner: spawner)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.key.\(UUID().uuidString)")!)
        store.folderScope = .root
        let panelController = FloatingPanelController(preferencesStore: store)

        let vm = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        let interceptor = PanelKeyInterceptor(
            panel: panelController.panel,
            viewModel: vm,
            panelController: panelController
        )

        panelController.show()
        XCTAssertTrue(panelController.isPresented)
        XCTAssertEqual(vm.highlightedIndex, 0)

        // 1. Down Arrow (keyCode 125)
        let downEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        let handledDown = interceptor.handleKeyEvent(downEvent)
        XCTAssertTrue(handledDown)
        XCTAssertEqual(vm.highlightedIndex, 1)

        // 2. Up Arrow (keyCode 126)
        let upEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        let handledUp = interceptor.handleKeyEvent(upEvent)
        XCTAssertTrue(handledUp)
        XCTAssertEqual(vm.highlightedIndex, 0)

        // 3. Return (keyCode 36) -> executes item at index 0 ("Shortcut A")
        let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        let handledReturn = interceptor.handleKeyEvent(returnEvent)
        XCTAssertTrue(handledReturn)
        XCTAssertEqual(processManager.activeTasks.count, 1)
        XCTAssertEqual(processManager.activeTasks[0].shortcutName, "Shortcut A")

        // 4. Command + 2 (digit 2) -> executes item at index 1 ("Shortcut B")
        let cmd2Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19
        )!
        let handledCmd2 = interceptor.handleKeyEvent(cmd2Event)
        XCTAssertTrue(handledCmd2)
        XCTAssertEqual(processManager.activeTasks.count, 2)
        XCTAssertEqual(processManager.activeTasks[1].shortcutName, "Shortcut B")

        // 5. Escape with non-empty search text -> clears search
        vm.searchQuery = "test"
        let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!
        let handledEsc1 = interceptor.handleKeyEvent(escEvent)
        XCTAssertTrue(handledEsc1)
        XCTAssertEqual(vm.searchQuery, "")

        // 6. Escape with empty search text -> hides panel
        panelController.show()
        XCTAssertTrue(panelController.isPresented)
        let handledEsc2 = interceptor.handleKeyEvent(escEvent)
        XCTAssertTrue(handledEsc2)
        XCTAssertFalse(panelController.isPresented)

        // 7. Regular typing key "a" (keyCode 0) -> NOT consumed so NSTextField receives it
        let charAEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        let handledA = interceptor.handleKeyEvent(charAEvent)
        XCTAssertFalse(handledA)

        // 8. Command + Left Arrow (123) / Right Arrow (124) -> tab switching
        XCTAssertTrue(vm.availableFolders.contains("Alpha"))
        XCTAssertEqual(vm.selectedFolder, "全部")

        let cmdRightEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        let handledCmdRight = interceptor.handleKeyEvent(cmdRightEvent)
        XCTAssertTrue(handledCmdRight)
        XCTAssertEqual(vm.selectedFolder, "Alpha")

        let cmdLeftEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panelController.panel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!
        let handledCmdLeft = interceptor.handleKeyEvent(cmdLeftEvent)
        XCTAssertTrue(handledCmdLeft)
        XCTAssertEqual(vm.selectedFolder, "全部")
    }
}
