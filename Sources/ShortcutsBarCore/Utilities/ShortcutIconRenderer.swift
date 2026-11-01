import AppKit
import CoreText
import CoreGraphics

@MainActor
public final class ShortcutIconRenderer {
    public static let shared = ShortcutIconRenderer()

    private let cache = NSCache<NSString, NSImage>()

    /// 💡 架构合规：对外保留属性以维持接口兼容性，内部彻底弃用私有框架以满足 App Store 2.5.1 规范与 Hardened Runtime
    public var usesPrivateFrameworks: Bool { false }

    public init() {}

    // MARK: - WCAG 2.1 Relative Luminance & Dynamic Text Contrast
    public static func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func linearize(_ val: CGFloat) -> CGFloat {
            return val <= 0.04045 ? val / 12.92 : pow((val + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    public static func contrastRatio(l1: CGFloat, l2: CGFloat) -> CGFloat {
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func optimalTextColor(forBackgroundColor colorValue: Int64) -> NSColor {
        let r = CGFloat((colorValue >> 24) & 0xFF) / 255.0
        let g = CGFloat((colorValue >> 16) & 0xFF) / 255.0
        let b = CGFloat((colorValue >> 8) & 0xFF) / 255.0
        let lum = relativeLuminance(r: r, g: g, b: b)
        // If background is bright (relative luminance > 0.55), use dark charcoal text for >= 4.5:1 contrast
        return lum > 0.55 ? NSColor(white: 0.1, alpha: 0.95) : NSColor.white
    }

    /// Comprehensive metadata-driven SF Symbol mapping for shortcut glyph IDs
    public static var glyphToSymbolMap: [Int: String] {
        ShortcutsGlyphMapper.glyphToSymbolMap
    }

    public func icon(for item: ShortcutItem, size: CGFloat = 16) -> NSImage {
        let cacheKey = "\(item.name)_\(item.glyph ?? 0)_\(item.colorValue ?? 0)_\(Int(size))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let rendered: NSImage
        if let color = item.colorValue {
            rendered = renderSquircle(name: item.name, colorValue: color, glyph: item.glyph, size: size)
        } else {
            rendered = renderDefaultIcon(glyph: item.glyph, size: size)
        }

        cache.setObject(rendered, forKey: cacheKey)
        return rendered
    }

    private func renderSquircle(name: String, colorValue: Int64, glyph: Int?, size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = CGFloat((colorValue >> 24) & 0xFF) / 255.0
            let g = CGFloat((colorValue >> 16) & 0xFF) / 255.0
            let b = CGFloat((colorValue >> 8) & 0xFF) / 255.0
            let color = NSColor(red: r, green: g, blue: b, alpha: 1.0)

            let cornerRadius = size * 0.26
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            color.setFill()
            path.fill()

            let textColor = Self.optimalTextColor(forBackgroundColor: colorValue)

            // 1. First priority: Render authentic metadata-matched SF Symbol
            let symbolName = ShortcutsGlyphMapper.symbolName(for: glyph)
            if let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(paletteColors: [textColor])
                let tinted = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
                let symbolRect = NSRect(x: size * 0.20, y: size * 0.20, width: size * 0.60, height: size * 0.60)
                tinted.draw(in: symbolRect)
                return true
            }

            // 2. Fallback: Default command symbol
            if let baseSymbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(paletteColors: [textColor])
                let tinted = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
                let symbolRect = NSRect(x: size * 0.22, y: size * 0.22, width: size * 0.56, height: size * 0.56)
                tinted.draw(in: symbolRect)
            }

            return true
        }
    }

    private func renderDefaultIcon(glyph: Int? = nil, size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let cornerRadius = size * 0.26
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.systemBlue.setFill()
            path.fill()

            let textColor = NSColor.white

            // 1. First priority: SF Symbol from metadata
            let symbolName = ShortcutsGlyphMapper.symbolName(for: glyph)
            if let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(paletteColors: [textColor])
                let tinted = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
                let symbolRect = NSRect(x: size * 0.20, y: size * 0.20, width: size * 0.60, height: size * 0.60)
                tinted.draw(in: symbolRect)
                return true
            }

            // 2. Fallback to command
            if let baseSymbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(paletteColors: [textColor])
                let tinted = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
                let symbolRect = NSRect(x: size * 0.22, y: size * 0.22, width: size * 0.56, height: size * 0.56)
                tinted.draw(in: symbolRect)
            }

            return true
        }
    }
}
