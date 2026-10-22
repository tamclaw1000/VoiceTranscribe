import Foundation

/// Structured event tracer. Each launch gets its own file,
/// /tmp/VoiceTranscribe--YYYYMMDD--HHMM.log, so a crash-triggered relaunch
/// never destroys the telemetry for the session that just crashed.
///
/// Usage:
///   Trace.event("listen.toggle", ["source": source.name, "action": "start"])
///
/// Output format (one JSON line per event):
///   {"ts": "2026-05-30T23:41:05.123Z", "event": "listen.toggle", "source": "Built-in Microphone", "action": "start"}
enum Trace {
    private static let queue = DispatchQueue(label: "VoiceTranscribe.Trace", qos: .utility)
    private static let directory = "/tmp"
    private static let retention: TimeInterval = 7 * 24 * 60 * 60

    private static let path: String = {
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        let datePart = formatter.string(from: now)
        formatter.dateFormat = "HHmm"
        let timePart = formatter.string(from: now)
        return "\(directory)/VoiceTranscribe--\(datePart)--\(timePart).log"
    }()

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

        rotateOldLogs()

        let url = URL(fileURLWithPath: path)
        do {
            try Data().write(to: url) // create this launch's own file
            let h = try FileHandle(forWritingTo: url)
            h.seekToEndOfFile()
            handle = h
            return h
        } catch {
            fputs("[Trace] Could not open \(path): \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// Removes prior launches' logs older than `retention`, so each crash/relaunch keeps its
    /// own lead-up telemetry without letting these files accumulate in `/tmp` forever.
    private static func rotateOldLogs() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }

        let cutoff = Date().addingTimeInterval(-retention)
        for name in entries where name.hasPrefix("VoiceTranscribe--") && name.hasSuffix(".log") {
            let entryPath = "\(directory)/\(name)"
            guard let attributes = try? fileManager.attributesOfItem(atPath: entryPath),
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(atPath: entryPath)
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
