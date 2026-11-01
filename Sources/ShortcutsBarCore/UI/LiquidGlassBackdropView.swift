import SwiftUI
import AppKit

/// 专用于 SwiftUI .background 的高性能 Liquid Glass 毛玻璃背景 (基于 macOS 26 原生 NSGlassEffectView)
@MainActor
public struct NSGlassEffectBackgroundRepresentable: NSViewRepresentable {
    public let style: NSGlassEffectView.Style
    public let cornerRadius: CGFloat
    public let isDark: Bool

    public init(
        style: NSGlassEffectView.Style = .regular,
        cornerRadius: CGFloat = 16,
        isDark: Bool = false
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> NSGlassEffectView {
        let glassView = NSGlassEffectView()
        glassView.style = style
        glassView.cornerRadius = cornerRadius
        glassView.wantsLayer = true
        return glassView
    }

    public func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        if nsView.style != style {
            nsView.style = style
        }
        if nsView.cornerRadius != cornerRadius {
            nsView.cornerRadius = cornerRadius
        }

        let targetView = nsView.contentView ?? nsView
        targetView.wantsLayer = true
        targetView.layer?.cornerRadius = cornerRadius
        targetView.layer?.masksToBounds = true

        // AppKit 原生 Base Opacity 遮罩层 (吸收桌面杂光，解决悬浮窗过透导致不可见问题)
        let overlayColor = isDark
            ? NSColor.black.withAlphaComponent(LiquidGlassBackdropView.darkOverlayAlpha)
            : NSColor.white.withAlphaComponent(LiquidGlassBackdropView.lightOverlayAlpha)
        targetView.layer?.backgroundColor = overlayColor.cgColor
    }
}

/// macOS 26+ Native Liquid Glass backdrop view (参考 Cogita 架构)
public struct LiquidGlassBackdropView: View {
    public var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public static let darkOverlayAlpha: CGFloat = 0.40
    public static let lightOverlayAlpha: CGFloat = 0.45

    public var body: some View {
        if reduceTransparency {
            // 💡 Apple HIG 辅助功能：当用户开启“减少透明度”时，优雅降级为原生实色背景，保障对比度与可读性
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else {
            NSGlassEffectBackgroundRepresentable(
                style: .regular,
                cornerRadius: cornerRadius,
                isDark: colorScheme == .dark
            )
        }
    }
}
