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

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
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
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: 8.5,
            startAngle: 0,
            endAngle: CGFloat.pi * 1.5, // 270 degree arc
            clockwise: false
        )
        spinnerLayer.path = path
        spinnerLayer.fillColor = CGColor(gray: 0, alpha: 0)
        spinnerLayer.strokeColor = NSColor.systemBlue.cgColor
        spinnerLayer.lineWidth = 1.5
        spinnerLayer.lineCap = .round
        spinnerLayer.frame = bounds
        spinnerLayer.isHidden = true
        layer?.addSublayer(spinnerLayer)

        // 3. Multi-task badge
        badgeTextField.frame = NSRect(x: 16, y: 11, width: 10, height: 10)
        badgeTextField.font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
        badgeTextField.textColor = .white
        badgeTextField.backgroundColor = .systemBlue
        badgeTextField.alignment = .center
        badgeTextField.isBezeled = false
        badgeTextField.drawsBackground = true
        badgeTextField.wantsLayer = true
        badgeTextField.layer?.cornerRadius = 5
        badgeTextField.layer?.masksToBounds = true
        badgeTextField.isHidden = true
        addSubview(badgeTextField)
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
        if let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Shortcuts Bar") {
            image.isTemplate = true
            iconImageView.image = image
            iconImageView.contentTintColor = nil
        }
    }

    private func setIconForRunning() {
        if let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Running") {
            image.isTemplate = true
            iconImageView.image = image
            iconImageView.contentTintColor = NSColor.systemBlue
        }
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

    private func stopSpinnerAnimation() {
        spinnerLayer.removeAnimation(forKey: "rotation")
        spinnerLayer.isHidden = true
    }
}
