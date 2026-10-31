import AppKit
import CoreText
import CoreGraphics
import ObjectiveC

@MainActor
public final class ShortcutIconRenderer {
    public static let shared = ShortcutIconRenderer()

    private let cache = NSCache<NSString, NSImage>()
    private var isPrivateFrameworkLoaded = false
    private var iconClass: AnyClass?
    private var drawerClass: AnyClass?
    private static var isGlyphFontRegistered = false

    public var usesPrivateFrameworks: Bool { isPrivateFrameworkLoaded }

    public init() {
        loadFrameworks()
        Self.ensureGlyphFontRegistered()
    }

    private func loadFrameworks() {
        dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/WorkflowUICore.framework/WorkflowUICore", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_NOW)

        iconClass = NSClassFromString("WFWorkflowIcon")
        drawerClass = NSClassFromString("WFWorkflowIconDrawer")
        isPrivateFrameworkLoaded = (iconClass != nil && drawerClass != nil)
    }

    /// Registers Apple's authentic Shortcuts glyph TrueType font using public CoreText API
    public static func ensureGlyphFontRegistered() {
        guard !isGlyphFontRegistered else { return }
        let fontURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/Versions/A/Resources/WorkflowGlyphs.ttf")
        if FileManager.default.fileExists(atPath: fontURL.path) {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        }
        isGlyphFontRegistered = true
    }

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
        // 1. Primary path: Native system rendering via Apple's official WFWorkflowIconDrawer
        if let glyph = item.glyph, let color = item.colorValue, let sysIcon = renderSystemIcon(glyph: glyph, color: color, size: size) {
            rendered = sysIcon
        } else if let color = item.colorValue {
            // 2. Fallback path: Standalone squircle rendering
            rendered = renderSquircle(name: item.name, colorValue: color, glyph: item.glyph, size: size)
        } else {
            rendered = renderDefaultIcon(glyph: item.glyph, size: size)
        }

        cache.setObject(rendered, forKey: cacheKey)
        return rendered
    }

    private func renderSystemIcon(glyph: Int, color: Int64, size: CGFloat) -> NSImage? {
        guard isPrivateFrameworkLoaded,
              let iconCls = iconClass as? NSObject.Type,
              let drawerCls = drawerClass as? NSObject.Type else {
            return nil
        }

        let iconSel = NSSelectorFromString("initWithBackgroundColorValue:glyphCharacter:")
        let drawerSel = NSSelectorFromString("initWithIcon:")
        let imgSel = NSSelectorFromString("imageWithSize:")

        guard iconCls.instancesRespond(to: iconSel),
              drawerCls.instancesRespond(to: drawerSel) else {
            return nil
        }

        typealias IconInitFunc = @convention(c) (AnyObject, Selector, Int64, UInt16) -> AnyObject
        let iconObj = iconCls.init()
        let iconInit = unsafeBitCast(iconObj.method(for: iconSel), to: IconInitFunc.self)
        let icon = iconInit(iconObj, iconSel, color, UInt16(clamping: glyph))

        typealias DrawerInitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject
        let drawerObj = drawerCls.init()
        let drawerInit = unsafeBitCast(drawerObj.method(for: drawerSel), to: DrawerInitFunc.self)
        let drawer = drawerInit(drawerObj, drawerSel, icon)

        typealias ImgFunc = @convention(c) (AnyObject, Selector, CGSize) -> AnyObject?
        let imgMethod = unsafeBitCast((drawer as AnyObject).method(for: imgSel), to: ImgFunc.self)
        guard let result = imgMethod(drawer, imgSel, CGSize(width: size, height: size)) as AnyObject? else {
            return nil
        }

        if let nsImage = result as? NSImage {
            return nsImage
        } else if let wfImage = result as AnyObject?, let nsImg = wfImage.value(forKey: "NSImage") as? NSImage {
            return nsImg
        }
        return nil
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

            // 2. Second priority: If font actually contains the glyph (verified via CoreText), render it
            if let g = glyph, let scalar = UnicodeScalar(g),
               let glyphFont = NSFont(name: "WorkflowGlyphs-Regular", size: size * 0.58) {
                var glyphCode: CGGlyph = 0
                var chars = [UniChar(g)]
                let ctFont = glyphFont as CTFont
                if CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphCode, 1) && glyphCode != 0 {
                    let str = NSAttributedString(string: String(Character(scalar)), attributes: [
                        .font: glyphFont,
                        .foregroundColor: textColor
                    ])
                    let strSize = str.size()
                    let strRect = NSRect(
                        x: (size - strSize.width) / 2,
                        y: (size - strSize.height) / 2,
                        width: strSize.width,
                        height: strSize.height
                    )
                    str.draw(in: strRect)
                    return true
                }
            }

            // 3. Fallback: Default command symbol
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

            // 2. Second priority: Vector glyph font if verified present
            if let g = glyph, let scalar = UnicodeScalar(g),
               let glyphFont = NSFont(name: "WorkflowGlyphs-Regular", size: size * 0.58) {
                var glyphCode: CGGlyph = 0
                var chars = [UniChar(g)]
                let ctFont = glyphFont as CTFont
                if CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphCode, 1) && glyphCode != 0 {
                    let str = NSAttributedString(string: String(Character(scalar)), attributes: [
                        .font: glyphFont,
                        .foregroundColor: textColor
                    ])
                    let strSize = str.size()
                    let strRect = NSRect(
                        x: (size - strSize.width) / 2,
                        y: (size - strSize.height) / 2,
                        width: strSize.width,
                        height: strSize.height
                    )
                    str.draw(in: strRect)
                    return true
                }
            }

            // 3. Fallback to command
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
