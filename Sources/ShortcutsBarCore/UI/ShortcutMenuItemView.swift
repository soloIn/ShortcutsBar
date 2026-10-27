import AppKit

public final class ShortcutMenuItemView: NSView {
    public let item: ShortcutItem
    public weak var menuItem: NSMenuItem?
    public var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let trailingCueView = NSImageView()

    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false

    public init(
        item: ShortcutItem,
        onClick: (() -> Void)? = nil
    ) {
        self.item = item
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Authentic 24x24 Shortcut Icon
        iconView.frame = NSRect(x: 10, y: 6, width: 24, height: 24)
        iconView.image = ShortcutIconRenderer.shared.icon(for: item, size: 24)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        // 2. Determine layout based on subtitle presence
        let hasSubtitle = (item.actionCount > 0 || item.folderName != nil)

        if hasSubtitle {
            // Two-line layout: Title + Subtitle
            titleLabel.frame = NSRect(x: 42, y: 17, width: 176, height: 16)
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.stringValue = item.name
            addSubview(titleLabel)

            subtitleLabel.frame = NSRect(x: 42, y: 3, width: 176, height: 13)
            subtitleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail

            var subParts: [String] = []
            if let folder = item.folderName, !folder.isEmpty {
                subParts.append(folder)
            }
            if item.actionCount > 0 {
                subParts.append("\(item.actionCount) 步")
            }
            subtitleLabel.stringValue = subParts.joined(separator: " · ")
            addSubview(subtitleLabel)
        } else {
            // Single-line centered title layout
            titleLabel.frame = NSRect(x: 42, y: 9, width: 176, height: 18)
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.stringValue = item.name
            addSubview(titleLabel)
        }

        // 3. Subtle Play / Action Cue on the right
        trailingCueView.frame = NSRect(x: 234, y: 11, width: 14, height: 14)
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        if let playSymbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "运行") {
            trailingCueView.image = playSymbol.withSymbolConfiguration(config)
            trailingCueView.contentTintColor = .tertiaryLabelColor
        }
        addSubview(trailingCueView)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateVisualState()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isHovered = false
            updateVisualState()
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered {
            let highlightRect = bounds.insetBy(dx: 4, dy: 2)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 5.0, yRadius: 5.0)
            NSColor.selectedContentBackgroundColor.setFill()
            path.fill()
        }
    }

    private func updateVisualState() {
        if isHovered {
            titleLabel.textColor = .white
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.82)
            trailingCueView.contentTintColor = .white
        } else {
            titleLabel.textColor = .labelColor
            subtitleLabel.textColor = .secondaryLabelColor
            trailingCueView.contentTintColor = .tertiaryLabelColor
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            if let menu = enclosingMenuItem?.menu ?? menuItem?.menu {
                menu.cancelTracking()
            }
            onClick?()
        } else {
            super.mouseUp(with: event)
        }
    }
}
