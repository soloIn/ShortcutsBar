import AppKit

public final class ScriptMonitorSpinnerView: NSView {
    public enum State: Equatable, Sendable {
        case idle
        case running(taskCount: Int)
        case successFlash
        case errorFlash
    }

    private let iconImageView = NSImageView()
    private let spinnerLayer = CAShapeLayer()
    private let badgeTextField = NSTextField(labelWithString: "")

    public private(set) var currentState: State = .idle
    public var ringStyle: ProgressRingStyle = PreferencesStore.shared.progressRingStyle {
        didSet {
            applyStyle(ringStyle)
            if case .running = currentState {
                stopSpinnerAnimation()
                startSpinnerAnimation()
            }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        setupUI()
        observePreferences()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        observePreferences()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Icon Image View (Center 16x16)
        iconImageView.frame = NSRect(x: 5, y: 3, width: 16, height: 16)
        iconImageView.imageScaling = .scaleProportionallyDown
        setIconForIdle()
        addSubview(iconImageView)

        // 2. Spinner Layer around icon
        let bounds = NSRect(x: 3, y: 1, width: 20, height: 20)
        spinnerLayer.frame = bounds
        spinnerLayer.fillColor = CGColor(gray: 0, alpha: 0)
        spinnerLayer.lineCap = .round
        spinnerLayer.isHidden = true
        applyStyle(ringStyle)
        layer?.addSublayer(spinnerLayer)

        // 3. Multi-task badge
        badgeTextField.frame = NSRect(x: 16, y: 11, width: 10, height: 10)
        badgeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
        badgeTextField.textColor = .white
        badgeTextField.backgroundColor = NSColor(red: 0.0, green: 0.75, blue: 0.95, alpha: 1.0)
        badgeTextField.alignment = .center
        badgeTextField.isBezeled = false
        badgeTextField.drawsBackground = true
        badgeTextField.wantsLayer = true
        badgeTextField.layer?.cornerRadius = 5
        badgeTextField.layer?.masksToBounds = true
        badgeTextField.isHidden = true
        addSubview(badgeTextField)
    }

    private func observePreferences() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferencesChanged),
            name: PreferencesStore.preferencesChangedNotification,
            object: nil
        )
    }

    @objc private func handlePreferencesChanged() {
        let newStyle = PreferencesStore.shared.progressRingStyle
        if newStyle != ringStyle {
            self.ringStyle = newStyle
        }
    }

    private func applyStyle(_ style: ProgressRingStyle) {
        let bounds = NSRect(x: 0, y: 0, width: 20, height: 20)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 8.5
        let path = CGMutablePath()

        switch style {
        case .classicMinimal:
            // 1.0pt single thin arc (180 degrees), understated and minimal
            path.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi, clockwise: false)
            spinnerLayer.path = path
            spinnerLayer.lineWidth = 1.0
            spinnerLayer.lineDashPattern = nil
            spinnerLayer.strokeColor = NSColor.secondaryLabelColor.cgColor

        case .dualBalanced:
            // Symmetrical dual 90-degree arcs, stable and balanced
            path.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 0.5, clockwise: false)
            let path2 = CGMutablePath()
            path2.addArc(center: center, radius: radius, startAngle: CGFloat.pi, endAngle: CGFloat.pi * 1.5, clockwise: false)
            path.addPath(path2)
            spinnerLayer.path = path
            spinnerLayer.lineWidth = 1.2
            spinnerLayer.lineDashPattern = nil
            spinnerLayer.strokeColor = NSColor.systemCyan.cgColor

        case .pulsingGlow:
            // Full 360 circle with breathing opacity animation (zero rotation)
            path.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
            spinnerLayer.path = path
            spinnerLayer.lineWidth = 1.2
            spinnerLayer.lineDashPattern = nil
            spinnerLayer.strokeColor = NSColor.systemCyan.cgColor

        case .dottedOrbit:
            // Dotted stipple line pattern, precise radar instrumentation
            path.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
            spinnerLayer.path = path
            spinnerLayer.lineWidth = 1.2
            spinnerLayer.lineDashPattern = [2, 3]
            spinnerLayer.strokeColor = NSColor.systemCyan.cgColor

        case .auroraVivid:
            // 270 degree vibrant arc
            path.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 1.5, clockwise: false)
            spinnerLayer.path = path
            spinnerLayer.lineWidth = 1.5
            spinnerLayer.lineDashPattern = nil
            spinnerLayer.strokeColor = NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0).cgColor
        }
    }

    public func updateState(_ state: State) {
        currentState = state

        switch state {
        case .idle:
            stopSpinnerAnimation()
            badgeTextField.isHidden = true
            setIconForIdle()

        case .running(let count):
            setIconForRunning()
            startSpinnerAnimation()
            if count > 1 {
                badgeTextField.isHidden = false
                badgeTextField.stringValue = "\(min(count, 9))"
            } else {
                badgeTextField.isHidden = true
            }

        case .successFlash:
            stopSpinnerAnimation()
            badgeTextField.isHidden = true
            setIcon(systemName: "checkmark.circle.fill", tintColor: .systemGreen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.currentState == .successFlash {
                    self?.updateState(.idle)
                }
            }

        case .errorFlash:
            stopSpinnerAnimation()
            badgeTextField.isHidden = true
            setIcon(systemName: "exclamationmark.circle.fill", tintColor: .systemRed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
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

    private func startSpinnerAnimation() {
        spinnerLayer.isHidden = false

        switch ringStyle {
        case .classicMinimal:
            if spinnerLayer.animation(forKey: "rotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = -Double.pi * 2
                rotation.duration = 1.4 // Gentle slow rotation
                rotation.repeatCount = .infinity
                rotation.isRemovedOnCompletion = false
                spinnerLayer.add(rotation, forKey: "rotation")
            }

        case .dualBalanced:
            if spinnerLayer.animation(forKey: "rotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = -Double.pi * 2
                rotation.duration = 1.2
                rotation.repeatCount = .infinity
                rotation.isRemovedOnCompletion = false
                spinnerLayer.add(rotation, forKey: "rotation")
            }

        case .pulsingGlow:
            // Static position with breathing opacity pulse
            if spinnerLayer.animation(forKey: "pulse") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 0.20
                pulse.toValue = 0.90
                pulse.duration = 0.95
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pulse.isRemovedOnCompletion = false
                spinnerLayer.add(pulse, forKey: "pulse")
            }

        case .dottedOrbit:
            if spinnerLayer.animation(forKey: "rotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = -Double.pi * 2
                rotation.duration = 1.8 // Slow precision radar orbit
                rotation.repeatCount = .infinity
                rotation.isRemovedOnCompletion = false
                spinnerLayer.add(rotation, forKey: "rotation")
            }

        case .auroraVivid:
            if spinnerLayer.animation(forKey: "rotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = -Double.pi * 2
                rotation.duration = 0.85
                rotation.repeatCount = .infinity
                rotation.isRemovedOnCompletion = false
                spinnerLayer.add(rotation, forKey: "rotation")
            }
        }
    }

    private func stopSpinnerAnimation() {
        spinnerLayer.removeAnimation(forKey: "rotation")
        spinnerLayer.removeAnimation(forKey: "pulse")
        spinnerLayer.opacity = 1.0
        spinnerLayer.isHidden = true
    }
}
