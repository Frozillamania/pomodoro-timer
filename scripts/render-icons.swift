import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("POMODORO-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func draw(size: Int, template: Bool) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = template ? 400 : 300
    if !template {
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
        NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.52, alpha: 1))!.draw(in: tile, angle: 80)
        NSColor(white: 0.91, alpha: 0.45).setStroke()
        tile.lineWidth = 4
        tile.stroke()
        let face = NSBezierPath(ovalIn: NSRect(x: 176, y: 176, width: 672, height: 672))
        NSGradient(starting: NSColor(white: 0.15, alpha: 1), ending: NSColor(white: 0.31, alpha: 1))!.draw(in: face, angle: 90)
        NSColor(white: 0.93, alpha: 0.24).setStroke()
        face.lineWidth = 3
        face.stroke()
    }
    let rim = NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
    NSColor(white: template ? 0 : 0.94, alpha: template ? 1 : 0.85).setStroke()
    rim.lineWidth = template ? 62 : 9
    rim.stroke()
    let sector = NSBezierPath()
    sector.move(to: center)
    sector.line(to: NSPoint(x: 512, y: 512 + radius - (template ? 90 : 33)))
    sector.appendArc(withCenter: center, radius: radius - (template ? 90 : 33), startAngle: 90, endAngle: 0, clockwise: true)
    sector.close()
    (template ? NSColor.black : NSColor(srgbRed: 0.79, green: 0.35, blue: 0.37, alpha: 1)).setFill()
    sector.fill()
    if !template {
        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: 512 + sin(angle) * 278, y: 512 + cos(angle) * 278))
            tick.line(to: NSPoint(x: 512 + sin(angle) * 292, y: 512 + cos(angle) * 292))
            NSColor(white: 0.95, alpha: 0.75).setStroke()
            tick.lineWidth = 5
            tick.lineCapStyle = .round
            tick.stroke()
        }
        NSColor(white: 0.90, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 495, y: 495, width: 34, height: 34)).fill()
    }
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try draw(size: size * scale, template: false).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
try draw(size: 1024, template: false).write(to: assets.appendingPathComponent("AppIcon.png"))
try draw(size: 36, template: true).write(to: assets.appendingPathComponent("MenuBarIcon.png"))
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("POMODORO.icns").path]
try tool.run()
tool.waitUntilExit()
precondition(tool.terminationStatus == 0, "App icon conversion failed")
print("Rendered app icon and 18pt Retina menu bar template")
