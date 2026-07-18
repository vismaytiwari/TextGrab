import AppKit
import Vision

enum GrabResult {
    case copied(String, NSImage)  // recognized text + the captured region
    case empty                    // a region was captured but no text was found
    case cancelled                // user pressed Esc / made no selection
}

enum TextGrabber {
    // Shows the native screenshot-style crosshair, OCRs the selected pixels,
    // and leaves the recognized text on the clipboard.
    static func captureAndCopy() -> GrabResult {
        let pb = NSPasteboard.general
        let changeCountBefore = pb.changeCount

        // -i interactive selection, -x no shutter sound, -c copy to clipboard.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-x", "-c"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .cancelled
        }

        // If the clipboard didn't change, the user cancelled the selection.
        guard pb.changeCount != changeCountBefore,
              let image = NSImage(pasteboard: pb),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return .cancelled
        }

        let text = recognize(cgImage)
        guard !text.isEmpty else { return .empty }

        pb.clearContents()
        pb.setString(text, forType: .string)
        return .copied(text, image)
    }

    private static func recognize(_ image: CGImage) -> String {
        var lines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            lines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
