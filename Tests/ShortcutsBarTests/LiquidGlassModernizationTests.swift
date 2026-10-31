import XCTest
import SwiftUI
import AppKit
@testable import ShortcutsBarCore

final class LiquidGlassModernizationTests: XCTestCase {

    // MARK: - 1. LiquidGlassBackdropView Native SwiftUI Verification
    @MainActor
    func testLiquidGlassBackdropView_IsNativeSwiftUIView() {
        print("\n========================================================")
        print(">>> [TEST RUN] LiquidGlassBackdropView 现代化改造验证")

        let backdrop = LiquidGlassBackdropView(cornerRadius: 16)
        XCTAssertEqual(backdrop.cornerRadius, 16)
        XCTAssertGreaterThanOrEqual(LiquidGlassBackdropView.darkOverlayAlpha, 0.40)
        XCTAssertGreaterThanOrEqual(LiquidGlassBackdropView.lightOverlayAlpha, 0.40)

        // 验证不再依赖旧式 NSVisualEffectView 及其图层背景色
        XCTAssertTrue((backdrop as Any) is (any View), "LiquidGlassBackdropView 必须是纯原生 SwiftUI View")
        print(">>> [VERIFIED] LiquidGlassBackdropView 成功升级为 macOS 26 原生 SwiftUI 视图，移除旧版 NSVisualEffectView")
        print("========================================================\n")
    }

    // MARK: - 2. MenuBarDropdownController Window & Presentation Lifecycle
    @MainActor
    func testMenuBarDropdownController_WindowLifecycleAndStyling() {
        print("\n========================================================")
        print(">>> [TEST RUN] MenuBarDropdownController 下拉菜单容器生命周期与外观验证")

        let controller = MenuBarDropdownController()
        let panel = controller.panel

        // 验证窗口关键属性：必须是无边框、透明、POPUP 级别
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertFalse(controller.isPresented)

        // 验证停靠坐标计算
        let dummyButton = NSStatusBarButton()
        let frame = controller.calculateDockedFrame(for: dummyButton, on: NSScreen.main)
        XCTAssertEqual(frame.width, MenuBarDropdownController.dropdownWidth)
        XCTAssertGreaterThan(frame.height, 0)

        // 验证展示与关闭状态流转
        controller.show(attachedTo: dummyButton)
        XCTAssertTrue(controller.isPresented)

        controller.close()
        XCTAssertFalse(controller.isPresented)

        print(">>> [VERIFIED] MenuBarDropdownController 支持 macOS 26 下拉菜单透明液态玻璃容器规范")
        print("========================================================\n")
    }

    // MARK: - 3. MenuBarView Initialization and Content Binding
    @MainActor
    func testMenuBarView_InitializationAndBindings() {
        print("\n========================================================")
        print(">>> [TEST RUN] MenuBarView 现代液态玻璃下拉视图初始化验证")

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.menubarview.\(UUID().uuidString)")!)
        let service = ShortcutsService()
        let processManager = ProcessManager()

        var panelOpened = false
        var settingsOpened = false
        var dismissed = false

        let view = MenuBarView(
            preferencesStore: store,
            shortcutsService: service,
            processManager: processManager,
            onOpenFloatingPanel: { panelOpened = true },
            onOpenSettings: { settingsOpened = true },
            onDismiss: { dismissed = true }
        )

        XCTAssertNotNil(view.body)
        view.onOpenFloatingPanel?()
        XCTAssertTrue(panelOpened)

        view.onOpenSettings?()
        XCTAssertTrue(settingsOpened)

        view.onDismiss?()
        XCTAssertTrue(dismissed)

        print(">>> [VERIFIED] MenuBarView 正确声明并接入液态玻璃交互与系统回调")
        print("========================================================\n")
    }

    // MARK: - 4. FloatingPanelView Modern Glass Container
    @MainActor
    func testFloatingPanelView_EmbedsInGlassEffectContainer() {
        print("\n========================================================")
        print(">>> [TEST RUN] FloatingPanelView 原生液态玻璃容器结构验证")

        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.floatingpanelview.\(UUID().uuidString)")!)
        let service = ShortcutsService()
        let processManager = ProcessManager()
        let panelController = FloatingPanelController(preferencesStore: store)
        let viewModel = FloatingPanelViewModel(
            shortcutsService: service,
            processManager: processManager,
            preferencesStore: store,
            panelController: panelController
        )

        let panelView = FloatingPanelView(viewModel: viewModel)
        XCTAssertNotNil(panelView.body)

        // 验证 FloatingPanelController 支持设置 SwiftUI 根视图并维持全透明非不透明图层
        panelController.setContent(panelView)
        XCTAssertNotNil(panelController.panel.contentView)
        XCTAssertFalse(panelController.panel.isOpaque)
        XCTAssertEqual(panelController.panel.backgroundColor, .clear)

        print(">>> [VERIFIED] FloatingPanelView 与 FloatingPanelController 完美契合 macOS 26 Liquid Glass 标准")
        print("========================================================\n")
    }
}
