import AppKit
import Foundation

// Icono de Agent Bar: la marca de getagentbar.com (la barra con dos puntos y la tecla naranja) sobre una placa
// grafito con la retícula de iconos de macOS (824 px de 1024, sombra suave). Genera el iconset y el .icns.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var iconChunks = Data()
func rgb(_ h: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a) }
func drawIcon() {
    // placa: retícula de macOS (824×824 centrada, radio ~185) con sombra de contacto
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let base = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow(); drop.shadowColor = NSColor.black.withAlphaComponent(0.32); drop.shadowBlurRadius = 22; drop.shadowOffset = NSSize(width: 0, height: -10); drop.set()
    rgb(0x161618).setFill(); base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0x2c2c30), rgb(0x161618), rgb(0x0c0c0d)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: base, angle: -90)
    // luz naranja muy tenue bajo la tecla
    NSGraphicsContext.saveGraphicsState(); base.addClip()
    NSGradient(colors: [rgb(0xff5b1f, 0.22), rgb(0xff5b1f, 0)])!.draw(fromCenter: NSPoint(x: 662, y: 470), radius: 0, toCenter: NSPoint(x: 662, y: 470), radius: 420, options: [])
    NSGraphicsContext.restoreGraphicsState()
    // filo superior de luz
    NSGraphicsContext.saveGraphicsState(); base.addClip()
    let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5), xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0.02), NSColor.white.withAlphaComponent(0)], atLocations: [0, 0.35, 1], colorSpace: .sRGB)!
        .draw(in: rim, angle: -90)
    rgb(0x161618).setFill()
    NSBezierPath(roundedRect: plate.insetBy(dx: 4, dy: 4), xRadius: 182, yRadius: 182).fill()
    NSGradient(colors: [rgb(0x2a2a2e), rgb(0x151517), rgb(0x0c0c0d)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: NSBezierPath(roundedRect: plate.insetBy(dx: 4, dy: 4), xRadius: 182, yRadius: 182), angle: -90)
    NSGradient(colors: [rgb(0xff5b1f, 0.20), rgb(0xff5b1f, 0)])!.draw(fromCenter: NSPoint(x: 662, y: 470), radius: 0, toCenter: NSPoint(x: 662, y: 470), radius: 400, options: [])
    NSGraphicsContext.restoreGraphicsState()
    // la barra: cápsula en relieve
    let bar = NSRect(x: 172, y: 372, width: 680, height: 280)
    let barPath = NSBezierPath(roundedRect: bar, xRadius: 140, yRadius: 140)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.6); sh.shadowBlurRadius = 34; sh.shadowOffset = NSSize(width: 0, height: -16); sh.set()
    rgb(0x232326).setFill(); barPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0x3a3a3f), rgb(0x232326), rgb(0x1a1a1c)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: barPath, angle: -90)
    NSGraphicsContext.saveGraphicsState(); barPath.addClip()
    let hl = NSBezierPath(roundedRect: bar.insetBy(dx: 2, dy: 2), xRadius: 138, yRadius: 138)
    hl.lineWidth = 4; NSColor.white.withAlphaComponent(0.16).setStroke(); hl.stroke()
    NSGraphicsContext.restoreGraphicsState()
    // dos teclas: puntos claros
    for x in [312.0, 452.0] {
        let d = NSBezierPath(ovalIn: NSRect(x: x - 34, y: 512 - 34, width: 68, height: 68))
        NSGradient(colors: [rgb(0xffffff), rgb(0xd9d9d4)])!.draw(in: d, angle: -90)
    }
    // la tecla naranja
    let key = NSRect(x: 552, y: 432, width: 220, height: 160)
    let keyPath = NSBezierPath(roundedRect: key, xRadius: 80, yRadius: 80)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = rgb(0xff5b1f, 0.75); glow.shadowBlurRadius = 46; glow.shadowOffset = .zero; glow.set()
    rgb(0xff5b1f).setFill(); keyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0xff8a50), rgb(0xff5b1f), rgb(0xe8460f)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: keyPath, angle: -90)
    NSGraphicsContext.saveGraphicsState(); keyPath.addClip()
    let khl = NSBezierPath(roundedRect: key.insetBy(dx: 2, dy: 2), xRadius: 78, yRadius: 78)
    khl.lineWidth = 4; NSColor.white.withAlphaComponent(0.35).setStroke(); khl.stroke()
    NSGraphicsContext.restoreGraphicsState()
}
func networkInteger(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}
let chunkTypes = ["16-1":"icp4", "16-2":"ic11", "32-1":"icp5", "32-2":"ic12",
                  "128-1":"ic07", "128-2":"ic13", "256-1":"ic08", "256-2":"ic14",
                  "512-1":"ic09", "512-2":"ic10"]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: destination.appendingPathComponent(name))
        iconChunks.append(Data(chunkTypes["\(size)-\(scale)"]!.utf8))
        iconChunks.append(networkInteger(png.count + 8))
        iconChunks.append(png)
    }
}
if CommandLine.arguments.count > 2 {
    var icon = Data("icns".utf8)
    icon.append(networkInteger(iconChunks.count + 8))
    icon.append(iconChunks)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
