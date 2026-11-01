import XCTest
@testable import ShortcutsBarCore

final class FloatingPanelControllerTests: XCTestCase {
    @MainActor
    func testFloatingPanelProperties() {
        let panel = FloatingPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 400))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.level, .floating)
    }

    @MainActor
    func testDockedFrameCalculation() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.panel.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        let mockScreen = NSScreen.main ?? NSScreen.screens.first!
        let frame = controller.calculateDockedFrame(for: nil, on: mockScreen)

        XCTAssertEqual(frame.width, FloatingPanelController.panelWidth)
        XCTAssertEqual(frame.height, FloatingPanelController.defaultPanelHeight)
        XCTAssertTrue(frame.minX >= mockScreen.visibleFrame.minX)
        XCTAssertTrue(frame.maxX <= mockScreen.visibleFrame.maxX)
    }

    @MainActor
    func testShowHideToggleLifecycle() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.panel.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        XCTAssertFalse(controller.isPresented)

        controller.show()
        XCTAssertTrue(controller.isPresented)

        controller.hide()
        XCTAssertFalse(controller.isPresented)

        controller.toggle()
        XCTAssertTrue(controller.isPresented)

        controller.toggle()
        XCTAssertFalse(controller.isPresented)
    }

    @MainActor
    func testPanelMoveAndSnap() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.panel.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)
        controller.show()

        let initialOrigin = controller.panel.frame.origin

        // Move inward by -50, -50 (avoiding right edge clamp)
        controller.movePanel(by: CGPoint(x: -50, y: -50))
        controller.handleDragEnd()
        XCTAssertNotNil(store.panelOrigin)
        XCTAssertEqual(controller.panel.frame.origin.x, initialOrigin.x - 50, accuracy: 1.0)
        XCTAssertEqual(controller.panel.frame.origin.y, initialOrigin.y - 50, accuracy: 1.0)

        // Reset to docked without animation for synchronous test assertion
        controller.resetToDocked(animate: false)
        XCTAssertNil(store.panelOrigin)
        let dockedOrigin = controller.panel.frame.origin
        XCTAssertEqual(dockedOrigin.x, initialOrigin.x, accuracy: 1.0)

        // Move within magnetic threshold (15pt inward) and handleDragEnd -> snaps back
        controller.movePanel(by: CGPoint(x: -15, y: -10))
        controller.handleDragEnd()
        // Should have snapped and cleared panelOrigin
        XCTAssertNil(store.panelOrigin)
        XCTAssertEqual(controller.panel.frame.origin.x, dockedOrigin.x, accuracy: 1.0)
    }

    @MainActor
    func testPinningUpdatesWindowLevel() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.panel.\(UUID().uuidString)")!)
        let controller = FloatingPanelController(preferencesStore: store)

        XCTAssertFalse(store.isPinned)
        XCTAssertEqual(controller.panel.level, .floating)

        store.isPinned = true
        controller.updateWindowLevel(isPinned: true)
        XCTAssertEqual(controller.panel.level, .floating)
        XCTAssertTrue(controller.panel.collectionBehavior.contains(.canJoinAllSpaces))

        store.isPinned = false
        controller.updateWindowLevel(isPinned: false)
        XCTAssertEqual(controller.panel.level, .floating)
    }
}
