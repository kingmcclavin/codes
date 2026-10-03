import Foundation

/// A finished block of study time.
struct StudySession: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var courseID: UUID?
    var topic: String = ""
    var startedAt: Date
    var endedAt: Date
    /// Time actually studied, excluding pauses.
    var durationSeconds: TimeInterval
    var notes: String = ""

    init(id: UUID = UUID(), courseID: UUID?, topic: String, startedAt: Date, endedAt: Date,
         durationSeconds: TimeInterval, notes: String = "") {
        self.id = id
        self.courseID = courseID
        self.topic = topic
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        courseID = try c.decodeIfPresent(UUID.self, forKey: .courseID)
        topic = try c.decode(String.self, forKey: .topic, default: "")
        startedAt = try c.decode(Date.self, forKey: .startedAt, default: Date())
        endedAt = try c.decode(Date.self, forKey: .endedAt, default: startedAt)
        durationSeconds = try c.decode(TimeInterval.self, forKey: .durationSeconds, default: 0)
        notes = try c.decode(String.self, forKey: .notes, default: "")
    }
}

/// The timer currently running (or paused). Stored with the rest of the data,
/// so quitting or force-closing the app never loses a session in progress.
/// Elapsed time is derived from timestamps rather than counted tick by tick.
struct ActiveStudyTimer: Codable, Equatable {
    var courseID: UUID?
    var topic: String
    var startedAt: Date
    /// Seconds accumulated before the current running stretch.
    var accumulatedSeconds: TimeInterval = 0
    /// When the current running stretch began. Nil while paused.
    var runningSince: Date?

    init(courseID: UUID?, topic: String, startedAt: Date) {
        self.courseID = courseID
        self.topic = topic
        self.startedAt = startedAt
        self.runningSince = startedAt
    }

    var isPaused: Bool { runningSince == nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        accumulatedSeconds += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    mutating func resume(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }
}
