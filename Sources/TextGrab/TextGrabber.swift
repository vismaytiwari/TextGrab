import AppKit
import ScreenCaptureKit
import Vision

/// Copying a picture has three outcomes, and cancelling is not an error.
enum CopyResult {
    case copied
    case cancelled
    case failed
}

enum GrabResult {
    case copied(String)  // recognized text; the pixels are discarded immediately
    case empty           // a region was captured but no text was found
    case cancelled       // user pressed Esc / made no selection
}

/// What a region capture came back with. A cancellation and a failure look the
/// same from outside and must not be treated the same.
private enum RegionCapture {
    case image(CGImage)
    case cancelled
    case failed
}

enum TextGrabber {
    // Drags out a region, OCRs those pixels, and leaves the recognized text on
    // the clipboard.
    static func captureAndCopy(codeMode: Bool = true) -> GrabResult {
        // The pixels never leave memory, and nothing but the text is ever put on
        // the pasteboard.
        //
        // `screencapture -c` used to put the screenshot itself on the pasteboard
        // before the text replaced it, and that is all a clipboard manager — or
        // anything syncing the clipboard to another device — needs to record a
        // screenshot you never meant to take. Going through a private file fixed
        // that; capturing straight to a CGImage removes even that copy.
        switch captureRegion(dimmed: true) {
        case .image(let image):
            let text = recognize(image, codeMode: codeMode)
            guard !text.isEmpty else { return .empty }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            return .copied(text)
        case .cancelled, .failed:
            // There is no failure case to report a failure through, and the
            // reason is already in the log either way.
            return .cancelled
        }
    }

    /// Region screenshot to the clipboard, silently. Same job as macOS's own
    /// "copy picture of selection" shortcut, minus the shutter sound, which the
    /// system version only loses together with every other UI sound.
    ///
    /// Unlike a text grab, the image is meant to land on the clipboard here:
    /// this is the path that feeds a picture to another application.
    ///
    /// Cancelling the selection is not a failure — Esc, a right-click or a click
    /// with no drag leaves the clipboard alone, which is the right outcome and
    /// should not be reported as an error.
    static func copyRegionToClipboard() -> CopyResult {
        switch captureRegion(dimmed: false) {
        case .image(let image):
            // PNG, because that is the format macOS's own screenshot copy leaves
            // on the pasteboard and what every reader of it expects to find.
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                NSLog("TextGrab: could not encode the captured region")
                return .failed
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            return .copied
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        }
    }

