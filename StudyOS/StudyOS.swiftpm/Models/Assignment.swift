import Foundation

enum AssignmentType: String, Codable, CaseIterable, Identifiable {
    case homework, quiz, exam, lab, project, paper, reading, presentation, other
    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .homework: return "pencil.and.list.clipboard"
        case .quiz: return "checkmark.circle"
        case .exam: return "doc.text.magnifyingglass"
        case .lab: return "flask"
        case .project: return "hammer"
        case .paper: return "doc.richtext"
        case .reading: return "book"
        case .presentation: return "person.wave.2"
        case .other: return "square.dashed"
        }
    }
}

enum AssignmentStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, inProgress, completed
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case low = 0, normal = 1, high = 2, critical = 3
    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Assignment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var courseID: UUID?
    var title: String
    var type: AssignmentType = .homework
    var details: String = ""
    /// Due date. When `hasDueTime` is false only the day is meaningful.
    var dueDate: Date
    var hasDueTime: Bool = true
    var priority: Priority = .normal
    var status: AssignmentStatus = .notStarted
    /// Grade category this assignment counts toward, if any.
    var categoryID: UUID? = nil
    /// Expected points, known before grading. Pre-fills the grade entry.
    var pointsPossible: Double? = nil
    var grade: Grade? = nil
    var estimatedMinutes: Int? = nil
    var notes: String = ""
    var completedAt: Date? = nil
    var createdAt: Date = Date()

    init(id: UUID = UUID(), courseID: UUID?, title: String, type: AssignmentType = .homework, dueDate: Date,
         hasDueTime: Bool = true, priority: Priority = .normal, status: AssignmentStatus = .notStarted,
         categoryID: UUID? = nil, pointsPossible: Double? = nil, grade: Grade? = nil, estimatedMinutes: Int? = nil,
         details: String = "", notes: String = "") {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.type = type
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.status = status
        self.categoryID = categoryID
        self.pointsPossible = pointsPossible
        self.grade = grade
        self.estimatedMinutes = estimatedMinutes
        self.details = details
        self.notes = notes
        if status == .completed { completedAt = Date() }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        courseID = try c.decodeIfPresent(UUID.self, forKey: .courseID)
        title = try c.decode(String.self, forKey: .title, default: "Assignment")
        type = try c.decode(AssignmentType.self, forKey: .type, default: .homework)
        details = try c.decode(String.self, forKey: .details, default: "")
        dueDate = try c.decode(Date.self, forKey: .dueDate, default: Date())
        hasDueTime = try c.decode(Bool.self, forKey: .hasDueTime, default: true)
        priority = try c.decode(Priority.self, forKey: .priority, default: .normal)
        status = try c.decode(AssignmentStatus.self, forKey: .status, default: .notStarted)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        pointsPossible = try c.decodeIfPresent(Double.self, forKey: .pointsPossible)
        grade = try c.decodeIfPresent(Grade.self, forKey: .grade)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        notes = try c.decode(String.self, forKey: .notes, default: "")
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt, default: Date())
    }

    var isCompleted: Bool { status == .completed }

    /// The moment the assignment is considered late. Date-only items are due at the end of that day.
    func effectiveDueDate(calendar: Calendar = .current) -> Date {
        if hasDueTime { return dueDate }
        let start = calendar.startOfDay(for: dueDate)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? dueDate
    }

    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !isCompleted && effectiveDueDate(calendar: calendar) < now
    }
}
