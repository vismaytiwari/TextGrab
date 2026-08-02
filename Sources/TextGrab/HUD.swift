import AppKit

// A small floating toast shown at the selection that confirms the grab.
//
// It deliberately never shows the captured pixels: the whole point of TextGrab
// is that you get text, not a screenshot, so putting a thumbnail of what you
// just grabbed on screen defeats it. Non-activating, so it never steals focus.
//
// Turn it off entirely with "Show Confirmation" in the menu.
enum HUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(success: Bool, text: String) {
        DispatchQueue.main.async { present(success: success, text: text) }
    }

    private static func present(success: Bool, text: String) {
        hideWork?.cancel()

        let leading = NSImageView()
        leading.image = NSImage(systemSymbolName: success ? "checkmark.circle.fill" : "xmark.circle.fill",
                                accessibilityDescription: nil)
        leading.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        leading.contentTintColor = success ? .systemGreen : .systemOrange
        leading.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: success ? "Copied to clipboard" : "No text found")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            success ? snippet(text) : "Couldn't read any text in that region.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 3
        body.lineBreakMode = .byTruncatingTail
        body.preferredMaxLayoutWidth = 320

        let textStack = NSStackView(views: [title, body])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [leading, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 18)
        row.translatesAutoresizingMaskIntoConstraints = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            row.topAnchor.constraint(equalTo: blur.topAnchor),
            row.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        let size = row.fittingSize
        blur.frame = CGRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = blur

        // Show the toast at the selection — just below where the cursor released —
        // clamped to the screen the pointer is on so it never runs off-screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame ?? .zero
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 16
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    private static func dismiss() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private static func snippet(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= 140 ? flat : String(flat.prefix(140)) + "…"
    }
}
