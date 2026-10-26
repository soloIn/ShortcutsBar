import AppKit

public final class ShortcutsIconFactory {
    /// Creates the authentic Shortcuts logo geometry as a template image for the macOS menu bar
    public static func createMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let w = size * 0.48
        let h = size * 0.28
        let r = h / 2.0

        // 1. Top-left rhombus centered at (38%, 62%)
        let c1 = CGPoint(x: size * 0.38, y: size * 0.62)
        var t1 = CGAffineTransform.identity
            .translatedBy(x: c1.x, y: c1.y)
            .rotated(by: -CGFloat.pi / 4.0)
        let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

        // 2. Bottom-right rhombus centered at (62%, 38%)
        let c2 = CGPoint(x: size * 0.62, y: size * 0.38)
        var t2 = CGAffineTransform.identity
            .translatedBy(x: c2.x, y: c2.y)
            .rotated(by: -CGFloat.pi / 4.0)
        let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

        // Draw top shape
        ctx.addPath(p1)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()

        // Negative mask gap between shapes (gives authentic Apple Shortcuts overlap separation)
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(size * 0.09)
        ctx.addPath(p1)
        ctx.strokePath()
        ctx.restoreGState()

        // Draw bottom shape
        ctx.addPath(p2)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    /// Creates the colorful Shortcuts logo for active running state
    public static func createRunningShortcutsIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let w = size * 0.48
        let h = size * 0.28
        let r = h / 2.0

        let c1 = CGPoint(x: size * 0.38, y: size * 0.62)
        var t1 = CGAffineTransform.identity.translatedBy(x: c1.x, y: c1.y).rotated(by: -CGFloat.pi / 4.0)
        let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

        let c2 = CGPoint(x: size * 0.62, y: size * 0.38)
        var t2 = CGAffineTransform.identity.translatedBy(x: c2.x, y: c2.y).rotated(by: -CGFloat.pi / 4.0)
        let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

        // Top shape: Electric Cyan / Blue (#00E5FF -> #2979FF)
        ctx.saveGState()
        ctx.addPath(p1)
        ctx.clip()
        let topColors = [NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0).cgColor, NSColor(red: 0.16, green: 0.47, blue: 1.0, alpha: 1.0).cgColor] as CFArray
        let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0, 1])!
        ctx.drawLinearGradient(topGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        ctx.restoreGState()

        // Mask gap
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(size * 0.09)
        ctx.addPath(p1)
        ctx.strokePath()
        ctx.restoreGState()

        // Bottom shape: Vivid Indigo / Purple (#7C4DFF -> #D500F9)
        ctx.saveGState()
        ctx.addPath(p2)
        ctx.clip()
        let bottomColors = [NSColor(red: 0.48, green: 0.30, blue: 1.0, alpha: 1.0).cgColor, NSColor(red: 0.83, green: 0.0, blue: 0.97, alpha: 1.0).cgColor] as CFArray
        let bottomGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0, 1])!
        ctx.drawLinearGradient(bottomGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        ctx.restoreGState()

        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// Renders a complete high-res macOS Squircle Application Icon with distinctive theme colors
    public static func createAppIcon(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let margin = size * 0.10
        let canvasRect = rect.insetBy(dx: margin, dy: margin)
        let cornerRadius = size * 0.22

        // 1. Shadow under canvas
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.08, color: NSColor(white: 0.0, alpha: 0.45).cgColor)
        let squircle = CGPath(roundedRect: canvasRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(squircle)
        ctx.setFillColor(NSColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Deep Obsidian Gradient Background
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        let bgColors = [
            NSColor(red: 0.15, green: 0.18, blue: 0.26, alpha: 1.0).cgColor,
            NSColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1.0).cgColor
        ] as CFArray
        let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

        // Outer subtle border
        ctx.setLineWidth(size * 0.015)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
        ctx.addPath(squircle)
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Central Shortcuts Rhombuses (Electric Cyan + Vibrant Purple)
        let glyphSize = size * 0.58
        let glyphOrigin = CGPoint(x: (size - glyphSize) / 2, y: (size - glyphSize) / 2)

        ctx.saveGState()
        ctx.translateBy(x: glyphOrigin.x, y: glyphOrigin.y)

        let w = glyphSize * 0.48
        let h = glyphSize * 0.28
        let r = h / 2.0

        let c1 = CGPoint(x: glyphSize * 0.38, y: glyphSize * 0.62)
        var t1 = CGAffineTransform.identity.translatedBy(x: c1.x, y: c1.y).rotated(by: -CGFloat.pi / 4.0)
        let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

        let c2 = CGPoint(x: glyphSize * 0.62, y: glyphSize * 0.38)
        var t2 = CGAffineTransform.identity.translatedBy(x: c2.x, y: c2.y).rotated(by: -CGFloat.pi / 4.0)
        let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

        // Top shape: Electric Cyan to Neon Teal (#00E5FF -> #00E676)
        ctx.saveGState()
        ctx.addPath(p1)
        ctx.clip()
        let topColors = [
            NSColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 1.0).cgColor,
            NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0).cgColor
        ] as CFArray
        let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0, 1])!
        ctx.drawLinearGradient(topGrad, start: CGPoint(x: 0, y: glyphSize), end: CGPoint(x: glyphSize, y: 0), options: [])
        ctx.restoreGState()

        // Mask gap between shapes
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(glyphSize * 0.08)
        ctx.addPath(p1)
        ctx.strokePath()
        ctx.restoreGState()

        // Bottom shape: Royal Indigo to Electric Violet (#651FFF -> #E040FB)
        ctx.saveGState()
        ctx.addPath(p2)
        ctx.clip()
        let bottomColors = [
            NSColor(red: 0.40, green: 0.12, blue: 1.0, alpha: 1.0).cgColor,
            NSColor(red: 0.88, green: 0.25, blue: 0.98, alpha: 1.0).cgColor
        ] as CFArray
        let bottomGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0, 1])!
        ctx.drawLinearGradient(bottomGrad, start: CGPoint(x: 0, y: glyphSize), end: CGPoint(x: glyphSize, y: 0), options: [])
        ctx.restoreGState()

        ctx.restoreGState()

        img.unlockFocus()
        return img
    }
}
