import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("usage: make_icon output.png\n", stderr)
    exit(1)
}

_ = NSApplication.shared

let pixels = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("bitmap failed\n", stderr)
    exit(1)
}
rep.size = NSSize(width: pixels, height: pixels)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
NSColor(srgbRed: 0.122, green: 0.106, blue: 0.086, alpha: 1).setFill()
canvas.fill()
let circle = NSBezierPath(ovalIn: canvas.insetBy(dx: 150, dy: 150))
NSColor(srgbRed: 0.878, green: 0.710, blue: 0.416, alpha: 1).setFill()
circle.fill()

let text = "休" as NSString
let font = NSFont.systemFont(ofSize: 520, weight: .semibold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(srgbRed: 0.122, green: 0.106, blue: 0.086, alpha: 1),
]
let textSize = text.size(withAttributes: attributes)
let textRect = NSRect(
    x: (CGFloat(pixels) - textSize.width) / 2,
    y: (CGFloat(pixels) - textSize.height) / 2 - 28,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("png failed\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
