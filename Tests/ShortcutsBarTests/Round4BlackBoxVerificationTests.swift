import XCTest
import AppKit
@testable import ShortcutsBarCore

@MainActor
final class Round4BlackBoxVerificationTests: XCTestCase {

    // MARK: - Fix 1: 菜单栏标准组件与图标激活高亮胶囊/深浅色适配
    func testFix1_MenuBarStatusItemStandardComponentAndActiveCapsuleHighlight() {
        print(">>> [TEST RUN] Fix 1: 菜单栏标准组件与激活胶囊高亮验证")

        let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "test_menubar_\(UUID().uuidString)")!)
        let processManager = ProcessManager()
        let customStatusItem = NSStatusBar.system.statusItem(withLength: 28)
        defer { NSStatusBar.system.removeStatusItem(customStatusItem) }

        let controller = StatusItemController(
            processManager: processManager,
            preferencesStore: prefs,
            statusItem: customStatusItem
        )

        // 1. 在现代 SwiftUI 解耦架构中：customStatusItem.menu 恒为 nil，避免 AppKit 模态菜单劫持
        prefs.primaryClickAction = .classicMenu
        controller.updateMenuBinding()
        XCTAssertNil(
            customStatusItem.menu,
            "【验证通过】在现代 SwiftUI 解耦架构中，customStatusItem.menu 恒为 nil，杜绝 AppKit 模态菜单劫持"
        )
        XCTAssertNotNil(customStatusItem.button?.action)

        // 2. 点击事件由 onTriggerDropdown 顺畅响应
        var dropdownTriggered = false
        controller.onTriggerDropdown = {
            dropdownTriggered = true
        }
        controller.triggerClassicMenu()
        XCTAssertTrue(dropdownTriggered, "【验证通过】点击菜单项由 onTriggerDropdown 顺畅响应，不走阻塞式 NSMenu")

        // 3. 高亮由 StatusItemController setHighlighted 控制
        controller.setHighlighted(true)
        XCTAssertTrue(
            customStatusItem.button?.isHighlighted == true,
            "【验证通过】展开期间，statusItem.button.isHighlighted 必须为 true，呈现原生微微激活的高亮胶囊背景"
        )

        controller.setHighlighted(false)
        XCTAssertFalse(
            customStatusItem.button?.isHighlighted == true,
            "【验证通过】关闭后，statusItem.button.isHighlighted 必须为 false，恢复常态"
        )

        // 4. 切换至 .floatingPanel 模式，customStatusItem.menu 同样恒为 nil
        prefs.primaryClickAction = .floatingPanel
        controller.updateMenuBinding()
        XCTAssertNil(
            customStatusItem.menu,
            "【验证通过】primaryClickAction == .floatingPanel 时，statusItem.menu 同样恒为 nil 以免劫持单击唤起浮窗事件"
        )
        XCTAssertNotNil(customStatusItem.button?.action)

        // 5. 浮窗唤醒时高亮联动
        let panelController = FloatingPanelController(preferencesStore: prefs)
        panelController.onPresentationChanged = { isPresented in
            controller.setHighlighted(isPresented)
        }

        panelController.show(attachedTo: customStatusItem.button)
        XCTAssertTrue(
            customStatusItem.button?.isHighlighted == true,
            "【验证通过】浮窗展开期间，statusItem.button.isHighlighted 保持激活态，自动适配浅色/深色模式"
        )

        panelController.hide()
        XCTAssertFalse(
            customStatusItem.button?.isHighlighted == true,
            "【验证通过】浮窗收起后，statusItem.button.isHighlighted 恢复初始状态"
        )
    }

    // MARK: - Fix 2: 快捷指令 SF Symbol 元数据映射与杜绝 [?] 缺失字符方框
    func testFix2_ShortcutSFMetadataMappingAndZeroQuestionMarkGlyphs() {
        print(">>> [TEST RUN] Fix 2: 快捷指令 SF Symbol 元数据映射完整性验证")

        let renderer = ShortcutIconRenderer.shared

        // 用户真机 Shortcuts.sqlite 中出现的核心快捷指令 glyph 与对应颜色
        let realWorldItems: [(name: String, glyph: Int, color: Int64, expectedSymbol: String)] = [
            ("图库壁纸", 61507, 431817727, "livephoto"),
            ("收藏壁纸", 61459, 431817727, "photo.fill.on.rectangle.fill"),
            ("pdf保存到相册", 61440, 1440408063, "square.2.layers.3d.fill"),
            ("照片添加时间文字水印", 59791, 3980825855, "richtext.page.fill"),
            ("拍摄 GIF", 59682, -12365313, "camera.fill"),
            ("影片轉 GIF", 59402, 463140863, "video.fill"),
            ("定时切换壁纸", 59844, 431817727, "stopwatch.fill"),
            ("网络切换", 59662, 255, "chart.bar.fill"),
            ("记账ai-openai", 59514, 4271458815, "yensign")
        ]

        for item in realWorldItems {
            let symbol = ShortcutsGlyphMapper.symbolName(for: item.glyph)
            XCTAssertEqual(
                symbol,
                item.expectedSymbol,
                "【元数据验证】glyph: \(item.glyph) 必须准确匹配系统 SF Symbol: \(item.expectedSymbol)"
            )

            let shortcut = ShortcutItem(
                name: item.name,
                folderName: nil,
                glyph: item.glyph,
                colorValue: item.color,
                actionCount: 5
            )
            let icon = renderer.icon(for: shortcut, size: 24)
            XCTAssertEqual(icon.size.width, 24)
            XCTAssertEqual(icon.size.height, 24)

            // 验证生成的系统矢量图标存在并且有效
            let systemSymbol = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(
                systemSymbol,
                "【HIG 规范】SF Symbol 名称「\(symbol)」在 macOS 系统中必须真实有效存在"
            )
        }

        print(">>> [Fix 2 结果] 【验证通过】所有快捷指令均通过真实元数据精准渲染为官方 SF Symbol，彻底杜绝 [?] 方框！")
    }

    // MARK: - Fix 3: 搜索框获得焦点时 Tab 键流与 macOS 原生快捷键无冲突切换文件夹
    func testFix3_FolderTabKeyboardNavigationUnderFocusedSearchField() {
        print(">>> [TEST RUN] Fix 3: 搜索框聚焦下 Tab / ⌃Tab / ⌘⇧] 文件夹无冲突切换验证")

        final class KeyablePanel: NSPanel {
            override var isKeyWindow: Bool { true }
        }

        let keyablePanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "test.round4.fix3.\(UUID().uuidString)")!)
        store.folderScope = .root
        let viewModel = FloatingPanelViewModel(
            shortcutsService: ShortcutsService(),
            processManager: ProcessManager(),
            preferencesStore: store
        )
        let interceptor = PanelKeyInterceptor(panel: keyablePanel, viewModel: viewModel, panelController: nil)

        viewModel.availableFolders = ["全部", "工作", "生活", "工具"]
        viewModel.selectedFolder = "全部"

        // 模拟搜索文本框获得焦点
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        keyablePanel.contentView?.addSubview(textView)
        keyablePanel.makeKeyAndOrderFront(nil)
        keyablePanel.makeFirstResponder(textView)
        XCTAssertTrue(keyablePanel.firstResponder is NSTextView, "文本输入框正常获得焦点")

        // 1. 验证按下 Tab (keyCode 48, 无修饰符) 顺次切换文件夹
        let tabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: keyablePanel.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        let handledTab = interceptor.handleKeyEvent(tabEvent)
        XCTAssertTrue(handledTab, "【验证通过】搜索框聚焦下单按 Tab 键成功消费并切换文件夹")
        XCTAssertEqual(viewModel.selectedFolder, "工作", "Tab 顺次切换至「工作」")

        // 2. 验证按下 Shift+Tab (keyCode 48, .shift) 逆向切换文件夹
        let shiftTabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: keyablePanel.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
        let handledShiftTab = interceptor.handleKeyEvent(shiftTabEvent)
        XCTAssertTrue(handledShiftTab, "【验证通过】Shift+Tab 成功消费并逆向切换")
        XCTAssertEqual(viewModel.selectedFolder, "全部", "Shift+Tab 逆向切换回「全部」")

        // 3. 验证 Control+Tab (keyCode 48, .control) 系统级快捷键切换
        let ctrlTabEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: keyablePanel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 48
        )!
        let handledCtrlTab = interceptor.handleKeyEvent(ctrlTabEvent)
        XCTAssertTrue(handledCtrlTab, "【验证通过】Control+Tab 成功切换")
        XCTAssertEqual(viewModel.selectedFolder, "工作", "Control+Tab 切换至「工作」")

        // 4. 验证 ⌘⇧] (keyCode 30, modifiers: [.command, .shift]) HIG 标准标签页切换
        let cmdShiftRightBracketEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: keyablePanel.windowNumber,
            context: nil,
            characters: "}",
            charactersIgnoringModifiers: "]",
            isARepeat: false,
            keyCode: 30
        )!
        let handledCmdShiftRight = interceptor.handleKeyEvent(cmdShiftRightBracketEvent)
        XCTAssertTrue(handledCmdShiftRight, "【验证通过】⌘⇧] 成功切换")
        XCTAssertEqual(viewModel.selectedFolder, "生活", "⌘⇧] 切换至「生活」")

        // 5. 验证 ⌘← / ⌘→ 在文本输入框内仍然放行给系统光标跳跃 (保持既有测试契约)
        let cmdRightArrowEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: keyablePanel.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        let handledCmdRight = interceptor.handleKeyEvent(cmdRightArrowEvent)
        XCTAssertFalse(handledCmdRight, "【验证通过】文本输入框内 ⌘→ 未被拦截，保留 moveToEndOfLine: 原生光标导航")
        XCTAssertEqual(viewModel.selectedFolder, "生活", "文件夹 Tab 保持不变")

        print(">>> [Fix 3 结果] 【验证通过】在搜索框默认聚焦下，Tab / ⌃Tab / ⌘⇧] 均可极速切换文件夹，且光标跳转完全不受影响！")
    }
}
