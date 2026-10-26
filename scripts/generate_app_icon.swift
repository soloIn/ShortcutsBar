import AppKit
import Foundation

// Renders the macOS Squircle Application Icon with Electric Cyan & Vivid Violet Shortcuts rhombuses
func createAppIcon(size: CGFloat) -> NSImage {
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

func savePNG(image: NSImage, targetPixelSize: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetPixelSize,
        pixelsHigh: targetPixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: targetPixelSize, height: targetPixelSize)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = context

    let rendered = createAppIcon(size: CGFloat(targetPixelSize))
    rendered.draw(in: NSRect(x: 0, y: 0, width: targetPixelSize, height: targetPixelSize))

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: url)
    }
}

let fm = FileManager.default
let iconsetURL = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let fileURL = iconsetURL.appendingPathComponent(name)
    savePNG(image: createAppIcon(size: CGFloat(px)), targetPixelSize: px, to: fileURL)
}

print("Generated iconset successfully.")
