import AppKit

public final class ShortcutsIconFactory {
    /// Creates the authentic Apple Shortcuts logo geometry (two vertically overlapping rounded diamonds)
    /// as a template image for the macOS menu bar.
    /// In Light Mode, AppKit renders this in dark graphite (#1D1D1F); in Dark Mode, it renders in pure white (#FFFFFF).
    public static func createMenuBarIcon(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let L: CGFloat = size * 0.44
            let r: CGFloat = L * 0.28

            let cx = size * 0.50
            let cyTop = size * 0.60
            let cyBottom = size * 0.40

            func diamondPath(cx: CGFloat, cy: CGFloat) -> CGPath {
                var transform = CGAffineTransform.identity
                    .translatedBy(x: cx, y: cy)
                    .rotated(by: CGFloat.pi / 4.0)
                return CGPath(
                    roundedRect: CGRect(x: -L/2, y: -L/2, width: L, height: L),
                    cornerWidth: r,
                    cornerHeight: r,
                    transform: &transform
                )
            }

            let topPath = diamondPath(cx: cx, cy: cyTop)
            let bottomPath = diamondPath(cx: cx, cy: cyBottom)

            // Draw bottom diamond in black for template rendering
            ctx.addPath(bottomPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // Negative mask gap separating top diamond from bottom diamond
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(size * 0.09)
            ctx.addPath(topPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Draw top diamond in black
            ctx.addPath(topPath)
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

            let L: CGFloat = size * 0.44
            let r: CGFloat = L * 0.28

            let cx = size * 0.50
            let cyTop = size * 0.60
            let cyBottom = size * 0.40

            func diamondPath(cx: CGFloat, cy: CGFloat) -> CGPath {
                var transform = CGAffineTransform.identity
                    .translatedBy(x: cx, y: cy)
                    .rotated(by: CGFloat.pi / 4.0)
                return CGPath(
                    roundedRect: CGRect(x: -L/2, y: -L/2, width: L, height: L),
                    cornerWidth: r,
                    cornerHeight: r,
                    transform: &transform
                )
            }

            let topPath = diamondPath(cx: cx, cy: cyTop)
            let bottomPath = diamondPath(cx: cx, cy: cyBottom)

            // Bottom diamond: Vibrant Blue to Violet/Magenta
            ctx.saveGState()
            ctx.addPath(bottomPath)
            ctx.clip()
            let bottomColors = [
                NSColor(red: 0.72, green: 0.30, blue: 0.90, alpha: 1.0).cgColor,
                NSColor(red: 0.22, green: 0.20, blue: 0.85, alpha: 1.0).cgColor
            ] as CFArray
            let botGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(botGrad, start: CGPoint(x: cx, y: cyBottom + L*0.7), end: CGPoint(x: cx, y: cyBottom - L*0.7), options: [])
            ctx.restoreGState()

            // Negative gap mask between shapes
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(size * 0.09)
            ctx.addPath(topPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Top diamond: Coral Pink to Magenta
            ctx.saveGState()
            ctx.addPath(topPath)
            ctx.clip()
            let topColors = [
                NSColor(red: 0.98, green: 0.45, blue: 0.48, alpha: 1.0).cgColor,
                NSColor(red: 0.62, green: 0.22, blue: 0.86, alpha: 1.0).cgColor
            ] as CFArray
            let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(topGrad, start: CGPoint(x: cx, y: cyTop + L*0.7), end: CGPoint(x: cx, y: cyTop - L*0.7), options: [])
            ctx.restoreGState()

            return true
        }

        img.isTemplate = false
        return img
    }

    /// Renders a complete high-res macOS Squircle Application Icon matching Apple official Shortcuts app design
    public static func createAppIcon(size: CGFloat = 512) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let margin = size * 0.105
            let canvasRect = rect.insetBy(dx: margin, dy: margin)
            let cornerRadius = size * 0.224

            // 1. Soft natural drop shadow under squircle
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.035),
                blur: size * 0.065,
                color: NSColor(red: 0.05, green: 0.02, blue: 0.12, alpha: 0.42).cgColor
            )
            let squircle = CGPath(roundedRect: canvasRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(squircle)
            ctx.setFillColor(NSColor(red: 0.14, green: 0.05, blue: 0.28, alpha: 1.0).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // 2. Official Deep Royal Purple Squircle Background
            ctx.saveGState()
            ctx.addPath(squircle)
            ctx.clip()

            let bgColors = [
                NSColor(red: 0.26, green: 0.10, blue: 0.52, alpha: 1.0).cgColor,
                NSColor(red: 0.15, green: 0.05, blue: 0.36, alpha: 1.0).cgColor,
                NSColor(red: 0.10, green: 0.03, blue: 0.24, alpha: 1.0).cgColor
            ] as CFArray
            let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 0.55, 1.0])!
            ctx.drawLinearGradient(bgGrad, start: CGPoint(x: size * 0.5, y: canvasRect.maxY), end: CGPoint(x: size * 0.5, y: canvasRect.minY), options: [])

