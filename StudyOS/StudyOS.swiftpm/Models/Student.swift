import Foundation

/// The person using StudyOS, plus academic history recorded before they
/// started using the app.
struct Student: Codable, Equatable {
    var name: String = ""
    var institution: String = ""
    var currentSemesterID: UUID? = nil

    /// Credits earned before StudyOS (for example, earlier transcripts).
    var priorCredits: Double = 0
    /// GPA for those prior credits. Combined with StudyOS courses for the cumulative GPA.
    var priorGPA: Double? = nil

    var gradingScale: GradingScale = .standard

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name, default: "")
        institution = try c.decode(String.self, forKey: .institution, default: "")
        currentSemesterID = try c.decodeIfPresent(UUID.self, forKey: .currentSemesterID)
        priorCredits = try c.decode(Double.self, forKey: .priorCredits, default: 0)
        priorGPA = try c.decodeIfPresent(Double.self, forKey: .priorGPA)
        gradingScale = try c.decode(GradingScale.self, forKey: .gradingScale, default: .standard)
    }
}
