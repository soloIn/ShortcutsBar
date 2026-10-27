import AppKit
import ObjectiveC

@MainActor
public final class ShortcutIconRenderer {
    public static let shared = ShortcutIconRenderer()

    private let cache = NSCache<NSString, NSImage>()
    private var isPrivateFrameworkLoaded = false

    private var iconClass: AnyClass?
    private var drawerClass: AnyClass?

    public init() {
        loadFrameworks()
    }

    private func loadFrameworks() {
        dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_NOW)
        dlopen("/System/Library/PrivateFrameworks/WorkflowUICore.framework/WorkflowUICore", RTLD_NOW)

        iconClass = NSClassFromString("WFWorkflowIcon")
        drawerClass = NSClassFromString("WFWorkflowIconDrawer")
        isPrivateFrameworkLoaded = (iconClass != nil && drawerClass != nil)
    }

    public func icon(for item: ShortcutItem, size: CGFloat = 16) -> NSImage {
        let cacheKey = "\(item.name)_\(item.glyph ?? 0)_\(item.colorValue ?? 0)_\(Int(size))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let rendered: NSImage
        if let glyph = item.glyph, let color = item.colorValue, let sysIcon = renderSystemIcon(glyph: glyph, color: color, size: size) {
            rendered = sysIcon
        } else if let color = item.colorValue {
            rendered = renderFallbackSquircle(name: item.name, colorValue: color, size: size)
        } else {
            rendered = renderDefaultIcon(size: size)
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

    private func renderFallbackSquircle(name: String, colorValue: Int64, size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = CGFloat((colorValue >> 24) & 0xFF) / 255.0
            let g = CGFloat((colorValue >> 16) & 0xFF) / 255.0
            let b = CGFloat((colorValue >> 8) & 0xFF) / 255.0
            let color = NSColor(red: r, green: g, blue: b, alpha: 1.0)

            let cornerRadius = size * 0.26
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            color.setFill()
            path.fill()

            let initial = String(name.prefix(1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.55, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: initial, attributes: attributes)
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

    private func renderDefaultIcon(size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let cornerRadius = size * 0.26
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.systemBlue.setFill()
            path.fill()

            if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil) {
                let symbolRect = NSRect(x: size * 0.2, y: size * 0.2, width: size * 0.6, height: size * 0.6)
                symbol.draw(in: symbolRect)
            }
            return true
        }
    }
}
