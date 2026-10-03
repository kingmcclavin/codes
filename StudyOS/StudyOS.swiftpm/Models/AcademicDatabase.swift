import Foundation

/// Everything StudyOS stores, as one portable, human-readable JSON document.
struct AcademicDatabase: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = AcademicDatabase.currentSchemaVersion
    var student = Student()
    var semesters: [Semester] = []
    var courses: [Course] = []
    var assignments: [Assignment] = []
    var exams: [Exam] = []
    var studySessions: [StudySession] = []
    var activeTimer: ActiveStudyTimer? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion, default: 1)
        student = try c.decode(Student.self, forKey: .student, default: Student())
        semesters = try c.decode([Semester].self, forKey: .semesters, default: [])
        courses = try c.decode([Course].self, forKey: .courses, default: [])
        assignments = try c.decode([Assignment].self, forKey: .assignments, default: [])
        exams = try c.decode([Exam].self, forKey: .exams, default: [])
        studySessions = try c.decode([StudySession].self, forKey: .studySessions, default: [])
        activeTimer = try c.decodeIfPresent(ActiveStudyTimer.self, forKey: .activeTimer)
    }
}
