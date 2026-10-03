import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, courses, assignments, calendar, grades, study, materials, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .courses: return "Courses"
        case .assignments: return "Assignments"
        case .calendar: return "Calendar"
        case .grades: return "Grades"
        case .study: return "Study"
        case .materials: return "Materials"
        case .more: return "More"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .courses: return "books.vertical"
        case .assignments: return "checklist"
        case .calendar: return "calendar"
        case .grades: return "chart.bar.doc.horizontal"
        case .study: return "timer"
        case .materials: return "folder"
        case .more: return "ellipsis.circle"
        }
    }

    static let planning: [AppSection] = [.dashboard, .courses, .assignments, .calendar, .grades]
    static let learning: [AppSection] = [.study, .materials]
}

/// Cross-section navigation, e.g. a Dashboard quick action opening Study.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var section: AppSection? = .dashboard
    /// Course to pre-select the next time the Study timer setup appears.
    @Published var pendingStudyCourseID: UUID?

    func startStudying(courseID: UUID?) {
        pendingStudyCourseID = courseID
        section = .study
    }
}

/// Navigation value for opening a course dashboard.
struct CourseRoute: Hashable {
    let courseID: UUID
}

/// Navigation value for opening a course's grade breakdown.
struct CourseGradesRoute: Hashable {
    let courseID: UUID
}
