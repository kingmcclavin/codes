import Foundation

/// Maps percentages to letter grades and letter grades to grade points.
struct GradingScale: Codable, Equatable {
    struct Step: Codable, Equatable, Identifiable {
        var id: String { letter }
        var letter: String
        /// Lowest percentage (inclusive) that earns this letter.
        var minimumPercent: Double
        var gradePoints: Double
    }

    var name: String
    /// Ordered from the highest letter to the lowest.
    var steps: [Step]

    static let standard = GradingScale(name: "Standard 4.0", steps: [
        Step(letter: "A", minimumPercent: 93, gradePoints: 4.0),
        Step(letter: "A-", minimumPercent: 90, gradePoints: 3.7),
        Step(letter: "B+", minimumPercent: 87, gradePoints: 3.3),
        Step(letter: "B", minimumPercent: 83, gradePoints: 3.0),
        Step(letter: "B-", minimumPercent: 80, gradePoints: 2.7),
        Step(letter: "C+", minimumPercent: 77, gradePoints: 2.3),
        Step(letter: "C", minimumPercent: 73, gradePoints: 2.0),
        Step(letter: "C-", minimumPercent: 70, gradePoints: 1.7),
        Step(letter: "D+", minimumPercent: 67, gradePoints: 1.3),
        Step(letter: "D", minimumPercent: 63, gradePoints: 1.0),
        Step(letter: "D-", minimumPercent: 60, gradePoints: 0.7),
        Step(letter: "F", minimumPercent: 0, gradePoints: 0.0),
    ])

    private var sortedSteps: [Step] {
        steps.sorted { $0.minimumPercent > $1.minimumPercent }
    }

    func step(forPercent percent: Double) -> Step? {
        sortedSteps.first { percent >= $0.minimumPercent } ?? sortedSteps.last
    }

    func letter(forPercent percent: Double) -> String? {
        step(forPercent: percent)?.letter
    }

    func gradePoints(forLetter letter: String) -> Double? {
        let wanted = letter.trimmingCharacters(in: .whitespaces).uppercased()
        return steps.first { $0.letter.uppercased() == wanted }?.gradePoints
    }

    var letters: [String] { sortedSteps.map(\.letter) }
}
