import Foundation

struct SessionPerson: Identifiable, Equatable {
    let id: UUID
    var number: Int
    var name: String

    var label: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Person \(number)" : trimmed
    }
}

enum RangeIdentitySource: Equatable {
    case automatic
    case manual
    case unidentified
}

struct SessionIdentityRange: Identifiable, Equatable {
    let id: UUID
    var speakerID: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var voiceID: String?
    var confidence: Float?
    var identityAttempts: Int = 0
    var automaticPersonID: UUID?
    var personID: UUID?
    var source: RangeIdentitySource

    var duration: TimeInterval { max(0, endTime - startTime) }
}

/// Session-local people are separate from Sortformer slots and WeSpeaker clusters.
struct SessionIdentityDirectory {
    private struct Snapshot {
        var people: [SessionPerson]
        var ranges: [SessionIdentityRange]
        var voicePeople: [String: UUID]
        var aliases: [UUID: UUID]
        var nextPersonNumber: Int
    }

    private(set) var people: [SessionPerson] = []
    private(set) var ranges: [SessionIdentityRange] = []
    private(set) var unresolvedRanges: [SessionIdentityRange] = []
    private var voicePeople: [String: UUID] = [:]
    private var aliases: [UUID: UUID] = [:]
    private var nextPersonNumber = 1
    private var history: [Snapshot] = []

    mutating func reset() {
        self = Self()
    }

    mutating func reconcile(_ segments: [SpeakerDiarizationSegment]) {
        let previous = ranges
        var used = Set<UUID>()
        ranges = segments.sorted { $0.startTime < $1.startTime }.map { segment in
            let candidate = previous
                .filter { $0.speakerID == segment.speakerID && !used.contains($0.id) }
                .map { old -> (SessionIdentityRange, TimeInterval) in
                    let overlap = max(0, min(old.endTime, segment.endTime) - max(old.startTime, segment.startTime))
                    let newDuration = segment.endTime - segment.startTime
                    let shorter = min(old.duration, newDuration)
                    let stableStart = abs(old.startTime - segment.startTime) <= 0.25
                    let notSplit = newDuration >= old.duration * 0.75
                    return (old, stableStart && notSplit && shorter > 0 ? overlap / shorter : 0)
                }
                .max { $0.1 < $1.1 }
            if let (old, overlap) = candidate, overlap >= 0.8 {
                used.insert(old.id)
                var updated = old
                updated.startTime = segment.startTime
                updated.endTime = segment.endTime
                return updated
            }
            return SessionIdentityRange(
                id: UUID(), speakerID: segment.speakerID,
                startTime: segment.startTime, endTime: segment.endTime,
                voiceID: nil, confidence: nil, automaticPersonID: nil,
                personID: nil, source: .automatic
            )
        }
        let orphaned = previous.filter { !used.contains($0.id) && $0.source != .automatic }
        for range in orphaned where !unresolvedRanges.contains(where: { $0.id == range.id }) {
            unresolvedRanges.append(range)
        }
    }

    func range(at offset: TimeInterval) -> SessionIdentityRange? {
        ranges.first { $0.startTime <= offset && offset < $0.endTime }
    }

    func range(id: UUID) -> SessionIdentityRange? {
        ranges.first { $0.id == id }
    }

    func person(id: UUID?) -> SessionPerson? {
        people.first { $0.id == canonicalPersonID(id) }
    }

    func canonicalPersonID(_ id: UUID?) -> UUID? {
        guard var id else { return nil }
        var visited = Set<UUID>()
        while let next = aliases[id], visited.insert(id).inserted { id = next }
        return id
    }

    func personLabel(for range: SessionIdentityRange) -> String {
        person(id: range.personID)?.label ?? "Unidentified audio"
    }

    func resolved(_ segment: TranscriptSegment) -> TranscriptSegment {
        if segment.isPersonOverride {
            if segment.manualPersonID == nil && segment.speakerName != "Unidentified audio" {
                return segment
            }
            var copy = segment
            copy.personID = canonicalPersonID(segment.manualPersonID)
            copy.speakerName = person(id: copy.personID)?.label ?? "Unidentified audio"
            return copy
        }
        let range = segment.diarizationRangeID.flatMap { self.range(id: $0) }
            ?? segment.audioOffset.flatMap { self.range(at: $0) }
        guard let range else { return segment }
        var copy = segment
        copy.diarizationRangeID = range.id
        copy.speakerID = range.speakerID
        copy.speakerName = personLabel(for: range)
        copy.personID = range.personID
        copy.voiceID = range.voiceID
        copy.voiceName = range.voiceID
        copy.voiceConfidence = range.confidence
        return copy
    }

