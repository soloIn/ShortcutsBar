import AppKit

@MainActor
public final class ScriptMonitorSpinnerView: NSView {
    public enum State: Equatable, Sendable {
        case idle
        case running(taskCount: Int)
        case successFlash
        case errorFlash
    }

    private let iconImageView = NSImageView()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let badgeTextField = NSTextField(labelWithString: "")

    public private(set) var currentState: State = .idle
    public private(set) var currentProgress: Double = 0.0
    public var onIdle: (@MainActor () -> Void)?

    private var progressTimer: Timer?
    private var earliestStartTime: Date?
    private var primaryActionCount: Int = 4
    private var lastLayoutSize: CGSize = .zero

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Forward all clicks to the status bar button to trigger menu display
    }

    public override func layout() {
        super.layout()
        let b = bounds
        guard b.size != lastLayoutSize else { return }
        lastLayoutSize = b.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let iconSize: CGFloat = 16
        iconImageView.frame = NSRect(
            x: round((b.width - iconSize) / 2),
            y: round((b.height - iconSize) / 2),
            width: iconSize,
            height: iconSize
        )

        let ringSize: CGFloat = 20
        let ringRect = NSRect(
            x: round((b.width - ringSize) / 2),
            y: round((b.height - ringSize) / 2),
            width: ringSize,
            height: ringSize
        )
        let ringCenter = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius: CGFloat = 8.5

        let trackPath = CGMutablePath()
        trackPath.addArc(center: ringCenter, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        trackLayer.frame = b
        trackLayer.path = trackPath

        let progressPath = CGMutablePath()
        progressPath.addArc(center: ringCenter, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi * 1.5, clockwise: false)
        progressLayer.frame = b
        progressLayer.path = progressPath

        badgeTextField.frame = NSRect(x: b.width - 11, y: b.height - 11, width: 10, height: 10)

        CATransaction.commit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && currentState == .idle {
            stopProgressTimer()
        }
    }

    private func setupUI() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibilityLabel()

        // 1. Center Shortcuts Logo Icon (16x16)
        iconImageView.frame = NSRect(x: 5, y: 3, width: 16, height: 16)
        iconImageView.imageScaling = .scaleProportionallyDown
        setIconForIdle()
        addSubview(iconImageView)

        // Common circular geometry
        let bounds = NSRect(x: 3, y: 1, width: 20, height: 20)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 8.5

        // 2. Background Track ("浅底圈" - Liquid Glass Frosted Rim)
        let trackPath = CGMutablePath()
        trackPath.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        trackLayer.frame = bounds
        trackLayer.path = trackPath
        trackLayer.fillColor = CGColor(gray: 0, alpha: 0)
        trackLayer.lineWidth = 1.5
        trackLayer.lineCap = .round
        trackLayer.isHidden = true
        layer?.addSublayer(trackLayer)

        // 3. Foreground Determinate Progress Ring (Fills clockwise from 12 o'clock, 0% to 100%)
        let progressPath = CGMutablePath()
        progressPath.addArc(
            center: center,
            radius: radius,
            startAngle: -CGFloat.pi / 2, // 12 o'clock top
            endAngle: CGFloat.pi * 1.5,
            clockwise: false
        )
        progressLayer.frame = bounds
        progressLayer.path = progressPath
        progressLayer.fillColor = CGColor(gray: 0, alpha: 0)
        progressLayer.lineWidth = 1.5
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0.0
        progressLayer.strokeEnd = 0.0
        progressLayer.isHidden = true
        layer?.addSublayer(progressLayer)

        // 4. Multi-task badge
        badgeTextField.frame = NSRect(x: 16, y: 11, width: 10, height: 10)
        badgeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
        badgeTextField.textColor = .white
        badgeTextField.alignment = .center
        badgeTextField.isBezeled = false
        badgeTextField.drawsBackground = true
        badgeTextField.wantsLayer = true
        badgeTextField.layer?.cornerRadius = 5
        badgeTextField.layer?.masksToBounds = true
        badgeTextField.isHidden = true
        addSubview(badgeTextField)

        layout()
        updateColorsForAppearance()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColorsForAppearance()
    }

    public override func updateLayer() {
        super.updateLayer()
    }

    private func updateColorsForAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Apple Liquid Glass: subtle frosted track rim in light/dark mode
        let trackColor = isDark
            ? NSColor(white: 1.0, alpha: 0.18).cgColor
            : NSColor(white: 0.0, alpha: 0.14).cgColor
        trackLayer.strokeColor = trackColor

        // Apple HIG native progress tint: adapts dynamically to macOS control accent color
        let accentColor = NSColor.controlAccentColor.cgColor
        progressLayer.strokeColor = accentColor
        badgeTextField.backgroundColor = NSColor.controlAccentColor

        if currentState == .idle {
            let targetColor = NSColor.headerTextColor
            if iconImageView.contentTintColor != targetColor {
                iconImageView.contentTintColor = targetColor
            }
        }
    }

    /// Sets explicit progress percentage from 0.0 to 1.0
    public func setProgress(_ progress: Double) {
        currentProgress = max(0.0, min(1.0, progress))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(currentProgress)
        CATransaction.commit()
        updateAccessibilityLabel()
    }

    public func updateRunningTasks(_ tasks: [RunningTask]) {
        guard !tasks.isEmpty else {
            updateState(.idle)
            return
        }

        self.earliestStartTime = tasks.map { $0.startTime }.min()
        self.primaryActionCount = max(tasks.map { $0.actionCount }.max() ?? 4, 3)
        updateState(.running(taskCount: tasks.count))
    }

    public func updateState(_ state: State) {
        currentState = state

        switch state {
        case .idle:
            stopProgressTimer()
            setProgress(0.0)
            trackLayer.isHidden = true
            progressLayer.isHidden = true
            badgeTextField.isHidden = true
            setIconForIdle()
            onIdle?()

        case .running(let count):
            setIconForRunning()
            trackLayer.isHidden = false
            progressLayer.isHidden = false
            updateColorsForAppearance()
            startProgressTimer()

            if count > 1 {
                badgeTextField.isHidden = false
                badgeTextField.stringValue = "\(min(count, 9))"
            } else {
                badgeTextField.isHidden = true
            }

        case .successFlash:
            stopProgressTimer()
            // 100% full circle: completely fills the "浅底圈"
            trackLayer.isHidden = false
            progressLayer.isHidden = false
            updateColorsForAppearance()
            setProgress(1.0)
            badgeTextField.isHidden = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.currentState == .successFlash {
                    self?.updateState(.idle)
                }
            }

        case .errorFlash:
            stopProgressTimer()
            trackLayer.isHidden = true
            progressLayer.isHidden = true
            badgeTextField.isHidden = true
            setIcon(systemName: "exclamationmark.circle.fill", tintColor: .systemRed)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.currentState == .errorFlash {
                    self?.updateState(.idle)
                }
            }
        }
        updateAccessibilityLabel()
    }

    private func updateAccessibilityLabel() {
        switch currentState {
        case .idle:
            setAccessibilityLabel("快捷指令栏：空闲")
        case .running(let count):
            let pct = Int(currentProgress * 100)
            setAccessibilityLabel("快捷指令栏：正在运行 \(count) 个任务，进度 \(pct)%")
        case .successFlash:
            setAccessibilityLabel("快捷指令栏：执行完成")
        case .errorFlash:
            setAccessibilityLabel("快捷指令栏：执行失败")
        }
    }

    private func setIconForIdle() {
        let image = ShortcutsIconFactory.createMenuBarIcon(size: 16)
        iconImageView.image = image
        iconImageView.contentTintColor = NSColor.headerTextColor
    }

    private func setIconForRunning() {
        let image = ShortcutsIconFactory.createRunningShortcutsIcon(size: 16)
        iconImageView.image = image
        iconImageView.contentTintColor = nil
    }

    private func setIcon(systemName: String, tintColor: NSColor) {
        let config = NSImage.SymbolConfiguration(paletteColors: [tintColor])
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: systemName)?.withSymbolConfiguration(config) {
            iconImageView.image = image
            iconImageView.contentTintColor = nil
        }
    }

    private func startProgressTimer() {
        if progressTimer != nil { return }
        // 10Hz (100ms) interval: smooth Liquid Glass progression while halving CPU wakeups
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleProgressTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.progressTimer = timer
        handleProgressTick()
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func handleProgressTick() {
        guard case .running = currentState else { return }
        let startTime = earliestStartTime ?? Date()
        let elapsed = max(0, Date().timeIntervalSince(startTime))

        // Progressive asymptotic curve advancing towards 0.94 while actively executing
        let expectedDuration = max(2.5, Double(primaryActionCount) * 0.35)
        let targetProgress = 1.0 - exp(-elapsed / (expectedDuration * 0.60))
        let clamped = min(0.94, max(0.04, targetProgress))
        setProgress(clamped)
    }
}