    /// Development tool: captures a known rectangle and reports what came back.
    /// Prints only sizes, never pixels.
    static func captureSelfTest() -> Int32 {
        _ = NSApplication.shared
        print("preflight granted: \(CGPreflightScreenCaptureAccess())")
        guard let screen = NSScreen.main else {
            print("no main screen")
            return 1
        }
        // A rectangle near the top-left of the main display, in the same global
        // bottom-left coordinates a real selection arrives in.
        let rect = CGRect(x: screen.frame.minX + 40,
                          y: screen.frame.maxY - 140,
                          width: 320,
                          height: 100)
        print("screen \(screen.frame.integral) scale \(screen.backingScaleFactor); selecting \(rect.integral)")
        guard let image = capture(RegionSelector.Selection(rect: rect, screen: screen)) else {
            print("capture returned nil")
            return 1
        }
        print("captured \(image.width)x\(image.height) px (expected \(Int(rect.width * screen.backingScaleFactor))x\(Int(rect.height * screen.backingScaleFactor)))")
        let text = recognize(image, codeMode: false)
        print("ocr found \(text.count) characters")
        // The image path does one more thing than the text path: it encodes to
        // PNG. Checked here without touching the pasteboard, which belongs to
        // whoever is using the machine.
        if let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            print("png encode ok: \(png.count) bytes")
        } else {
            print("png encode FAILED")
        }
        return 0
    }

    /// The one selector and the one capture that both hot keys go through.
    private static func captureRegion(dimmed: Bool) -> RegionCapture {
        // ScreenCaptureKit's first call without the grant can sit behind the
        // system permission prompt and never come back, with an overlay left on
        // screen in front of it. CoreGraphics answers immediately and never
        // prompts, so it is asked before anything is drawn.
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("TextGrab: no Screen Recording permission — grant it in System Settings › Privacy & Security › Screen Recording")
            return .failed
        }
        guard let selection = RegionSelector.select(dimmed: dimmed) else { return .cancelled }
        guard let image = capture(selection) else { return .failed }
        return .image(image)
    }

    /// The selected points, read out of the window server as native pixels.
    ///
    /// The configuration is sized in pixels while a selection is in points, so
    /// the display's scale factor is what keeps a Retina grab at full
    /// resolution. A capture scaled down to points is where an `l` stops being
    /// distinguishable from a `1`, which is the whole job of the app.
    private static func capture(_ selection: RegionSelector.Selection) -> CGImage? {
        let screen = selection.screen
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            NSLog("TextGrab: the selected screen has no display id")
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        // NSScreen measures from the bottom-left corner of the whole desktop and
        // ScreenCaptureKit from the top-left corner of the one display it is
        // capturing, so both the origin and the direction have to be converted.
        let source = CGRect(x: selection.rect.minX - screen.frame.minX,
                            y: screen.frame.maxY - selection.rect.maxY,
                            width: selection.rect.width,
                            height: selection.rect.height)
        let scale = screen.backingScaleFactor

        var image: CGImage?
        let done = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content = content,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                NSLog("TextGrab: could not find the display to capture: \(String(describing: error))")
                done.signal()
                return
            }
            // Our own windows are excluded as well as ordered out, so a
            // confirmation toast still fading out cannot end up inside the
            // pixels it was confirming.
            let ours = content.windows.filter { $0.owningApplication?.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingWindows: ours)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = source
            configuration.width = Int((source.width * scale).rounded())
            configuration.height = Int((source.height * scale).rounded())
            configuration.captureResolution = .best
            // Both off, or the region would be letterboxed into that size
            // instead of filling it, and the pixels would no longer line up with
            // what was dragged.
            configuration.scalesToFit = false
            configuration.preservesAspectRatio = false
            // The pointer is not part of what was selected, and a cursor baked
            // into the image is exactly the screenshot tell being avoided here.
            configuration.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { captured, error in
                if captured == nil {
                    NSLog("TextGrab: screen capture failed: \(String(describing: error))")
                }
                image = captured
                done.signal()
            }
        }
        // Both callers are already on a background queue, so this waits on
        // nothing that was not being waited on anyway. A capture that never
        // called back would strand the thread and the hot key with it, and no
        // screenshot has ever taken five seconds.
        guard done.wait(timeout: .now() + 5) == .success else {
            NSLog("TextGrab: screen capture timed out")
            return nil
        }
        return image
    }

    static func recognize(_ image: CGImage, codeMode: Bool) -> String {
        // Results are read straight off the request after `perform`, which is
        // synchronous. The old completion-handler form worked only because of
        // that; if it ever stopped being synchronous it would silently return
        // nothing instead of failing.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate

        if codeMode {
            // Language correction is a spell-checker for prose, and code is not
            // prose: it turns `stderr` into "sterner", splits `NSPasteboard`, and
            // rewrites `--force` with an em dash. Off, with the language pinned so
            // Vision cannot decide the snippet is German and re-read it that way.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
        } else {
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("TextGrab: text recognition failed: \(error)")
            return ""
        }

        return layout(request.results ?? [], codeMode: codeMode)
    }

    /// Rebuilds the page from the recognised pieces.
    ///
    /// Vision hands back observations in its own order with no whitespace, which
    /// is fine for a sentence and wrong for anything laid out in two dimensions.
    /// Lines are grouped by vertical position and ordered top-to-bottom, then
    /// left-to-right, so a split view or a diff no longer interleaves. In code
    /// mode the leading indentation is reconstructed from each line's left edge,
    /// because indentation is not decoration in most languages.
    private static func layout(_ observations: [VNRecognizedTextObservation], codeMode: Bool) -> String {
        let pieces = observations.compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        guard !pieces.isEmpty else { return "" }

        // Vision's origin is bottom-left, so a larger midY is higher on screen.
        // Two pieces belong to the same line when they overlap vertically by more
        // than half the shorter one's height.
        var rows: [[(text: String, box: CGRect)]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if var last = rows.last,
               let reference = last.first,
               abs(reference.box.midY - piece.box.midY) < min(reference.box.height, piece.box.height) * 0.6 {
                last.append(piece)
                rows[rows.count - 1] = last
            } else {
                rows.append([piece])
            }
        }

        // One character's width, averaged over everything recognised — the basis
        // for turning a left edge into a number of spaces.
        let totalCharacters = pieces.reduce(0) { $0 + max($1.text.count, 1) }
        let averageCharacterWidth = pieces.reduce(0.0) { $0 + $1.box.width } / Double(totalCharacters)
        let leftmost = pieces.map(\.box.minX).min() ?? 0

        let lines = rows.map { row -> String in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            let body = ordered.map(\.text).joined(separator: " ")
            guard codeMode, averageCharacterWidth > 0, let first = ordered.first else { return body }
            let indent = Int(((first.box.minX - leftmost) / averageCharacterWidth).rounded())
            return String(repeating: " ", count: min(max(indent, 0), 60)) + body
        }

        let text = lines.joined(separator: "\n")
        return (codeMode ? asciify(text) : text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vision hands back typographic and mathematical glyphs, which are right for
    /// prose and broken for code: `--force` comes back as `—force`, `->` as `→>`
    /// and `>=` as `›=`, so the snippet no longer compiles when pasted.
    ///
    /// Longer sequences are replaced first, or `→>` would expand to `->>`.
    private static func asciify(_ text: String) -> String {
        var out = text
        for (glyph, ascii) in [
            ("\u{2192}>", "->"),                        // → followed by >
            ("<\u{2190}", "<-"),                        // < followed by ←
            ("\u{2192}", "->"), ("\u{2190}", "<-"),     // → ←
            ("\u{203A}", ">"), ("\u{2039}", "<"),       // › ‹
            ("\u{2265}", ">="), ("\u{2264}", "<="),     // ≥ ≤
            ("\u{2260}", "!="),                         // ≠
            ("\u{2018}", "'"), ("\u{2019}", "'"),       // ' '
            ("\u{201C}", "\""), ("\u{201D}", "\""),    // " "
            ("\u{2014}", "--"), ("\u{2013}", "-"),      // em dash, en dash
            ("\u{2026}", "..."),                        // ellipsis
            ("\u{00A0}", " "),                          // non-breaking space
        ] {
            out = out.replacingOccurrences(of: glyph, with: ascii)
        }
        return out
    }
}
