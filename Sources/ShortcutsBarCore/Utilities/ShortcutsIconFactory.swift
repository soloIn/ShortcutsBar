import AppKit

public final class ShortcutsIconFactory {
    /// Creates the authentic Apple Shortcuts logo geometry as a template image for the macOS menu bar.
    /// In Light Mode, AppKit renders this in dark graphite (#1D1D1F); in Dark Mode, it renders in pure white (#FFFFFF).
    public static func createMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let w = size * 0.52
            let h = size * 0.28
            let r = h / 2.0

            // 1. Top-left rhombus centered at (40%, 60%)
            let c1 = CGPoint(x: size * 0.40, y: size * 0.60)
            var t1 = CGAffineTransform.identity
                .translatedBy(x: c1.x, y: c1.y)
                .rotated(by: -CGFloat.pi / 4.0)
            let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

            // 2. Bottom-right rhombus centered at (60%, 40%)
            let c2 = CGPoint(x: size * 0.60, y: size * 0.40)
            var t2 = CGAffineTransform.identity
                .translatedBy(x: c2.x, y: c2.y)
                .rotated(by: -CGFloat.pi / 4.0)
            let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

            // Draw top shape in solid black for template rendering
            ctx.addPath(p1)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // Negative mask gap between shapes (gives authentic Apple Shortcuts overlap separation)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(size * 0.10)
            ctx.addPath(p1)
            ctx.strokePath()
            ctx.restoreGState()

