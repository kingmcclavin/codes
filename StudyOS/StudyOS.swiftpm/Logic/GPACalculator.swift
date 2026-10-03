import Foundation

/// One course's contribution to a GPA.
struct GPAContribution: Equatable {
    enum Basis: Equatable {
        /// The official final letter grade was recorded. ACTUAL.
        case finalGrade
        /// Estimated from the current course percentage. PROJECTED.
        case projectedFromCurrentGrade
    }

    var courseID: UUID?
    var credits: Double
    var gradePoints: Double
    var letter: String
    var basis: Basis
}

struct GPASummary: Equatable {
    var gpa: Double?
    var credits: Double
    /// True when any part of the GPA is projected from in-progress courses.
    var includesProjection: Bool
}

enum GPACalculator {
    /// Credit-weighted average of grade points.
    static func gpa(_ contributions: [GPAContribution]) -> Double? {
        let credits = contributions.reduce(0) { $0 + $1.credits }
        guard credits > 0 else { return nil }
        return contributions.reduce(0) { $0 + $1.gradePoints * $1.credits } / credits
    }

    /// What a course contributes, if anything.
    ///
    /// A recorded final letter grade always wins. When `allowProjection` is
    /// true, an in-progress course is estimated from its current percentage.
    static func contribution(for course: Course, effectivePercent: Double?, scale: GradingScale,
                             allowProjection: Bool) -> GPAContribution? {
        guard course.countsTowardGPA, course.credits > 0 else { return nil }
        if let letter = course.finalLetterGrade, let points = scale.gradePoints(forLetter: letter) {
            return GPAContribution(courseID: course.id, credits: course.credits, gradePoints: points,
                                   letter: letter, basis: .finalGrade)
        }
        guard allowProjection, let percent = effectivePercent, let step = scale.step(forPercent: percent) else {
            return nil
        }
        return GPAContribution(courseID: course.id, credits: course.credits, gradePoints: step.gradePoints,
                               letter: step.letter, basis: .projectedFromCurrentGrade)
    }

    /// Combines courses with credits earned before StudyOS.
    static func summary(_ contributions: [GPAContribution], priorCredits: Double = 0, priorGPA: Double? = nil) -> GPASummary {
        var all = contributions
        if priorCredits > 0, let priorGPA {
            all.append(GPAContribution(courseID: nil, credits: priorCredits, gradePoints: priorGPA,
                                       letter: "", basis: .finalGrade))
        }
        return GPASummary(
            gpa: gpa(all),
            credits: all.reduce(0) { $0 + $1.credits },
            includesProjection: all.contains { $0.basis == .projectedFromCurrentGrade }
        )
    }
}
