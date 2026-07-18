import AppKit

// Renders the TextGrab app icon (a blue→purple squircle with the white mark)
// into an .iconset directory. Run via `make icon`, which then packs it to .icns.
// drawMark is duplicated from Sources/TextGrab/Icon.swift so this script stays
// self-contained (the `swift` interpreter runs a single file).

func drawMark(in rect: CGRect, lineWidth: CGFloat, color: NSColor) {
    color.set()
    let r = rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05)
    let arm = r.width * 0.28

    let brackets = NSBezierPath()
    brackets.lineWidth = lineWidth
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    brackets.move(to: CGPoint(x: r.minX, y: r.maxY - arm))
    brackets.line(to: CGPoint(x: r.minX, y: r.maxY))
    brackets.line(to: CGPoint(x: r.minX + arm, y: r.maxY))
    brackets.move(to: CGPoint(x: r.maxX - arm, y: r.maxY))
    brackets.line(to: CGPoint(x: r.maxX, y: r.maxY))
    brackets.line(to: CGPoint(x: r.maxX, y: r.maxY - arm))
    brackets.move(to: CGPoint(x: r.maxX, y: r.minY + arm))
    brackets.line(to: CGPoint(x: r.maxX, y: r.minY))
    brackets.line(to: CGPoint(x: r.maxX - arm, y: r.minY))
    brackets.move(to: CGPoint(x: r.minX + arm, y: r.minY))
    brackets.line(to: CGPoint(x: r.minX, y: r.minY))
    brackets.line(to: CGPoint(x: r.minX, y: r.minY + arm))
    brackets.stroke()

    let gap = r.height * 0.19
    let ys = [r.midY + gap, r.midY, r.midY - gap]
    let widths: [CGFloat] = [0.50, 0.50, 0.32]
    for (i, y) in ys.enumerated() {
        let w = r.width * widths[i]
        let line = NSBezierPath()
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.move(to: CGPoint(x: r.midX - w / 2, y: y))
        line.line(to: CGPoint(x: r.midX + w / 2, y: y))
        line.stroke()
    }
}

func render(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let rect = canvas.insetBy(dx: size * 0.10, dy: size * 0.10)
    let bg = NSBezierPath(roundedRect: rect,
                          xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.49, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.51, green: 0.30, blue: 0.94, alpha: 1),
    ])!
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    gradient.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let markSize = rect.width * 0.50
    let markRect = CGRect(x: rect.midX - markSize / 2, y: rect.midY - markSize / 2,
                          width: markSize, height: markSize)
    drawMark(in: markRect, lineWidth: max(1, size * 0.026), color: .white)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let dir = "Resources/TextGrab.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in sizes {
    try! render(px: px).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
print("Generated \(sizes.count) images in \(dir)")
