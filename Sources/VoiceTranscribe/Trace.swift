import Foundation

/// Structured event tracer for /tmp/VoiceTranscribe.log.
///
/// Usage:
///   Trace.event("listen.toggle", ["source": source.name, "action": "start"])
///
/// Output format (one JSON line per event):
///   {"ts": "2026-05-30T23:41:05.123Z", "event": "listen.toggle", "source": "Built-in Microphone", "action": "start"}
enum Trace {
    private static let queue = DispatchQueue(label: "VoiceTranscribe.Trace", qos: .utility)
    private static let path = "/tmp/VoiceTranscribe.log"
    private static var handle: FileHandle?
    private static let startedAt = ISO8601DateFormatter().string(from: Date())
    private static let lock = NSLock()

    private static func ensureHandle() -> FileHandle? {
        lock.lock()
        defer { lock.unlock() }
        if let handle { return handle }

        // Truncate on first open per process lifetime, then append.
        let url = URL(fileURLWithPath: path)
        do {
            try Data().write(to: url) // truncate
            let h = try FileHandle(forWritingTo: url)
            h.seekToEndOfFile()
            handle = h
            return h
        } catch {
            fputs("[Trace] Could not open \(path): \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// Writes a structured event line. All values are converted to strings; the
    /// caller decides the event name and key-value pairs to record.
    static func event(_ name: String, _ pairs: [String: CustomStringConvertible?] = [:]) {
        let formatter = ISO8601DateFormatter()
        var dict: [String: String] = [
            "ts": formatter.string(from: Date()),
            "event": name
        ]
        for (k, v) in pairs {
            dict[k] = v.map { String(describing: $0) } ?? "nil"
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")

        queue.async {
            guard let h = ensureHandle() else { return }
            do {
                try h.write(contentsOf: line.data(using: .utf8)!)
            } catch {
                fputs("[Trace] write failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Convenience: log a state transition.
    static func state(_ component: String, from old: Any, to new: Any) {
        event("\(component).state", ["from": "\(old)", "to": "\(new)"])
    }

    /// Convenience: log a button action.
    static func button(_ name: String, source: String) {
        event("button.\(name)", ["source": source])
    }

    /// Convenience: log an audio event.
    static func audio(_ event: String, _ pairs: [String: CustomStringConvertible?] = [:]) {
        var p = pairs
        p["audioEvent"] = event
        Trace.event("audio.\(event)", p)
    }

    /// Convenience: log a file I/O event.
    static func file(_ event: String, path: String, extra: [String: CustomStringConvertible?] = [:]) {
        var p = extra
        p["filePath"] = path
        Trace.event("file.\(event)", p)
    }

    /// Flush and close (call on app termination if desired).
    static func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }
}
