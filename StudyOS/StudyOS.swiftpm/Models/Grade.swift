import Foundation

/// A recorded score. Embedded in assignments and exams so the score always
/// travels with the work it belongs to.
struct Grade: Codable, Equatable, Hashable {
    var pointsEarned: Double
    var pointsPossible: Double
    var recordedAt: Date = Date()

    init(pointsEarned: Double, pointsPossible: Double, recordedAt: Date = Date()) {
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pointsEarned = try c.decode(Double.self, forKey: .pointsEarned, default: 0)
        pointsPossible = try c.decode(Double.self, forKey: .pointsPossible, default: 0)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt, default: Date())
    }

    /// Percentage (0–100+). Nil when nothing was possible.
    var percent: Double? {
        pointsPossible > 0 ? pointsEarned / pointsPossible * 100 : nil
    }
}

/// Anything that can carry a grade toward a course's categories.
struct GradedItem: Equatable {
    var id: UUID
    var title: String
    var courseID: UUID?
    var categoryID: UUID?
    var grade: Grade
    var date: Date
}
