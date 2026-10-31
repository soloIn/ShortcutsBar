import AppKit
import UserNotifications

@MainActor
public final class StatusItemController: NSObject {
    public private(set) var statusItem: NSStatusItem?
    private let spinnerView: ScriptMonitorSpinnerView
    private let processManager: ProcessManager
    private let preferencesStore: PreferencesStore
    private var _fallbackMenu: NSMenu?
    private var queueObserverId: UUID?
    private var taskCompletedObserverId: UUID?

    public var classicMenu: NSMenu? {
        get { _fallbackMenu }
        set {
            _fallbackMenu = newValue
            _fallbackMenu?.delegate = self
            updateMenuBinding()
        }
    }

    public var menu: NSMenu? {
        get { _fallbackMenu }
        set {
            _fallbackMenu = newValue
            _fallbackMenu?.delegate = self
            updateMenuBinding()
        }
    }

    public var onTriggerFloatingPanel: (() -> Void)?
    public var onTriggerClassicMenu: (() -> Void)?

    public init(
        processManager: ProcessManager,
        preferencesStore: PreferencesStore = .shared,
        statusItem: NSStatusItem? = nil
    ) {
        self.processManager = processManager
        self.preferencesStore = preferencesStore
        self.spinnerView = ScriptMonitorSpinnerView(frame: NSRect(x: 0, y: 0, width: 26, height: 22))

        if let custom = statusItem {
            self.statusItem = custom
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            // Standard macOS menu bar status item width (28 points)
            self.statusItem = NSStatusBar.system.statusItem(withLength: 28)
        } else {
            self.statusItem = nil
        }
        super.init()

        setupStatusItem()
        observeProcessManager()
        observePreferences()
    }

    isolated deinit {
        if let id = queueObserverId {
            processManager.removeQueueObserver(id)
        }
        if let id = taskCompletedObserverId {
            processManager.removeTaskCompletedObserver(id)
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    private var preferencesObserver: NSObjectProtocol?

    public static func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func setupStatusItem() {
        spinnerView.onIdle = { [weak self] in
            self?.showIdleState()
        }
        showIdleState()

        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            rightClick.buttonMask = 0x2
            button.addGestureRecognizer(rightClick)
        }
        updateMenuBinding()
    }

    private func observePreferences() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenuBinding()
            }
        }
    }

    public func updateMenuBinding() {
        if preferencesStore.primaryClickAction == .classicMenu {
            statusItem?.menu = _fallbackMenu
        } else {
            statusItem?.menu = nil
            if let button = statusItem?.button {
                button.target = self
                button.action = #selector(handleStatusItemClick(_:))
            }
        }
    }

    @objc public func handleRightClick(_ sender: NSClickGestureRecognizer) {
        if preferencesStore.primaryClickAction == .floatingPanel {
            triggerClassicMenu()
        } else {
            triggerFloatingPanel()
        }
    }

    public func setHighlighted(_ highlighted: Bool) {
        statusItem?.button?.isHighlighted = highlighted
    }

    @objc public func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            routeDefaultAction()
            return
        }

        let isRightClick = currentEvent.type == .rightMouseUp || currentEvent.type == .rightMouseDown
        let isOptionClick = currentEvent.modifierFlags.contains(.option)

        if isRightClick || isOptionClick {
            if preferencesStore.primaryClickAction == .floatingPanel {
                triggerClassicMenu()
            } else {
                triggerFloatingPanel()
            }
        } else {
            routeDefaultAction()
        }
    }

    private func routeDefaultAction() {
        switch preferencesStore.primaryClickAction {
        case .floatingPanel:
            triggerFloatingPanel()
        case .classicMenu:
            triggerClassicMenu()
        }
    }

    public func triggerClassicMenu() {
        if let customHandler = onTriggerClassicMenu {
            customHandler()
        }
        guard let menu = _fallbackMenu, let button = statusItem?.button else { return }
        button.isHighlighted = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    public func triggerFloatingPanel() {
        onTriggerFloatingPanel?()
    }

    private func showIdleState() {
        guard let button = statusItem?.button else { return }
        spinnerView.removeFromSuperview()
        let icon = ShortcutsIconFactory.createMenuBarIcon(size: 16)
        button.image = icon
        button.imagePosition = .imageOnly
    }

    private func showActiveState() {
        guard let button = statusItem?.button else { return }
        if spinnerView.superview == nil {
            button.image = nil
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(spinnerView)
            spinnerView.frame = button.bounds
            spinnerView.autoresizingMask = [.width, .height]
        }
    }

    private func observeProcessManager() {
        queueObserverId = processManager.addQueueObserver { [weak self] tasks in
            DispatchQueue.main.async { [weak self] in
                self?.handleQueueChanged(tasks: tasks)
            }
        }

        taskCompletedObserverId = processManager.addTaskCompletedObserver { [weak self] task, success in
            DispatchQueue.main.async { [weak self] in
                self?.handleTaskCompleted(task: task, success: success)
            }
        }
    }

    private func handleQueueChanged(tasks: [RunningTask]) {
        if tasks.isEmpty {
            if spinnerView.currentState == .idle {
                showIdleState()
            }
        } else {
            showActiveState()
            spinnerView.updateRunningTasks(tasks)
        }
    }

    private func handleTaskCompleted(task: RunningTask, success: Bool) {
        if processManager.activeTaskCount == 0 {
            showActiveState()
            if success {
                spinnerView.updateState(.successFlash)
            } else {
                spinnerView.updateState(.errorFlash)
            }
        }

        // Wire up notifyOnFailure: dispatch notification when shortcut fails
        if !success && preferencesStore.notifyOnFailure {
            sendFailureNotification(shortcutName: task.shortcutName)
        }
    }

    private func sendFailureNotification(shortcutName: String) {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = "快捷指令运行失败"
        content.body = "快捷指令「\(shortcutName)」未能成功执行。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[StatusItemController] Failed to deliver failure notification: \(error)")
            }
        }
    }

    public func flashSuccess() {
        spinnerView.updateState(.successFlash)
    }

    public func flashError() {
        spinnerView.updateState(.errorFlash)
    }
}

extension StatusItemController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        statusItem?.button?.isHighlighted = true
        onTriggerClassicMenu?()
    }

    public func menuDidClose(_ menu: NSMenu) {
        statusItem?.button?.isHighlighted = false
    }
}
