import Foundation

struct Exam: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var courseID: UUID?
    var title: String
    var date: Date
    var durationMinutes: Int? = nil
    var location: String = ""
    var topics: [String] = []
    var notes: String = ""
    /// The student's own estimate of how prepared they feel (0…1).
    /// Self-reported only — StudyOS never presents this as a measure of knowledge.
    var preparation: Double = 0
    /// Planned study time for this exam, in minutes.
    var studyGoalMinutes: Int? = nil
    var categoryID: UUID? = nil
    var grade: Grade? = nil
    var createdAt: Date = Date()

    init(id: UUID = UUID(), courseID: UUID?, title: String, date: Date, durationMinutes: Int? = nil,
         location: String = "", topics: [String] = [], notes: String = "", preparation: Double = 0,
         studyGoalMinutes: Int? = nil, categoryID: UUID? = nil, grade: Grade? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.date = date
        self.durationMinutes = durationMinutes
        self.location = location
        self.topics = topics
        self.notes = notes
        self.preparation = preparation
        self.studyGoalMinutes = studyGoalMinutes
        self.categoryID = categoryID
        self.grade = grade
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        courseID = try c.decodeIfPresent(UUID.self, forKey: .courseID)
        title = try c.decode(String.self, forKey: .title, default: "Exam")
        date = try c.decode(Date.self, forKey: .date, default: Date())
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        location = try c.decode(String.self, forKey: .location, default: "")
        topics = try c.decode([String].self, forKey: .topics, default: [])
        notes = try c.decode(String.self, forKey: .notes, default: "")
        preparation = try c.decode(Double.self, forKey: .preparation, default: 0)
        studyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .studyGoalMinutes)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        grade = try c.decodeIfPresent(Grade.self, forKey: .grade)
        createdAt = try c.decode(Date.self, forKey: .createdAt, default: Date())
    }
}
