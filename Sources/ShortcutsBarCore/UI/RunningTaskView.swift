import AppKit

@MainActor
public final class RunningTaskView: NSView {
    private let taskId: UUID
    private let taskName: String
    private let startTime: Date
    private let actionCount: Int
    private let onStop: (UUID) -> Void

    private let spinnerView = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton()

    private var timer: Timer?

    public init(
        taskId: UUID,
        taskName: String,
        startTime: Date = Date(),
        actionCount: Int = 0,
        onStop: @escaping (UUID) -> Void
    ) {
        self.taskId = taskId
        self.taskName = taskName
        self.startTime = startTime
        self.actionCount = actionCount
        self.onStop = onStop
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        autoresizingMask = [.width]
        setupUI()
        startTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopTimer()
        } else if timer == nil {
            startTimer()
        }
    }

    public override func updateLayer() {
        super.updateLayer()
        updateColorsForHighlight()
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Progress Indicator (Micro spinner)
        spinnerView.style = .spinning
        spinnerView.controlSize = .small
        spinnerView.frame = NSRect(x: 10, y: 10, width: 16, height: 16)
        spinnerView.isDisplayedWhenStopped = false
        spinnerView.startAnimation(nil)
        addSubview(spinnerView)

        // 2. Title Label (Shortcuts Name)
        titleLabel.frame = NSRect(x: 32, y: 17, width: 195, height: 16)
        titleLabel.stringValue = taskName
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        // 3. Progress / Elapsed Time Label
        progressLabel.frame = NSRect(x: 32, y: 3, width: 195, height: 14)
        progressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        progressLabel.lineBreakMode = .byTruncatingTail
        progressLabel.autoresizingMask = [.width]
        updateProgressText()
        addSubview(progressLabel)

        // 4. Stop Button (Pure HIG SF Symbol: stop.circle.fill)
        stopButton.frame = NSRect(x: 232, y: 8, width: 20, height: 20)
        stopButton.isBordered = false
        stopButton.title = ""
        stopButton.bezelStyle = .regularSquare
        stopButton.autoresizingMask = [.minXMargin]

        if let stopImage = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "停止运行") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            stopButton.image = stopImage.withSymbolConfiguration(config)
            stopButton.contentTintColor = .systemRed
        }
        stopButton.target = self
        stopButton.action = #selector(handleStopClicked)
        stopButton.toolTip = "停止运行 \(taskName)"
        addSubview(stopButton)

        updateColorsForHighlight()
    }

    private func updateColorsForHighlight() {
        let isHighlighted = enclosingMenuItem?.isHighlighted ?? false
        if isHighlighted {
            titleLabel.textColor = .selectedMenuItemTextColor
            progressLabel.textColor = .selectedMenuItemTextColor.withAlphaComponent(0.85)
        } else {
            titleLabel.textColor = .labelColor
            progressLabel.textColor = .secondaryLabelColor
        }
    }

    public func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        updateProgressText()
        stopTimer()

        // Weak-self block timer breaks the RunLoop strong reference cycle
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerTick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private func handleTimerTick() {
        updateProgressText()
        updateColorsForHighlight()
    }

    private func updateProgressText() {
        let elapsed = max(0, Int(Date().timeIntervalSince(startTime)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let timeStr = String(format: "%02d:%02d", minutes, seconds)

        if actionCount > 0 {
            progressLabel.stringValue = "\(actionCount) 步 · 运行中 \(timeStr)"
        } else {
            progressLabel.stringValue = "运行中 \(timeStr)"
        }
    }

    @objc private func handleStopClicked() {
        onStop(taskId)
    }
}
