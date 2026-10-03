import Foundation

/// The result of calculating a course grade from recorded scores.
/// Everything here is ACTUAL — it only reflects grades that were entered.
struct CourseGradeResult: Equatable {
    enum Method: Equatable {
        /// No graded work yet.
        case none
        /// Grades combined by total points (course has no categories).
        case totalPoints
        /// Category averages combined by category weight.
        case weighted
    }

    struct CategoryResult: Equatable, Identifiable {
        var id: UUID { category.id }
        var category: GradeCategory
        var pointsEarned: Double
        var pointsPossible: Double
        var gradedCount: Int
        /// Nil when nothing in this category has been graded.
        var percent: Double? {
            pointsPossible > 0 ? pointsEarned / pointsPossible * 100 : nil
        }
    }

    var method: Method
    /// Current course grade as a percentage. Nil when nothing has been graded.
    var percent: Double?
    var categories: [CategoryResult]
    var pointsEarned: Double
    var pointsPossible: Double
    var gradedCount: Int
    /// Graded items in a course with categories that weren't assigned a category.
    /// They are not part of the weighted grade; the UI points this out.
    var uncategorizedCount: Int
    /// Sum of the weights of categories that have at least one grade.
    /// With weights adding to 100, this is how much of the course is "decided" so far.
    var gradedWeight: Double
    /// Sum of all category weights (ideally 100).
    var totalWeight: Double
}

enum GradeCalculator {
    /// Calculates a course grade.
    ///
    /// - Without categories: total points earned ÷ total points possible.
    /// - With categories: each category's average is points earned ÷ points
    ///   possible within it; category averages are combined by weight, using
    ///   only categories that have grades so far (weights are re-normalised).
    ///   That matches how most course portals report a running grade.
    static func calculate(course: Course, items: [GradedItem]) -> CourseGradeResult {
        let usable = items.filter { $0.grade.pointsPossible > 0 || $0.grade.pointsEarned > 0 }
        let earned = usable.reduce(0) { $0 + $1.grade.pointsEarned }
        let possible = usable.reduce(0) { $0 + $1.grade.pointsPossible }
        let totalWeight = course.categories.reduce(0) { $0 + max(0, $1.weight) }

        if course.categories.isEmpty || totalWeight <= 0 {
            return CourseGradeResult(
                method: possible > 0 ? .totalPoints : .none,
                percent: possible > 0 ? earned / possible * 100 : nil,
                categories: [],
                pointsEarned: earned,
                pointsPossible: possible,
                gradedCount: usable.count,
                uncategorizedCount: 0,
                gradedWeight: 0,
                totalWeight: totalWeight
            )
        }

        let knownIDs = Set(course.categories.map(\.id))
        let categoryResults = course.categories.map { category -> CourseGradeResult.CategoryResult in
            let inCategory = usable.filter { $0.categoryID == category.id }
            return CourseGradeResult.CategoryResult(
                category: category,
                pointsEarned: inCategory.reduce(0) { $0 + $1.grade.pointsEarned },
                pointsPossible: inCategory.reduce(0) { $0 + $1.grade.pointsPossible },
                gradedCount: inCategory.count
            )
        }
        let uncategorized = usable.filter { $0.categoryID == nil || !knownIDs.contains($0.categoryID!) }

        var weightedSum = 0.0
        var gradedWeight = 0.0
        for result in categoryResults {
            guard let percent = result.percent, result.category.weight > 0 else { continue }
            weightedSum += percent * result.category.weight
            gradedWeight += result.category.weight
        }
        let percent = gradedWeight > 0 ? weightedSum / gradedWeight : nil

        return CourseGradeResult(
            method: percent == nil ? .none : .weighted,
            percent: percent,
            categories: categoryResults,
            pointsEarned: earned - uncategorized.reduce(0) { $0 + $1.grade.pointsEarned },
            pointsPossible: possible - uncategorized.reduce(0) { $0 + $1.grade.pointsPossible },
            gradedCount: usable.count - uncategorized.count,
            uncategorizedCount: uncategorized.count,
            gradedWeight: gradedWeight,
            totalWeight: totalWeight
        )
    }
}

/// The grade StudyOS shows for a course, and where it came from.
struct EffectiveGrade: Equatable {
    enum Source: Equatable {
        case calculated
        /// Typed in by hand on the course.
        case manual
    }

    var percent: Double
    var source: Source
}
