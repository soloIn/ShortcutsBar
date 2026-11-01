import XCTest
import AppKit
@testable import ShortcutsBarCore

@MainActor
final class AppDelegateLifecycleTests: XCTestCase {

    func testAppDelegateInitializationAndStartup() {
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate.shortcutsService)
        XCTAssertNotNil(delegate.processManager)
        XCTAssertNotNil(delegate.preferencesStore)
        XCTAssertNotNil(delegate.databaseWatcher)
        XCTAssertNotNil(delegate.globalHotkeyManager)

        // Simulate applicationDidFinishLaunching
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationDidFinishLaunching(notification)

        XCTAssertNotNil(delegate.statusItemController)
        XCTAssertNotNil(delegate.settingsWindowController)
        XCTAssertNotNil(delegate.floatingPanelController)
        XCTAssertNotNil(delegate.floatingPanelViewModel)
        XCTAssertNotNil(delegate.keyInterceptor)

        // Verify triggerFloatingPanel toggle lifecycle
        delegate.triggerFloatingPanel()
        XCTAssertTrue(delegate.floatingPanelController.isPresented)

        delegate.triggerFloatingPanel()
        XCTAssertFalse(delegate.floatingPanelController.isPresented)

        // Verify applicationWillTerminate teardown
        let terminateNotification = Notification(name: NSApplication.willTerminateNotification)
        delegate.applicationWillTerminate(terminateNotification)

        XCTAssertFalse(delegate.globalHotkeyManager.isRegistered)

        // Clean up test panel
        delegate.floatingPanelController.panel.orderOut(nil)
    }

    func testAppDelegateOpenSettings() {
        let delegate = AppDelegate()
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationDidFinishLaunching(notification)

        delegate.openSettings()
        XCTAssertNotNil(delegate.settingsWindowController.window)
        XCTAssertTrue(delegate.settingsWindowController.window?.isKeyWindow ?? false || delegate.settingsWindowController.window?.isVisible ?? false)

        delegate.settingsWindowController.window?.orderOut(nil)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
}
