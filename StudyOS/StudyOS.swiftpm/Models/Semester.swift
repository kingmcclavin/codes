import Foundation

struct Semester: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var startDate: Date
    var endDate: Date
    /// Archived semesters are hidden from day-to-day views but keep all history.
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, startDate: Date, endDate: Date, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name, default: "Semester")
        startDate = try c.decode(Date.self, forKey: .startDate, default: Date())
        endDate = try c.decode(Date.self, forKey: .endDate, default: Date())
        isArchived = try c.decode(Bool.self, forKey: .isArchived, default: false)
        createdAt = try c.decode(Date.self, forKey: .createdAt, default: Date())
    }

    func contains(_ date: Date) -> Bool {
        date >= startDate && date <= endDate
    }
}
