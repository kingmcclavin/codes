import Foundation

struct Course: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var semesterID: UUID?
    var name: String
    var code: String = ""
    var professor: String = ""
    var credits: Double = 3
    var room: String = ""
    var meetings: [MeetingTime] = []

    /// Weighted grading categories. Empty means grades are combined by total points.
    var categories: [GradeCategory] = []
    /// Target grade, as a percentage.
    var targetGrade: Double? = nil
    /// A grade typed in by hand (for example, copied from a school portal).
    /// When set it is shown instead of the calculated grade and is labelled "Manual".
    var manualGrade: Double? = nil
    /// The official final letter grade once the course is over. Used for actual GPA.
    var finalLetterGrade: String? = nil
    var countsTowardGPA: Bool = true

    var color: CourseColor = .blue
    var icon: String = CourseIcon.defaultSymbol
    var notes: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), semesterID: UUID?, name: String, code: String = "", professor: String = "",
         credits: Double = 3, room: String = "", meetings: [MeetingTime] = [], categories: [GradeCategory] = [],
         targetGrade: Double? = nil, color: CourseColor = .blue, icon: String = CourseIcon.defaultSymbol, notes: String = "") {
        self.id = id
        self.semesterID = semesterID
        self.name = name
        self.code = code
        self.professor = professor
        self.credits = credits
        self.room = room
        self.meetings = meetings
        self.categories = categories
        self.targetGrade = targetGrade
        self.color = color
        self.icon = icon
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        semesterID = try c.decodeIfPresent(UUID.self, forKey: .semesterID)
        name = try c.decode(String.self, forKey: .name, default: "Course")
        code = try c.decode(String.self, forKey: .code, default: "")
        professor = try c.decode(String.self, forKey: .professor, default: "")
        credits = try c.decode(Double.self, forKey: .credits, default: 3)
        room = try c.decode(String.self, forKey: .room, default: "")
        meetings = try c.decode([MeetingTime].self, forKey: .meetings, default: [])
        categories = try c.decode([GradeCategory].self, forKey: .categories, default: [])
        targetGrade = try c.decodeIfPresent(Double.self, forKey: .targetGrade)
        manualGrade = try c.decodeIfPresent(Double.self, forKey: .manualGrade)
        finalLetterGrade = try c.decodeIfPresent(String.self, forKey: .finalLetterGrade)
        countsTowardGPA = try c.decode(Bool.self, forKey: .countsTowardGPA, default: true)
        color = try c.decode(CourseColor.self, forKey: .color, default: .blue)
        icon = try c.decode(String.self, forKey: .icon, default: CourseIcon.defaultSymbol)
        notes = try c.decode(String.self, forKey: .notes, default: "")
        createdAt = try c.decode(Date.self, forKey: .createdAt, default: Date())
    }

    /// "PHYS 222" if a code exists, otherwise the course name.
    var shortName: String { code.isEmpty ? name : code }

    func category(withID id: UUID?) -> GradeCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }
}

/// A recurring weekly class meeting.
struct MeetingTime: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    /// Calendar weekday: 1 = Sunday … 7 = Saturday.
    var weekday: Int
    /// Minutes after midnight.
    var startMinute: Int
    var endMinute: Int
    /// Overrides the course room for this meeting when not empty (e.g. a lab room).
    var location: String = ""
    var kind: String = "Lecture"

    init(id: UUID = UUID(), weekday: Int, startMinute: Int, endMinute: Int, location: String = "", kind: String = "Lecture") {
        self.id = id
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.location = location
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        weekday = try c.decode(Int.self, forKey: .weekday, default: 2)
        startMinute = try c.decode(Int.self, forKey: .startMinute, default: 9 * 60)
        endMinute = try c.decode(Int.self, forKey: .endMinute, default: 10 * 60)
        location = try c.decode(String.self, forKey: .location, default: "")
        kind = try c.decode(String.self, forKey: .kind, default: "Lecture")
    }

    var durationMinutes: Int { max(0, endMinute - startMinute) }
}

/// A weighted grading category, e.g. "Homework — 15%".
struct GradeCategory: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Percentage weight of the course grade (15 means 15%).
    var weight: Double

    init(id: UUID = UUID(), name: String, weight: Double) {
        self.id = id
        self.name = name
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name, default: "Category")
        weight = try c.decode(Double.self, forKey: .weight, default: 0)
    }
}

/// A restrained palette so courses are distinguishable without looking like a toy.
enum CourseColor: String, Codable, CaseIterable, Identifiable {
    case blue, indigo, purple, teal, green, olive, orange, red, pink, graphite
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum CourseIcon {
    static let defaultSymbol = "book.closed"
    static let all = [
        "book.closed", "atom", "function", "sum", "x.squareroot", "flask", "leaf",
        "globe.americas", "building.columns", "gearshape.2", "cpu", "bolt",
        "waveform.path.ecg", "chart.line.uptrend.xyaxis", "paintpalette", "music.note",
        "theatermasks", "text.book.closed", "character.book.closed", "brain.head.profile",
        "hammer", "ruler", "scalemass", "stethoscope",
    ]
}
