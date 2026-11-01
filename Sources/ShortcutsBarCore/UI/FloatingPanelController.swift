import AppKit
import SwiftUI

@MainActor
public final class FloatingPanelController: NSWindowController, NSWindowDelegate {
    public var panel: FloatingPanel {
        return window as! FloatingPanel
    }
    public let preferencesStore: PreferencesStore
    public weak var statusButton: NSStatusBarButton?
    public var screenFinder: ((CGPoint) -> NSScreen?)?

    public private(set) var isPresented: Bool = false
    public var onPresentationChanged: ((Bool) -> Void)?

    public static let panelWidth: CGFloat = 340
    public static let defaultPanelHeight: CGFloat = 460
    public static let magneticSnapThreshold: CGFloat = 30.0

    public init(preferencesStore: PreferencesStore = .shared, initialRect: NSRect? = nil) {
        self.preferencesStore = preferencesStore
        let rect = initialRect ?? NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.defaultPanelHeight)
        let panel = FloatingPanel(contentRect: rect)
        super.init(window: panel)
        panel.delegate = self
        panel.isPinned = preferencesStore.isPinned
        panel.updateWindowLevel()
        panel.onCloseCallback = { [weak self] in
            self?.isPresented = false
            self?.onPresentationChanged?(false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
    }

    public func updateWindowLevel(isPinned: Bool) {
        panel.isPinned = isPinned
    }

    public func calculateDockedFrame(for button: NSStatusBarButton?, on screen: NSScreen?) -> NSRect {
        // 💡 仅当状态栏按钮及其窗口有效排版（frame.height > 0 且 bounds.width > 0）时，才判定为有效 Anchor；
        // 当 StatusItem 为空闲隐藏态 (isVisible == false) 时，button.window 未在屏幕排版，height 为 0，
        // 若直接使用 convertToScreen 会将浮窗错误停靠在屏幕左下角 (0, 0)。此时回退至当前屏幕右上角安全区域。
        let isButtonUsable: Bool = {
            guard let btn = button, let btnWindow = btn.window else { return false }
            if btnWindow.frame.height <= 0 || btn.bounds.width <= 0 {
                return false
            }
            if btnWindow.frame.origin == .zero && btnWindow.frame.size.height < 10 {
                return false
            }
            return true
        }()

        let anchorScreen: NSScreen? = {
            if isButtonUsable, let btnScreen = button?.window?.screen {
                return btnScreen
            }
            return screen ?? NSScreen.screens.first(where: { NSPointInRect(NSEvent.mouseLocation, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens.first
        }()
        let screenRect = anchorScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let width = Self.panelWidth
        let height = panel.frame.height > 0 ? panel.frame.height : Self.defaultPanelHeight

        var targetX: CGFloat
        var targetY: CGFloat

        if isButtonUsable, let btn = button, let btnWindow = btn.window {
            let btnScreenRect = btnWindow.convertToScreen(btn.bounds)
            targetX = btnScreenRect.midX - (width / 2)
            targetY = btnScreenRect.minY - height - 4
        } else {
            targetX = screenRect.maxX - width - 16
            targetY = screenRect.maxY - height - 8
        }

        // Clamp horizontally within screen
        if targetX < screenRect.minX + 8 {
            targetX = screenRect.minX + 8
        } else if targetX + width > screenRect.maxX - 8 {
            targetX = screenRect.maxX - width - 8
        }

        // Clamp vertically within screen visibleFrame (respecting Dock & MenuBar)
        if targetY < screenRect.minY + 8 {
            targetY = screenRect.minY + 8
        } else if targetY + height > screenRect.maxY - 4 {
            targetY = screenRect.maxY - height - 4
        }

        return NSRect(x: targetX, y: targetY, width: width, height: height)
    }

    public func show(attachedTo button: NSStatusBarButton? = nil) {
        if let btn = button {
            self.statusButton = btn
        }

        // 💡 优先获取当前鼠标光标所在屏幕，保障多显示器环境下的自然呼出
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) })
            ?? self.statusButton?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let dockedRect = calculateDockedFrame(for: self.statusButton, on: targetScreen)

        if let savedOrigin = preferencesStore.panelOrigin {
            let containingScreen = screenFinder?(savedOrigin)
                ?? NSScreen.screens.first(where: { NSPointInRect(savedOrigin, $0.frame) })
                ?? targetScreen
            if let screen = containingScreen {
                let screenVisible = screen.visibleFrame
                let clampedX = min(max(savedOrigin.x, screenVisible.minX), screenVisible.maxX - Self.panelWidth)
                let clampedY = min(max(savedOrigin.y, screenVisible.minY), screenVisible.maxY - Self.defaultPanelHeight)
                panel.setFrame(NSRect(x: clampedX, y: clampedY, width: Self.panelWidth, height: Self.defaultPanelHeight), display: true)
            } else {
                panel.setFrame(NSRect(origin: savedOrigin, size: CGSize(width: Self.panelWidth, height: Self.defaultPanelHeight)), display: true)
            }
        } else {
            panel.setFrame(dockedRect, display: true)
        }

        panel.cancelClosing()
        panel.isPinned = preferencesStore.isPinned
        panel.updateWindowLevel()
        panel.updateCollectionBehavior()
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isPresented = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
        onPresentationChanged?(true)
    }

    public func hide() {
        panel.orderOutWithAnimation()
        isPresented = false
        onPresentationChanged?(false)
    }

    public func toggle(attachedTo button: NSStatusBarButton? = nil) {
        if isPresented {
            hide()
        } else {
            show(attachedTo: button)
        }
    }

    public var currentTargetScreen: NSScreen? {
        panel.screen ?? statusButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    public func movePanel(by delta: CGPoint) {
        var currentOrigin = panel.frame.origin
        currentOrigin.x += delta.x
        currentOrigin.y += delta.y

        let targetScreen = currentTargetScreen
        let screenVisible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Clamp to target display
        currentOrigin.x = min(max(currentOrigin.x, screenVisible.minX), screenVisible.maxX - panel.frame.width)
        currentOrigin.y = min(max(currentOrigin.y, screenVisible.minY), screenVisible.maxY - panel.frame.height)

        panel.setFrameOrigin(currentOrigin)
    }

    public func handleDragEnd() {
        let targetScreen = currentTargetScreen
        let dockedFrame = calculateDockedFrame(for: statusButton, on: targetScreen)
        var currentOrigin = panel.frame.origin

        // 💡 拖拽松开时实施屏幕可视区域边界保护，防止窗口被拖出屏幕外后持久化保存为死坐标
        if let screenVisible = targetScreen?.visibleFrame {
            currentOrigin.x = min(max(currentOrigin.x, screenVisible.minX), screenVisible.maxX - panel.frame.width)
            currentOrigin.y = min(max(currentOrigin.y, screenVisible.minY), screenVisible.maxY - panel.frame.height)
            panel.setFrameOrigin(currentOrigin)
        }

        let distance = hypot(currentOrigin.x - dockedFrame.origin.x, currentOrigin.y - dockedFrame.origin.y)
        if distance <= Self.magneticSnapThreshold {
            resetToDocked(animate: true)
        } else {
            preferencesStore.panelOrigin = currentOrigin
        }
    }

    public func resetToDocked(animate: Bool = false) {
        let targetScreen = currentTargetScreen
        let dockedFrame = calculateDockedFrame(for: statusButton, on: targetScreen)
        panel.setFrame(dockedFrame, display: true, animate: animate)
        preferencesStore.panelOrigin = nil
    }
}
