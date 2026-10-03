import Foundation

// Read-only questions the UI asks of the data. Kept free of SwiftUI so they
// can be tested on their own.

struct ClassMeetingOccurrence: Identifiable, Equatable {
    var id: String { "\(course.id)-\(meeting.id)" }
    var course: Course
    var meeting: MeetingTime
    var start: Date
    var end: Date
    var location: String { meeting.location.isEmpty ? course.room : meeting.location }
}

extension AcademicDatabase {
    // MARK: Lookup

    func course(withID id: UUID?) -> Course? {
        guard let id else { return nil }
        return courses.first { $0.id == id }
    }

    func semester(withID id: UUID?) -> Semester? {
        guard let id else { return nil }
        return semesters.first { $0.id == id }
    }

    var currentSemester: Semester? { semester(withID: student.currentSemesterID) }

    /// Semesters newest first.
    var sortedSemesters: [Semester] {
        semesters.sorted { $0.startDate > $1.startDate }
    }

    func courses(inSemester semesterID: UUID?) -> [Course] {
        courses.filter { $0.semesterID == semesterID }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Courses in the current semester. Before any semester exists, all courses.
    var currentCourses: [Course] {
        guard let id = student.currentSemesterID else {
            return courses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return courses(inSemester: id)
    }

    /// Courses whose semester is not archived (plus courses with no semester).
    var activeCourses: [Course] {
        let archived = Set(semesters.filter(\.isArchived).map(\.id))
        return courses.filter { $0.semesterID == nil || !archived.contains($0.semesterID!) }
    }

    // MARK: Schedule

    func classes(on date: Date, calendar: Calendar = .current) -> [ClassMeetingOccurrence] {
        let weekday = calendar.component(.weekday, from: date)
        let dayStart = calendar.startOfDay(for: date)
        var result: [ClassMeetingOccurrence] = []
        for course in currentCourses {
            if let semester = semester(withID: course.semesterID),
               dayStart < calendar.startOfDay(for: semester.startDate) || dayStart > semester.endDate {
                continue
            }
            for meeting in course.meetings where meeting.weekday == weekday {
                let start = dayStart.addingTimeInterval(TimeInterval(meeting.startMinute * 60))
                let end = dayStart.addingTimeInterval(TimeInterval(meeting.endMinute * 60))
                result.append(ClassMeetingOccurrence(course: course, meeting: meeting, start: start, end: end))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: Assignments

    private var activeCourseIDs: Set<UUID> { Set(activeCourses.map(\.id)) }

    /// Assignments that belong to non-archived courses (or no course).
    var activeAssignments: [Assignment] {
        let ids = activeCourseIDs
        return assignments.filter { $0.courseID == nil || ids.contains($0.courseID!) }
    }

    func assignmentsDue(on date: Date, calendar: Calendar = .current) -> [Assignment] {
        activeAssignments
            .filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted(by: Self.dueOrder)
    }

    /// Incomplete assignments due after today, within `days` days.
    func assignmentsDueSoon(after now: Date, days: Int, calendar: Calendar = .current) -> [Assignment] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let limit = calendar.date(byAdding: .day, value: days + 1, to: calendar.startOfDay(for: now)) ?? now
        return activeAssignments
            .filter { !$0.isCompleted && $0.dueDate >= tomorrow && $0.dueDate < limit }
            .sorted(by: Self.dueOrder)
    }

    func overdueAssignments(now: Date, calendar: Calendar = .current) -> [Assignment] {
        activeAssignments
            .filter { $0.isOverdue(now: now, calendar: calendar) && !calendar.isDate($0.dueDate, inSameDayAs: now) }
            .sorted(by: Self.dueOrder)
    }

    static func dueOrder(_ a: Assignment, _ b: Assignment) -> Bool {
        if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    /// Current-semester assignment completion: of the assignments that are
    /// due by now or already finished, how many are completed.
    /// (Work finished early counts; future work that isn't started yet doesn't count against you.)
    func completionRate(now: Date, calendar: Calendar = .current) -> (completed: Int, total: Int) {
        let ids = Set(currentCourses.map(\.id))
        let relevant = activeAssignments.filter { a in
            let inSemester = a.courseID.map(ids.contains) ?? true
            return inSemester && (a.isCompleted || a.effectiveDueDate(calendar: calendar) <= now)
        }
        return (relevant.filter(\.isCompleted).count, relevant.count)
    }

    // MARK: Exams

    func upcomingExams(from now: Date, limit: Int? = nil) -> [Exam] {
        let ids = activeCourseIDs
        let upcoming = exams
            .filter { $0.date >= now && ($0.courseID == nil || ids.contains($0.courseID!)) }
            .sorted { $0.date < $1.date }
        if let limit { return Array(upcoming.prefix(limit)) }
        return upcoming
    }

    // MARK: Grades

    func gradedItems(forCourse courseID: UUID) -> [GradedItem] {
        let fromAssignments = assignments.compactMap { a -> GradedItem? in
            guard a.courseID == courseID, let grade = a.grade else { return nil }
            return GradedItem(id: a.id, title: a.title, courseID: courseID, categoryID: a.categoryID, grade: grade, date: a.dueDate)
        }
        let fromExams = exams.compactMap { e -> GradedItem? in
            guard e.courseID == courseID, let grade = e.grade else { return nil }
            return GradedItem(id: e.id, title: e.title, courseID: courseID, categoryID: e.categoryID, grade: grade, date: e.date)
        }
        return (fromAssignments + fromExams).sorted { $0.date > $1.date }
    }

    func gradeResult(for course: Course) -> CourseGradeResult {
        GradeCalculator.calculate(course: course, items: gradedItems(forCourse: course.id))
    }

    /// The grade to display: a manual grade if one was typed in, otherwise the calculated one.
    func effectiveGrade(for course: Course) -> EffectiveGrade? {
        if let manual = course.manualGrade {
            return EffectiveGrade(percent: manual, source: .manual)
        }
        if let percent = gradeResult(for: course).percent {
            return EffectiveGrade(percent: percent, source: .calculated)
        }
        return nil
    }

    // MARK: GPA

    func gpaContributions(for courses: [Course], allowProjection: Bool) -> [GPAContribution] {
        courses.compactMap { course in
            GPACalculator.contribution(for: course, effectivePercent: effectiveGrade(for: course)?.percent,
                                       scale: student.gradingScale, allowProjection: allowProjection)
        }
    }

    /// ACTUAL cumulative GPA: only recorded final grades plus prior credits.
    var cumulativeGPA: GPASummary {
        GPACalculator.summary(gpaContributions(for: courses, allowProjection: false),
                              priorCredits: student.priorCredits, priorGPA: student.priorGPA)
    }

    /// PROJECTED cumulative GPA: also counts in-progress courses at their current grade.
    var projectedCumulativeGPA: GPASummary {
        GPACalculator.summary(gpaContributions(for: courses, allowProjection: true),
                              priorCredits: student.priorCredits, priorGPA: student.priorGPA)
    }

    /// GPA for one semester. In-progress courses are projected from their current grade.
    func semesterGPA(_ semesterID: UUID?) -> GPASummary {
        GPACalculator.summary(gpaContributions(for: courses(inSemester: semesterID), allowProjection: true))
    }

    // MARK: Study

    func studySessions(forCourse courseID: UUID) -> [StudySession] {
        studySessions.filter { $0.courseID == courseID }.sorted { $0.startedAt > $1.startedAt }
    }
}
