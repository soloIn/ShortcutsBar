import XCTest
@testable import ShortcutsBarCore

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testSpinnerViewStateTransitions() {
        let view = ScriptMonitorSpinnerView(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        XCTAssertEqual(view.currentState, .idle)

        view.updateState(.running(taskCount: 1))
        XCTAssertEqual(view.currentState, .running(taskCount: 1))

        view.updateState(.running(taskCount: 4))
        XCTAssertEqual(view.currentState, .running(taskCount: 4))

        view.updateState(.successFlash)
        XCTAssertEqual(view.currentState, .successFlash)

        view.updateState(.idle)
        XCTAssertEqual(view.currentState, .idle)
    }

    @MainActor
    func testStatusItemControllerInitialization() {
        let manager = ProcessManager()
        let controller = StatusItemController(processManager: manager)
        XCTAssertNil(controller.menu)

        let menu = NSMenu()
        controller.menu = menu
        XCTAssertEqual(controller.menu, menu)
    }
}
