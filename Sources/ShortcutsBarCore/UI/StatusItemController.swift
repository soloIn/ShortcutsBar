import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let spinnerView: ScriptMonitorSpinnerView
    private let processManager: ProcessManager

    public init(processManager: ProcessManager) {
        self.processManager = processManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: 28)
        self.spinnerView = ScriptMonitorSpinnerView(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        super.init()

        setupStatusItem()
        observeProcessManager()
    }

    public var menu: NSMenu? {
        get { statusItem.menu }
        set { statusItem.menu = newValue }
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(spinnerView)
        spinnerView.frame = button.bounds
        spinnerView.autoresizingMask = [.width, .height]
    }

    private func observeProcessManager() {
        processManager.onQueueChanged = { [weak self] tasks in
            Task { @MainActor [weak self] in
                self?.handleQueueChanged(tasks: tasks)
            }
        }

        processManager.onTaskCompleted = { [weak self] task, success in
            Task { @MainActor [weak self] in
                self?.handleTaskCompleted(task: task, success: success)
            }
        }
    }

    private func handleQueueChanged(tasks: [RunningTask]) {
        if tasks.isEmpty {
            if spinnerView.currentState != .successFlash && spinnerView.currentState != .errorFlash {
                spinnerView.updateState(.idle)
            }
        } else {
            spinnerView.updateRunningTasks(tasks)
        }
    }

    private func handleTaskCompleted(task: RunningTask, success: Bool) {
        if processManager.activeTaskCount == 0 {
            if success {
                spinnerView.updateState(.successFlash)
            } else {
                spinnerView.updateState(.errorFlash)
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
