import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let inset = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
        let tile = NSBezierPath(roundedRect: inset, xRadius: size * 0.18, yRadius: size * 0.18)
        NSGradient(colors: [NSColor(red: 0.20, green: 0.32, blue: 0.95, alpha: 1), NSColor(red: 0.55, green: 0.20, blue: 0.90, alpha: 1)])!
            .draw(in: tile, angle: -60)
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let symbolSize = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2, width: symbolSize.width, height: symbolSize.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: output.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: output.appending(path: "icon_\(base)x\(base)@2x.png"))
}