    mutating func assignAutomatic(voiceID: String, confidence: Float?, to rangeID: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == rangeID }) else { return }
        let personID: UUID
        if let known = voicePeople[voiceID] {
            personID = known
        } else {
            personID = makePerson().id
            voicePeople[voiceID] = personID
        }
        ranges[index].voiceID = voiceID
        ranges[index].confidence = confidence
        ranges[index].automaticPersonID = personID
        if ranges[index].source == .automatic {
            ranges[index].personID = personID
        }
    }

    mutating func markUnresolved(_ rangeID: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == rangeID }) else { return }
        ranges[index].identityAttempts += 1
    }

    @discardableResult
    mutating func createPerson() -> SessionPerson {
        saveUndo()
        return makePerson()
    }

    mutating func rename(personID: UUID, to name: String) {
        guard let index = people.firstIndex(where: { $0.id == personID }) else { return }
        saveUndo()
        people[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func assign(_ rangeIDs: Set<UUID>, to personID: UUID?) {
        guard personID == nil || person(id: personID) != nil else { return }
        guard ranges.contains(where: { rangeIDs.contains($0.id) }) else { return }
        saveUndo()
        for index in ranges.indices where rangeIDs.contains(ranges[index].id) {
            ranges[index].personID = personID
            ranges[index].source = personID == nil ? .unidentified : .manual
        }
    }

    mutating func restoreAutomatic(_ rangeIDs: Set<UUID>) {
        guard ranges.contains(where: { rangeIDs.contains($0.id) }) else { return }
        saveUndo()
        for index in ranges.indices where rangeIDs.contains(ranges[index].id) {
            ranges[index].personID = ranges[index].automaticPersonID
            ranges[index].source = .automatic
        }
    }

    mutating func merge(_ sourceID: UUID, into targetID: UUID) {
        guard sourceID != targetID, person(id: sourceID) != nil, person(id: targetID) != nil else { return }
        saveUndo()
        people.removeAll { $0.id == sourceID }
        aliases[sourceID] = targetID
        for (oldID, destination) in aliases where destination == sourceID {
            aliases[oldID] = targetID
        }
        for index in ranges.indices {
            if ranges[index].personID == sourceID { ranges[index].personID = targetID }
            if ranges[index].automaticPersonID == sourceID { ranges[index].automaticPersonID = targetID }
        }
        for (voiceID, personID) in voicePeople where personID == sourceID {
            voicePeople[voiceID] = targetID
        }
    }

    mutating func discardUnresolved(_ rangeID: UUID) {
        unresolvedRanges.removeAll { $0.id == rangeID }
    }

    mutating func undo() -> Bool {
        guard let snapshot = history.popLast() else { return false }
        let currentRanges = ranges
        let currentPeople = people
        let currentVoicePeople = voicePeople
        people = snapshot.people
        ranges = snapshot.ranges
        voicePeople = snapshot.voicePeople
        aliases = snapshot.aliases
        nextPersonNumber = snapshot.nextPersonNumber
        for (voiceID, personID) in currentVoicePeople where voicePeople[voiceID] == nil {
            voicePeople[voiceID] = personID
            if !people.contains(where: { $0.id == personID }),
               let person = currentPeople.first(where: { $0.id == personID }) {
                people.append(person)
                nextPersonNumber = max(nextPersonNumber, person.number + 1)
            }
        }
        for index in ranges.indices {
            guard let current = currentRanges.first(where: { $0.id == ranges[index].id }) else { continue }
            ranges[index].identityAttempts = max(ranges[index].identityAttempts, current.identityAttempts)
            guard current.voiceID != ranges[index].voiceID
                    || current.confidence != ranges[index].confidence else { continue }
            ranges[index].voiceID = current.voiceID
            ranges[index].confidence = current.confidence
            ranges[index].automaticPersonID = current.voiceID.flatMap { voicePeople[$0] }
            if ranges[index].source == .automatic {
                ranges[index].personID = ranges[index].automaticPersonID
            }
        }
        return true
    }

    var canUndo: Bool { !history.isEmpty }

    private mutating func makePerson() -> SessionPerson {
        let person = SessionPerson(id: UUID(), number: nextPersonNumber, name: "")
        nextPersonNumber += 1
        people.append(person)
        return person
    }

    private mutating func saveUndo() {
        history.append(Snapshot(
            people: people, ranges: ranges, voicePeople: voicePeople,
            aliases: aliases,
            nextPersonNumber: nextPersonNumber
        ))
        if history.count > 30 { history.removeFirst() }
    }
}
