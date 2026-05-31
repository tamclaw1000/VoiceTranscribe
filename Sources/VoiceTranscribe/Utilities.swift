import Foundation

enum FileNamer {
    static func sourceSlug(_ sourceName: String) -> String {
        let lowercased = sourceName.lowercased()
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var previousWasDash = false

        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "audio-source" : trimmed
    }

    static func startTimestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02d%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func endTimestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        let tenths = (components.nanosecond ?? 0) / 100_000_000
        return String(
            format: "%02d%02d%02d%d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            tenths
        )
    }

    static func recordingBasename(
        sourceName: String,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> String {
        "\(startTimestamp(startDate, calendar: calendar))-\(endTimestamp(endDate, calendar: calendar))-\(sourceSlug(sourceName))"
    }

    static func inProgressBasename(
        sourceName: String,
        startDate: Date,
        calendar: Calendar = .current
    ) -> String {
        "\(startTimestamp(startDate, calendar: calendar))-recording-\(sourceSlug(sourceName))"
    }
}

struct BoundedBuffer<Element> {
    private(set) var elements: [Element] = []
    let capacity: Int
    private(set) var droppedCount = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > capacity {
            elements.removeFirst(elements.count - capacity)
            droppedCount += 1
        }
    }
}

struct TranscriptDocument {
    private(set) var finalized: [TranscriptSegment] = []
    private(set) var interim: TranscriptSegment?

    mutating func apply(_ segment: TranscriptSegment) {
        if segment.isFinal {
            finalized.append(segment)
            interim = nil
        } else {
            interim = segment
        }
    }

    var plainText: String {
        let finalText = finalized.map(\.text).joined(separator: "\n")
        guard let interim else {
            return finalText
        }
        return finalText.isEmpty ? interim.text : "\(finalText)\n\(interim.text)"
    }
}
