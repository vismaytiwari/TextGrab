import AppKit
import ImageIO
import Vision

enum GrabResult {
    case copied(String)  // recognized text; the pixels are discarded immediately
    case empty           // a region was captured but no text was found
    case cancelled       // user pressed Esc / made no selection
}

enum TextGrabber {
    // Shows the native screenshot-style crosshair, OCRs the selected pixels,
    // and leaves the recognized text on the clipboard.
    static func captureAndCopy(codeMode: Bool = true) -> GrabResult {
        // The capture goes to a private temporary file, never to the clipboard.
        //
        // `screencapture -c` would put the screenshot itself on the pasteboard
        // before we replace it with the text, and that is enough for every
        // clipboard manager — or anything syncing the clipboard to another
        // device — to record a screenshot you never meant to take. Going via a
        // file means the clipboard only ever sees the recognized text.
        guard let scratch = makeScratchDirectory() else { return .cancelled }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("grab.png")

        // -i interactive selection, -x no shutter sound.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-x", file.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .cancelled
        }

        // Cancelling the selection (Esc, or no drag) writes no file.
        // Straight to a CGImage via ImageIO: no AppKit round-trip, and the raw
        // native-resolution pixels are what Vision wants — an NSImage is measured
        // in points and may hand back a scaled render, losing the fine detail
        // that decides whether an `l` reads as a `1`.
        guard task.terminationStatus == 0,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .cancelled
        }

        let text = recognize(cgImage, codeMode: codeMode)
        guard !text.isEmpty else { return .empty }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return .copied(text)
    }

    /// A 0700 directory of our own, so the screenshot is never briefly readable
    /// by other users the way a file dropped straight into /tmp would be.
    private static func makeScratchDirectory() -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("textgrab-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return url
        } catch {
            NSLog("TextGrab: could not create a scratch directory: \(error)")
            return nil
        }
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
