import AppKit
import Foundation

// Icono de Agent Deck: placa oscura con cuatro teclas, una dorada. Genera el iconset y el .icns.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var iconChunks = Data()
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
        let base = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 205, yRadius: 205)
        NSGradient(colors: [NSColor(calibratedRed: 0.031, green: 0.035, blue: 0.043, alpha: 1),
                            NSColor(calibratedRed: 0.11, green: 0.114, blue: 0.18, alpha: 1)])!
            .draw(in: base, angle: 90)
        NSColor.white.withAlphaComponent(0.07).setStroke(); base.lineWidth = 3; base.stroke()
        let gold = NSColor(calibratedRed: 0.89, green: 0.788, blue: 0.541, alpha: 1)
        let tile = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.24, alpha: 1)
        let positions: [(CGFloat, CGFloat)] = [(200, 540), (540, 540), (200, 200), (540, 200)]
        for (i, p) in positions.enumerated() {
            let r = NSBezierPath(roundedRect: NSRect(x: p.0, y: p.1, width: 284, height: 284), xRadius: 56, yRadius: 56)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
            (i == 0 ? gold : tile).setFill(); r.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(i == 0 ? 0.35 : 0.12).setStroke(); r.lineWidth = 3; r.stroke()
        }
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
