import AppKit
import UserNotifications

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem?
    private let spinnerView: ScriptMonitorSpinnerView
    private let processManager: ProcessManager
    private let preferencesStore: PreferencesStore
    private var _fallbackMenu: NSMenu?

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
        } else if CGSessionCopyCurrentDictionary() != nil {
            // Standard macOS menu bar status item width (28 points)
            self.statusItem = NSStatusBar.system.statusItem(withLength: 28)
        } else {
            self.statusItem = nil
        }
        super.init()

        setupStatusItem()
        observeProcessManager()
    }

    deinit {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    public var menu: NSMenu? {
        get { statusItem?.menu ?? _fallbackMenu }
        set {
            if let item = statusItem {
                item.menu = newValue
            } else {
                _fallbackMenu = newValue
            }
        }
    }

    private func setupStatusItem() {
        spinnerView.onIdle = { [weak self] in
            self?.showIdleState()
        }
        showIdleState()
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
        processManager.onQueueChanged = { [weak self] tasks in
            DispatchQueue.main.async { [weak self] in
                self?.handleQueueChanged(tasks: tasks)
            }
        }

        processManager.onTaskCompleted = { [weak self] task, success in
            DispatchQueue.main.async { [weak self] in
                self?.handleTaskCompleted(task: task, success: success)
            }
        }
    }

    private func handleQueueChanged(tasks: [RunningTask]) {
        if tasks.isEmpty {
            if spinnerView.currentState != .successFlash && spinnerView.currentState != .errorFlash {
                spinnerView.updateState(.idle)
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
        let content = UNMutableNotificationContent()
        content.title = "快捷指令运行失败"
        content.body = "快捷指令「\(shortcutName)」未能成功执行。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    public func flashSuccess() {
        spinnerView.updateState(.successFlash)
    }

    public func flashError() {
        spinnerView.updateState(.errorFlash)
    }
}