            // Radial ambient top glow on squircle
            let glowColors = [
                NSColor(red: 0.45, green: 0.20, blue: 0.85, alpha: 0.35).cgColor,
                NSColor(red: 0.25, green: 0.10, blue: 0.55, alpha: 0.0).cgColor
            ] as CFArray
            let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0])!
            ctx.drawRadialGradient(
                glowGrad,
                startCenter: CGPoint(x: size * 0.5, y: canvasRect.maxY - size * 0.1),
                startRadius: 0,
                endCenter: CGPoint(x: size * 0.5, y: canvasRect.maxY - size * 0.1),
                endRadius: size * 0.5,
                options: []
            )

            // Subtle squircle rim highlight
            ctx.setLineWidth(size * 0.010)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.22).cgColor)
            ctx.addPath(squircle)
            ctx.strokePath()

            // 3. Central Shortcuts Diamonds (Two vertically overlapping rotated rounded squares)
            let L: CGFloat = size * 0.44
            let r: CGFloat = L * 0.29

            let cx = size * 0.50
            let cyTop = size * 0.580
            let cyBottom = size * 0.420

            func diamondPath(cx: CGFloat, cy: CGFloat) -> CGPath {
                var transform = CGAffineTransform.identity
                    .translatedBy(x: cx, y: cy)
                    .rotated(by: CGFloat.pi / 4.0)
                return CGPath(
                    roundedRect: CGRect(x: -L/2, y: -L/2, width: L, height: L),
                    cornerWidth: r,
                    cornerHeight: r,
                    transform: &transform
                )
            }

            let topPath = diamondPath(cx: cx, cy: cyTop)
            let bottomPath = diamondPath(cx: cx, cy: cyBottom)

            // A. Bottom Diamond Shadow
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.035),
                blur: size * 0.055,
                color: NSColor(red: 0.04, green: 0.01, blue: 0.12, alpha: 0.55).cgColor
            )
            ctx.addPath(bottomPath)
            ctx.setFillColor(NSColor(red: 0.20, green: 0.15, blue: 0.65, alpha: 0.8).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Bottom Diamond Gradient
            ctx.saveGState()
            ctx.addPath(bottomPath)
            ctx.clip()
            let bottomColors = [
                NSColor(red: 0.65, green: 0.28, blue: 0.88, alpha: 0.94).cgColor,
                NSColor(red: 0.28, green: 0.22, blue: 0.86, alpha: 0.94).cgColor,
                NSColor(red: 0.16, green: 0.32, blue: 0.88, alpha: 0.94).cgColor
            ] as CFArray
            let botGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0.0, 0.55, 1.0])!
            ctx.drawLinearGradient(botGrad, start: CGPoint(x: cx, y: cyBottom + L*0.65), end: CGPoint(x: cx, y: cyBottom - L*0.65), options: [])

            // Soft rim on bottom diamond
            ctx.setLineWidth(size * 0.006)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
            ctx.addPath(bottomPath)
            ctx.strokePath()
            ctx.restoreGState()

            // B. Top Diamond Shadow (casts onto bottom diamond and background)
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.028),
                blur: size * 0.045,
                color: NSColor(red: 0.06, green: 0.01, blue: 0.14, alpha: 0.50).cgColor
            )
            ctx.addPath(topPath)
            ctx.setFillColor(NSColor(red: 0.7, green: 0.2, blue: 0.5, alpha: 0.7).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Top Diamond Gradient (Frosted Glass Translucent)
            ctx.saveGState()
            ctx.addPath(topPath)
            ctx.clip()

            let topColors = [
                NSColor(red: 0.99, green: 0.44, blue: 0.46, alpha: 0.88).cgColor,
                NSColor(red: 0.88, green: 0.30, blue: 0.66, alpha: 0.88).cgColor,
                NSColor(red: 0.68, green: 0.25, blue: 0.85, alpha: 0.88).cgColor
            ] as CFArray
            let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0.0, 0.50, 1.0])!
            ctx.drawLinearGradient(topGrad, start: CGPoint(x: cx, y: cyTop + L*0.65), end: CGPoint(x: cx, y: cyTop - L*0.65), options: [])

            // Top Diamond Soft Specular Rim Highlight
            ctx.setLineWidth(size * 0.007)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
            ctx.addPath(topPath)
            ctx.strokePath()

            ctx.restoreGState() // restore topPath clip
            ctx.restoreGState() // restore squircle clip
            return true
        }

        return img
    }
}
