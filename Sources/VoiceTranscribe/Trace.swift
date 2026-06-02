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

    /// Write synchronously to guarantee the event is on disk before the caller
    /// continues. This keeps the trace reliable during debugging; if it becomes
    /// a bottleneck under heavy audio load, switch back to async + periodic flush.
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

        // Also echo to stderr so it's visible in Console.app / terminal launch.
        fputs("[VT] \(line)\n", stderr)

        line.append("\n")

        queue.sync {
            guard let h = ensureHandle() else { return }
            do {
                try h.write(contentsOf: line.data(using: .utf8)!)
                try h.synchronize()
            } catch {
                fputs("[Trace] write failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private static func ensureHandle() -> FileHandle? {
        if let handle { return handle }

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

    /// Convenience: log a button action.
    static func button(_ name: String, source: String, extra: [String: CustomStringConvertible?] = [:]) {
        var p: [String: CustomStringConvertible?] = ["source": source]
        for (k, v) in extra { p[k] = v }
        event("button.\(name)", p)
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
}
