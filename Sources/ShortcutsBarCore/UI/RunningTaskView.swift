import AppKit

public final class RunningTaskView: NSView {
    private let taskId: UUID
    private let taskName: String
    private let onStop: (UUID) -> Void

    private let spinnerView = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton()

    public init(
        taskId: UUID,
        taskName: String,
        onStop: @escaping (UUID) -> Void
    ) {
        self.taskId = taskId
        self.taskName = taskName
        self.onStop = onStop
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Progress Indicator (Micro spinner)
        spinnerView.style = .spinning
        spinnerView.controlSize = .small
        spinnerView.frame = NSRect(x: 10, y: 5, width: 16, height: 16)
        spinnerView.isDisplayedWhenStopped = false
        spinnerView.startAnimation(nil)
        addSubview(spinnerView)

        // 2. Title Label (Shortcuts Name)
        titleLabel.frame = NSRect(x: 32, y: 4, width: 195, height: 18)
        titleLabel.stringValue = taskName
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // 3. Stop Button (Pure HIG SF Symbol: stop.circle.fill)
        stopButton.frame = NSRect(x: 232, y: 3, width: 20, height: 20)
        stopButton.isBordered = false
        stopButton.title = ""
        stopButton.bezelStyle = .regularSquare

        if let stopImage = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "终止该任务") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            stopButton.image = stopImage.withSymbolConfiguration(config)
            stopButton.contentTintColor = .systemRed
        }
        stopButton.target = self
        stopButton.action = #selector(handleStopClicked)
        stopButton.toolTip = "终止 \(taskName)"
        addSubview(stopButton)
    }

    @objc private func handleStopClicked() {
        onStop(taskId)
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        stopButton.alphaValue = 1.0
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        stopButton.alphaValue = 0.8
    }
}
