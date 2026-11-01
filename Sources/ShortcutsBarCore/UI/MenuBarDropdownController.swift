import AppKit
import SwiftUI

@MainActor
@available(*, deprecated, message: "Replaced by direct MenuBarExtra and MenuBarView")
public final class MenuBarDropdownController: NSWindowController, NSWindowDelegate {
    public var panel: FloatingPanel {
        return window as! FloatingPanel
    }
    public private(set) var isPresented: Bool = false
    public weak var statusButton: NSStatusBarButton?

    public static let dropdownWidth: CGFloat = 280
    public static let defaultDropdownHeight: CGFloat = 360

    public init(initialRect: NSRect? = nil) {
        let rect = initialRect ?? NSRect(x: 0, y: 0, width: Self.dropdownWidth, height: Self.defaultDropdownHeight)
        let panel = FloatingPanel(contentRect: rect)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
        panel.delegate = self
        panel.onCloseCallback = { [weak self] in
            self?.isPresented = false
            self?.statusButton?.isHighlighted = false
        }
        panel.onCancelOperation = { [weak self] in
            self?.close()
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
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
    }

    public func calculateDockedFrame(for button: NSStatusBarButton?, on screen: NSScreen?) -> NSRect {
        let anchorScreen = button?.window?.screen ?? screen ?? NSScreen.screens.first ?? NSScreen.main
        let screenRect = anchorScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let width = Self.dropdownWidth
        let height = panel.frame.height > 0 ? panel.frame.height : Self.defaultDropdownHeight

        var targetX: CGFloat
        var targetY: CGFloat

        if let btn = button, let btnWindow = btn.window {
            let btnScreenRect = btnWindow.convertToScreen(btn.bounds)
            targetX = btnScreenRect.midX - (width / 2)
            targetY = btnScreenRect.minY - height - 4
        } else {
            targetX = screenRect.maxX - width - 16
            targetY = screenRect.maxY - height - 8
        }

        if targetX < screenRect.minX + 8 {
            targetX = screenRect.minX + 8
        } else if targetX + width > screenRect.maxX - 8 {
            targetX = screenRect.maxX - width - 8
        }

        if targetY < screenRect.minY + 8 {
            targetY = screenRect.minY + 8
        } else if targetY + height > screenRect.maxY - 4 {
            targetY = screenRect.maxY - height - 4
        }

        return NSRect(x: targetX, y: targetY, width: width, height: height)
    }

    public func updateHeightToFit() {
        guard let contentView = panel.contentView else { return }
        let fitting = contentView.fittingSize
        if fitting.height > 0 {
            let clampedHeight = min(max(fitting.height, 120), 520)
            let currentFrame = panel.frame
            if abs(currentFrame.height - clampedHeight) > 1 {
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.maxY - clampedHeight,
                    width: currentFrame.width,
                    height: clampedHeight
                )
                panel.setFrame(newFrame, display: true, animate: false)
            }
        }
    }

    public func show(attachedTo button: NSStatusBarButton? = nil) {
        if let btn = button {
            self.statusButton = btn
        }
        statusButton?.isHighlighted = true
        if let contentView = panel.contentView {
            let fitting = contentView.fittingSize
            if fitting.height > 0 {
                let clampedHeight = min(max(fitting.height, 120), 520)
                panel.setFrame(NSRect(x: panel.frame.origin.x, y: panel.frame.origin.y, width: Self.dropdownWidth, height: clampedHeight), display: false)
            }
        }
        let targetScreen = self.statusButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let targetFrame = calculateDockedFrame(for: self.statusButton, on: targetScreen)
        panel.setFrame(targetFrame, display: true)
        panel.cancelClosing()
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
        isPresented = true
    }

    override public func close() {
        statusButton?.isHighlighted = false
        guard isPresented else {
            super.close()
            return
        }
        isPresented = false
        panel.orderOutWithAnimation()
    }

    public func hide() {
        close()
    }

    public func toggle(attachedTo button: NSStatusBarButton? = nil) {
        if isPresented {
            close()
        } else {
            show(attachedTo: button)
        }
    }
}
