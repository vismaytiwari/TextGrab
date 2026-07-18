import AppKit

// The TextGrab mark: viewfinder corner brackets around three "text" lines —
// i.e. "grab the text inside a selection". Drawn with vector paths so it stays
// crisp at any size and works as a monochrome menu bar template.
enum Icon {
    static func drawMark(in rect: CGRect, lineWidth: CGFloat, color: NSColor) {
        color.set()
        let r = rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05)
        let arm = r.width * 0.28 // length of each corner bracket arm

        let brackets = NSBezierPath()
        brackets.lineWidth = lineWidth
        brackets.lineCapStyle = .round
        brackets.lineJoinStyle = .round
        // top-left
        brackets.move(to: CGPoint(x: r.minX, y: r.maxY - arm))
        brackets.line(to: CGPoint(x: r.minX, y: r.maxY))
        brackets.line(to: CGPoint(x: r.minX + arm, y: r.maxY))
        // top-right
        brackets.move(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        brackets.line(to: CGPoint(x: r.maxX, y: r.maxY))
        brackets.line(to: CGPoint(x: r.maxX, y: r.maxY - arm))
        // bottom-right
        brackets.move(to: CGPoint(x: r.maxX, y: r.minY + arm))
        brackets.line(to: CGPoint(x: r.maxX, y: r.minY))
        brackets.line(to: CGPoint(x: r.maxX - arm, y: r.minY))
        // bottom-left
        brackets.move(to: CGPoint(x: r.minX + arm, y: r.minY))
        brackets.line(to: CGPoint(x: r.minX, y: r.minY))
        brackets.line(to: CGPoint(x: r.minX, y: r.minY + arm))
        brackets.stroke()

        // three text lines, centered
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

    // Monochrome template image for the menu bar (adapts to light/dark).
    static func menuBar() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        drawMark(in: CGRect(origin: .zero, size: size), lineWidth: 1.3, color: .black)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
