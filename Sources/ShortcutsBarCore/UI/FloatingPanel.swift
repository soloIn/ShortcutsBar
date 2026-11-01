import AppKit

@MainActor
public final class FloatingPanel: NSPanel {
    public var onCloseCallback: (() -> Void)?
    public var onCancelOperation: (() -> Void)?

    public var isPinned: Bool = false {
        didSet {
            updateCollectionBehavior()
            updateWindowLevel()
        }
    }

    private var isMenuTracking = false
    private var pendingClose = false
    public private(set) var isClosing = false
    private var desktopDismissalMonitor: Any?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hidesOnDeactivate = false
        self.appearance = nil

        // Strip standard buttons to prevent system controls overlapping Liquid Glass
        standardWindowButton(.closeButton)?.removeFromSuperview()
        standardWindowButton(.miniaturizeButton)?.removeFromSuperview()
        standardWindowButton(.zoomButton)?.removeFromSuperview()

        setupNotifications()
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        stopDesktopDismissalMonitor()
    }

    public var isPopoverPresented: Bool = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func updateWindowLevel() {
        self.level = .floating
    }

    public func updateCollectionBehavior() {
        if isPinned {
            self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            self.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        // 💡 监听应用失活，覆盖点击空白桌面导致 Finder 激活但未产生 keyWindow 的场景
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidResignActive() {
        Task { @MainActor [weak self] in
            guard let self = self, self.shouldAutoHide else { return }
            self.closeWithAnimation()
        }
    }

    @objc private func handleMenuDidBeginTracking() {
        isMenuTracking = true
        pendingClose = false
    }

    @objc private func handleMenuDidEndTracking() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isMenuTracking = false
            self.checkAndHideIfNeeded()
        }
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if (childWindows?.contains(closingWindow) ?? false) || attachedSheet == closingWindow {
            Task { @MainActor [weak self] in
                self?.checkAndHideIfNeeded()
            }
        }
    }

    public var shouldAutoHide: Bool {
        if isPinned || isKeyWindow || attachedSheet != nil || isMenuTracking || isPopoverPresented || NSApp.modalWindow != nil {
            return false
        }
        if let childWindows = childWindows, !childWindows.isEmpty {
            return false
        }
        if let keyWin = NSApp.keyWindow {
            if keyWin == self {
                if isKeyWindow { return false }
            } else if keyWin.parent == self || (childWindows?.contains(keyWin) ?? false) {
                return false
            }
            let className = String(describing: type(of: keyWin))
            if className.contains("Popover") && (keyWin.parent == self || keyWin.level == self.level) {
                return false
            }
        }
        return true
    }

    public override func resignKey() {
        super.resignKey()
        if isPinned || attachedSheet != nil || !(childWindows?.isEmpty ?? true) || isMenuTracking || isPopoverPresented || isClosing {
            return
        }
        pendingClose = true
        Task { @MainActor [weak self] in
            guard let self = self, self.pendingClose else { return }
            guard self.shouldAutoHide else { return }
            self.pendingClose = false
            self.closeWithAnimation()
        }
    }

    public func checkAndHideIfNeeded() {
        if shouldAutoHide {
            orderOutWithAnimation()
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        if attachedSheet != nil {
            super.cancelOperation(sender)
            return
        }
        if let onCancelOperation = onCancelOperation {
            onCancelOperation()
        } else if !isPinned {
            closeWithAnimation()
        }
    }

    public func closeWithAnimation() {
        guard !isClosing else { return }
        isClosing = true
        animateOut { [weak self] in
            guard let self = self, self.isClosing else { return }
            self.orderOut(nil)
            self.isClosing = false
            self.onCloseCallback?()
        }
    }

    public func orderOutWithAnimation() {
        closeWithAnimation()
    }

    public override func orderOut(_ sender: Any?) {
        stopDesktopDismissalMonitor()
        super.orderOut(sender)
        if !isClosing {
            onCloseCallback?()
        }
    }

    private func animateOut(completion: @escaping @MainActor @Sendable () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                completion()
            }
        }
    }

    public func cancelClosing() {
        isClosing = false
        pendingClose = false
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        cancelClosing()
        super.makeKeyAndOrderFront(sender)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        startDesktopDismissalMonitor()
    }

    // 💡 外部点击监听：仅在面板可见并成为 Key 时监听全局鼠标按下，实现点击空白桌面/外部非活跃区自动关闭
    private func startDesktopDismissalMonitor() {
        guard desktopDismissalMonitor == nil else { return }
        desktopDismissalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.shouldAutoHide else { return }
                self.closeWithAnimation()
            }
        }
    }

    private func stopDesktopDismissalMonitor() {
        if let monitor = desktopDismissalMonitor {
            NSEvent.removeMonitor(monitor)
            desktopDismissalMonitor = nil
        }
    }
}