            // Draw bottom shape in solid black
            ctx.addPath(p2)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            return true
        }

        img.isTemplate = true
        return img
    }

    /// Creates the colorful Apple Shortcuts logo for active running state
    public static func createRunningShortcutsIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let w = size * 0.52
            let h = size * 0.28
            let r = h / 2.0

            let c1 = CGPoint(x: size * 0.40, y: size * 0.60)
            var t1 = CGAffineTransform.identity.translatedBy(x: c1.x, y: c1.y).rotated(by: -CGFloat.pi / 4.0)
            let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

            let c2 = CGPoint(x: size * 0.60, y: size * 0.40)
            var t2 = CGAffineTransform.identity.translatedBy(x: c2.x, y: c2.y).rotated(by: -CGFloat.pi / 4.0)
            let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

            // Top shape: Apple Electric Cyan to Royal Blue (#00F0FF -> #0072FF)
            ctx.saveGState()
            ctx.addPath(p1)
            ctx.clip()
            let topColors = [
                NSColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(red: 0.0, green: 0.45, blue: 1.0, alpha: 1.0).cgColor
            ] as CFArray
            let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0, 1])!
            ctx.drawLinearGradient(topGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
            ctx.restoreGState()

            // Negative gap mask between shapes
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(size * 0.10)
            ctx.addPath(p1)
            ctx.strokePath()
            ctx.restoreGState()

            // Bottom shape: Apple Hot Pink to Electric Violet (#FF2A85 -> #9300FF)
            ctx.saveGState()
            ctx.addPath(p2)
            ctx.clip()
            let bottomColors = [
                NSColor(red: 1.0, green: 0.16, blue: 0.52, alpha: 1.0).cgColor,
                NSColor(red: 0.58, green: 0.0, blue: 1.0, alpha: 1.0).cgColor
            ] as CFArray
            let bottomGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0, 1])!
            ctx.drawLinearGradient(bottomGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
            ctx.restoreGState()

            return true
        }

        img.isTemplate = false
        return img
    }

    /// Renders a complete high-res macOS Squircle Application Icon aligned with Apple official design language
    public static func createAppIcon(size: CGFloat = 512) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let margin = size * 0.10
            let canvasRect = rect.insetBy(dx: margin, dy: margin)
            let cornerRadius = size * 0.22

            // 1. Shadow under squircle canvas
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.035),
                blur: size * 0.07,
                color: NSColor(white: 0.0, alpha: 0.45).cgColor
            )
            let squircle = CGPath(roundedRect: canvasRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(squircle)
            ctx.setFillColor(NSColor(red: 0.14, green: 0.04, blue: 0.29, alpha: 1.0).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // 2. Official Deep Royal Purple Gradient Background (#4C1D95 -> #240B4A)
            ctx.saveGState()
            ctx.addPath(squircle)
            ctx.clip()
            let bgColors = [
                NSColor(red: 0.30, green: 0.11, blue: 0.58, alpha: 1.0).cgColor,
                NSColor(red: 0.14, green: 0.04, blue: 0.29, alpha: 1.0).cgColor
            ] as CFArray
            let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

            // Top rim specular highlight (macOS Sonoma / Sequoia continuous curvature)
            ctx.setLineWidth(size * 0.015)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.22).cgColor)
            ctx.addPath(squircle)
            ctx.strokePath()

            // 3. Subtle Automation Orbit Ring
            ctx.saveGState()
            let orbitCenter = CGPoint(x: size / 2, y: size / 2)
            let orbitRadius = size * 0.34
            ctx.setLineWidth(size * 0.006)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
            let dashPattern: [CGFloat] = [size * 0.015, size * 0.022]
            ctx.setLineDash(phase: 0, lengths: dashPattern)
            ctx.addArc(center: orbitCenter, radius: orbitRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()

            // 4. Central Shortcuts Rhombuses (75% Canvas Occupancy)
            let glyphSize = size * 0.74
            let glyphOrigin = CGPoint(x: (size - glyphSize) / 2, y: (size - glyphSize) / 2)

            ctx.saveGState()
            ctx.translateBy(x: glyphOrigin.x, y: glyphOrigin.y)

            let w = glyphSize * 0.54
            let h = glyphSize * 0.30
            let r = h / 2.0

            let c1 = CGPoint(x: glyphSize * 0.40, y: glyphSize * 0.60)
            var t1 = CGAffineTransform.identity.translatedBy(x: c1.x, y: c1.y).rotated(by: -CGFloat.pi / 4.0)
            let p1 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t1)

            let c2 = CGPoint(x: glyphSize * 0.60, y: glyphSize * 0.40)
            var t2 = CGAffineTransform.identity.translatedBy(x: c2.x, y: c2.y).rotated(by: -CGFloat.pi / 4.0)
            let p2 = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: &t2)

            // Drop shadow under glyph
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.025),
                blur: size * 0.04,
                color: NSColor(white: 0.0, alpha: 0.40).cgColor
            )

            // Top shape: Apple Electric Cyan to Royal Blue (#00F0FF -> #0072FF)
            ctx.saveGState()
            ctx.addPath(p1)
            ctx.clip()
            let topColors = [
                NSColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(red: 0.0, green: 0.45, blue: 1.0, alpha: 1.0).cgColor
            ] as CFArray
            let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0, 1])!
            ctx.drawLinearGradient(topGrad, start: CGPoint(x: 0, y: glyphSize), end: CGPoint(x: glyphSize, y: 0), options: [])
            ctx.restoreGState()

            // Negative gap mask between shapes
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(glyphSize * 0.075)
            ctx.addPath(p1)
            ctx.strokePath()
            ctx.restoreGState()

            // Bottom shape: Apple Hot Pink to Electric Violet (#FF2A85 -> #9300FF)
            ctx.saveGState()
            ctx.addPath(p2)
            ctx.clip()
            let bottomColors = [
                NSColor(red: 1.0, green: 0.16, blue: 0.52, alpha: 1.0).cgColor,
                NSColor(red: 0.58, green: 0.0, blue: 1.0, alpha: 1.0).cgColor
            ] as CFArray
            let bottomGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0, 1])!
            ctx.drawLinearGradient(bottomGrad, start: CGPoint(x: 0, y: glyphSize), end: CGPoint(x: glyphSize, y: 0), options: [])
            ctx.restoreGState()

            ctx.restoreGState() // restore glyph translation
            ctx.restoreGState() // restore squircle clip

            return true
        }

        return img
    }
}
