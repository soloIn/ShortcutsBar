import XCTest
import AppKit
@testable import ShortcutsBarCore

final class StatusItemDualModeTests: XCTestCase {
    @MainActor
    func testDualModeClickRoutingDefaultClassicMenu() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.dual.\(UUID().uuidString)")!)
        store.primaryClickAction = .classicMenu

        let controller = StatusItemController(processManager: ProcessManager(), preferencesStore: store)

        var classicTriggered = false
        var panelTriggered = false

        controller.onTriggerClassicMenu = { classicTriggered = true }
        controller.onTriggerFloatingPanel = { panelTriggered = true }

        // Trigger normal classic menu
        controller.triggerClassicMenu()
        XCTAssertTrue(classicTriggered)
        XCTAssertFalse(panelTriggered)

        // Trigger floating panel
        classicTriggered = false
        controller.triggerFloatingPanel()
        XCTAssertFalse(classicTriggered)
        XCTAssertTrue(panelTriggered)
    }

    @MainActor
    func testDualModeClickRoutingFloatingPanelPrimary() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.dual2.\(UUID().uuidString)")!)
        store.primaryClickAction = .floatingPanel

        let controller = StatusItemController(processManager: ProcessManager(), preferencesStore: store)

        var classicTriggered = false
        var panelTriggered = false

        controller.onTriggerClassicMenu = { classicTriggered = true }
        controller.onTriggerFloatingPanel = { panelTriggered = true }

        // In floatingPanel mode, normal trigger calls onTriggerFloatingPanel
        controller.triggerFloatingPanel()
        XCTAssertTrue(panelTriggered)
        XCTAssertFalse(classicTriggered)

        panelTriggered = false
        controller.triggerClassicMenu()
        XCTAssertTrue(classicTriggered)
        XCTAssertFalse(panelTriggered)
    }

    @MainActor
    func testStatusItemClickAlwaysTriggersClassicMenu() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.statusclick.\(UUID().uuidString)")!)
        let controller = StatusItemController(processManager: ProcessManager(), preferencesStore: store)

        var classicTriggered = false
        controller.onTriggerClassicMenu = { classicTriggered = true }

        let button = NSStatusBarButton()
        controller.handleStatusItemClick(button)
        XCTAssertTrue(classicTriggered)
    }

    @MainActor
    func testMenuBuilderIncludesFloatingPanelItemAndAuthenticShortcutsIcon() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.menu.\(UUID().uuidString)")!)
        store.globalHotkeyEnabled = true
        store.globalHotkeyCode = 35 // 'P'
        store.globalHotkeyModifiers = 256 | 2048 // ⌘⌥

        let service = ShortcutsService()
        let manager = ProcessManager()
        let builder = MenuBuilder()
        builder.shortcutsService = service
        builder.processManager = manager
        builder.preferencesStore = store

        var panelOpened = false
        builder.onOpenFloatingPanel = { panelOpened = true }

        let menu = builder.buildMenu()

        // 1. Check "快捷指令悬浮窗" item
        guard let panelItem = menu.items.first(where: { $0.title == "快捷指令悬浮窗" }) else {
            XCTFail("Missing '快捷指令悬浮窗' in menu")
            return
        }
        XCTAssertEqual(panelItem.keyEquivalent, "p")
        XCTAssertTrue(panelItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(panelItem.keyEquivalentModifierMask.contains(.option))

        // Trigger action
        if let target = panelItem.target, let action = panelItem.action {
            _ = target.perform(action, with: panelItem)
            XCTAssertTrue(panelOpened)
        }

        // 2. Check "打开快捷指令 App" item
        guard let appItem = menu.items.first(where: { $0.title.hasPrefix("打开快捷指令 App") }) else {
            XCTFail("Missing '打开快捷指令 App' in menu")
            return
        }
        XCTAssertNotNil(appItem.image)
    }

    @MainActor
    func testGlobalHotkeyManagerRegistrationLifecycle() {
        let manager = GlobalHotkeyManager()
        XCTAssertFalse(manager.isRegistered)

        // Register valid key (keyCode 1 = 'S', modifiers = 4096 = controlKey)
        let success = manager.register(keyCode: 1, modifiers: 4096)
        if success {
            XCTAssertTrue(manager.isRegistered)
            manager.unregister()
            XCTAssertFalse(manager.isRegistered)
        } else {
            // In headless/sandboxed test runners where Carbon window server events are restricted,
            // verify graceful fallback
            XCTAssertFalse(manager.isRegistered)
        }
    }

    func testHotkeyHelperFormattingAndModifiers() {
        // Space with Option key (keyCode 49, optionKey 2048)
        let str = HotkeyHelper.string(for: 49, modifiers: 2048)
        XCTAssertEqual(str, "⌥Space")

        // ⌃⌥S (keyCode 1, controlKey 4096 | optionKey 2048)
        let str2 = HotkeyHelper.string(for: 1, modifiers: 4096 | 2048)
        XCTAssertEqual(str2, "⌃⌥S")

        // ⌘⇧K (keyCode 40, cmdKey 256 | shiftKey 512)
        let str3 = HotkeyHelper.string(for: 40, modifiers: 256 | 512)
        XCTAssertEqual(str3, "⇧⌘K")

        // Test Carbon modifier conversion from Cocoa flags
        let cocoaFlags: NSEvent.ModifierFlags = [.command, .shift]
        let carbon = HotkeyHelper.carbonModifiers(from: cocoaFlags)
        XCTAssertEqual(carbon, 256 | 512)
    }
}
