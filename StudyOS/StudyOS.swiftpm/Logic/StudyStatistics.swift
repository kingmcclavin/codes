import Foundation

struct StudyTimeByCourse: Identifiable, Equatable {
    var id: String { courseID?.uuidString ?? "none" }
    var courseID: UUID?
    var seconds: TimeInterval
}

enum StudyStatistics {
    /// The calendar week containing `date` (respects the user's first weekday).
    static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86_400)
    }

    static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// Sessions are attributed to the interval in which they started.
    static func sessions(_ sessions: [StudySession], in interval: DateInterval) -> [StudySession] {
        sessions.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
    }

    static func totalSeconds(_ sessions: [StudySession], in interval: DateInterval) -> TimeInterval {
        self.sessions(sessions, in: interval).reduce(0) { $0 + $1.durationSeconds }
    }

    static func byCourse(_ sessions: [StudySession], in interval: DateInterval) -> [StudyTimeByCourse] {
        var totals: [UUID?: TimeInterval] = [:]
        for session in self.sessions(sessions, in: interval) {
            totals[session.courseID, default: 0] += session.durationSeconds
        }
        return totals.map { StudyTimeByCourse(courseID: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }
}

enum DurationFormat {
    /// "4h 32m", "47m", "0m".
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "1:02:07" or "02:07" — for a running timer.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

enum PercentFormat {
    /// "91.4%"
    static func string(_ percent: Double?, digits: Int = 1) -> String {
        guard let percent else { return "—" }
        return String(format: "%.\(digits)f%%", percent)
    }

    static func gpa(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    /// "12.5" or "12" for points.
    static func points(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
