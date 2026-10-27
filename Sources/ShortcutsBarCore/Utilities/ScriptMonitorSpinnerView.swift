import AppKit

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

    private var progressTimer: Timer?
    private var earliestStartTime: Date?
    private var primaryActionCount: Int = 4

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        progressTimer?.invalidate()
    }

    private func setupUI() {
        wantsLayer = true

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

        updateColorsForAppearance()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColorsForAppearance()
    }

    public override func updateLayer() {
        super.updateLayer()
        updateColorsForAppearance()
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
    }

    /// Sets explicit progress percentage from 0.0 to 1.0
    public func setProgress(_ progress: Double) {
        currentProgress = max(0.0, min(1.0, progress))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(currentProgress)
        CATransaction.commit()
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
    }

    private func setIconForIdle() {
        let image = ShortcutsIconFactory.createMenuBarIcon(size: 16)
        iconImageView.image = image
        iconImageView.contentTintColor = nil
    }

    private func setIconForRunning() {
        let image = ShortcutsIconFactory.createRunningShortcutsIcon(size: 16)
        iconImageView.image = image
        iconImageView.contentTintColor = nil
    }

    private func setIcon(systemName: String, tintColor: NSColor) {
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: systemName) {
            image.isTemplate = false
            iconImageView.image = image
            iconImageView.contentTintColor = tintColor
        }
    }

    private func startProgressTimer() {
        if progressTimer != nil { return }
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(handleProgressTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.progressTimer = timer
        handleProgressTick()
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    @objc private func handleProgressTick() {
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
