import AppKit
import Foundation

/// Keeps exactly one TextGrab running, and lets a freshly built one take over.
///
/// Without this, a second copy starts happily but `RegisterEventHotKey` refuses
/// the shortcut that the first copy already owns — so the app sits there inert
/// and the only clue is the menu-bar tooltip. Rebuilding makes it worse: `open`
/// on a running app merely activates it, so you keep using the old binary while
/// believing you restarted. Launch with `open -n` (what `make restart` does) and
/// the newer build asks the older one to quit before claiming the lock.
///
/// The lock is an advisory `flock`, so a crashed instance releases it for free.
enum SingleInstance {
    /// Held for the process lifetime; closing it would release the lock. Touched
    /// only once, from `claim()` at launch, before any concurrency exists.
    nonisolated(unsafe) private static var lockDescriptor: Int32 = -1

    private struct Holder: Codable {
        let pid: pid_t
        /// The executable's modification time — what distinguishes one build from
        /// the next without a version number to bump by hand.
        let build: Date
        let path: String
    }

    /// Call once at launch. Returns false when this process should exit because
    /// another instance is already serving.
    static func claim() -> Bool {
        let url = lockURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else {
            NSLog("TextGrab: could not open the lock file; continuing without single-instance protection.")
            return true
        }

        if take(descriptor) { return true }

        guard let holder = readHolder(descriptor), holder.pid != getpid() else {
            NSLog("TextGrab: another instance holds the lock. Exiting.")
            close(descriptor)
            return false
        }

        guard buildDate() > holder.build else {
            NSLog("TextGrab: already running (pid \(holder.pid)). Exiting.")
            close(descriptor)
            return false
        }

        NSLog("TextGrab: a newer build is starting; asking pid \(holder.pid) to quit.")
        quit(pid: holder.pid)

        // Wait for the old process to let go of the lock (and the hot key).
        for _ in 0..<50 {
            if take(descriptor) {
                NSLog("TextGrab: took over from pid \(holder.pid).")
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        NSLog("TextGrab: pid \(holder.pid) did not exit; leaving it in charge.")
        close(descriptor)
        return false
    }

    // MARK: Private

    private static func take(_ descriptor: Int32) -> Bool {
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        lockDescriptor = descriptor
        write(descriptor)
        return true
    }

    private static func write(_ descriptor: Int32) {
        let holder = Holder(pid: getpid(), build: buildDate(), path: executablePath())
        guard let data = try? JSONEncoder().encode(holder) else { return }
        ftruncate(descriptor, 0)
        lseek(descriptor, 0, SEEK_SET)
        data.withUnsafeBytes { _ = Darwin.write(descriptor, $0.baseAddress, $0.count) }
    }

    private static func readHolder(_ descriptor: Int32) -> Holder? {
        lseek(descriptor, 0, SEEK_SET)
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &bytes, bytes.count)
        guard count > 0 else { return nil }
        return try? JSONDecoder().decode(Holder.self, from: Data(bytes[0..<count]))
    }

    /// Ask politely first, so the old instance can unregister its hot key, then insist.
    private static func quit(pid: pid_t) {
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.terminate()
        } else {
            kill(pid, SIGTERM)
        }
        for _ in 0..<30 {
            if kill(pid, 0) != 0 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        kill(pid, SIGTERM)
    }

    private static func executablePath() -> String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    private static func buildDate() -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath())
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private static func lockURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("TextGrab", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }
}
