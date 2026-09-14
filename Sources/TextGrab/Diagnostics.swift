import Foundation

/// A log file of what the app did, never of what it saw.
///
/// `NSLog` from a menu-bar app is effectively unreadable after the fact — the
/// unified log drops it or buries it, and there is no console to watch. A hot
/// key that quietly does nothing cannot be diagnosed without a record, so one
/// line per event goes to a file instead.
///
/// Recognised text, captured pixels and clipboard contents are never written
/// here. Sizes and outcomes only.
enum Diagnostics {
    private static let queue = DispatchQueue(label: "textgrab.diagnostics")
    private static let file: URL? = {
        guard let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Logs/TextGrab", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("textgrab.log")
    }()

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// A plain string rather than an autoclosure on purpose: an autoclosure
    /// captures whatever it mentions, which turns every call site inside a
    /// closure into an explicit-self argument for the sake of a log line.
    /// These are rare enough that building the string eagerly costs nothing.
    static func log(_ message: String) {
        let now = Date()
        queue.async {
            guard let file = file else { return }
            let line = stamp.string(from: now) + " " + message + "\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file)
            }
        }
    }
}
