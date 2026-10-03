import SwiftUI

/// What sheet a Dashboard quick action opened.
enum CreateSheet: Identifiable {
    case course
    case assignment(courseID: UUID?)
    case exam(courseID: UUID?)

    var id: String {
        switch self {
        case .course: return "course"
        case .assignment: return "assignment"
        case .exam: return "exam"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var sheet: CreateSheet?
    @State private var editingAssignment: Assignment?
    @State private var editingExam: Exam?

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        // Re-evaluates the time-dependent sections every minute.
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(now: context.date)
                    if store.db.courses.isEmpty {
                        WelcomeCard(addCourse: { sheet = .course })
                    }
                    QuickActions(sheet: $sheet)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        TodayCard(now: context.date, editAssignment: { editingAssignment = $0 })
                        OverviewCard(now: context.date)
                        DueSoonCard(now: context.date, editAssignment: { editingAssignment = $0 })
                        UpcomingExamsCard(now: context.date, editExam: { editingExam = $0 })
                    }
                }
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Assignment", systemImage: "checklist") { sheet = .assignment(courseID: nil) }
                        .keyboardShortcut("n", modifiers: .command)
                    Button("Exam", systemImage: "doc.text.magnifyingglass") { sheet = .exam(courseID: nil) }
                    Button("Course", systemImage: "books.vertical") { sheet = .course }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .course: CourseEditorView(course: nil)
            case .assignment(let courseID): AssignmentEditorView(assignment: nil, defaultCourseID: courseID)
            case .exam(let courseID): ExamEditorView(exam: nil, defaultCourseID: courseID)
            }
        }
        .sheet(item: $editingAssignment) { AssignmentEditorView(assignment: $0) }
        .sheet(item: $editingExam) { ExamEditorView(exam: $0) }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(greeting(now: now))
                .font(.largeTitle.weight(.bold))
            if let semester = store.db.currentSemester {
                Text(semester.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func greeting(now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default: base = "Good evening"
        }
        let name = store.db.student.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? base : "\(base), \(name)"
    }
}

// MARK: - Welcome

private struct WelcomeCard: View {
    @EnvironmentObject private var store: AcademicStore
    let addCourse: () -> Void

    var body: some View {
        Card("Welcome to StudyOS", systemImage: "graduationcap") {
            Text("Start by adding your courses. Assignments, exams, grades and study time all connect back to them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Add Your First Course", systemImage: "plus", action: addCourse)
                    .buttonStyle(.borderedProminent)
                Button("Explore with Sample Data") { store.loadSampleData() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Quick actions

private struct QuickActions: View {
    @EnvironmentObject private var navigation: AppNavigation
    @Binding var sheet: CreateSheet?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                action("Add Assignment", "checklist") { sheet = .assignment(courseID: nil) }
                action("Add Exam", "doc.text.magnifyingglass") { sheet = .exam(courseID: nil) }
                action("Add Course", "books.vertical") { sheet = .course }
                action("Add Grade", "chart.bar.doc.horizontal") { navigation.section = .grades }
                action("Start Study Session", "timer") { navigation.startStudying(courseID: nil) }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today

private struct TodayCard: View {
    @EnvironmentObject private var store: AcademicStore
    let now: Date
    let editAssignment: (Assignment) -> Void

    var body: some View {
        let classes = store.db.classes(on: now)
        let due = store.db.assignmentsDue(on: now)
        let overdue = store.db.overdueAssignments(now: now)
        let examsToday = store.db.upcomingExams(from: Calendar.current.startOfDay(for: now))
            .filter { Calendar.current.isDate($0.date, inSameDayAs: now) }

        Card("Today", systemImage: "sun.max") {
            if classes.isEmpty && due.isEmpty && overdue.isEmpty && examsToday.isEmpty {
                CardEmptyText("Nothing scheduled today.")
            }
            if !examsToday.isEmpty {
                SubsectionTitle("Exams")
                ForEach(examsToday) { exam in
                    HStack {
                        CourseBadge(course: store.db.course(withID: exam.courseID), size: 24)
                        Text(exam.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(exam.date, format: .dateTime.hour().minute())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if !classes.isEmpty {
                SubsectionTitle("Classes")
                ForEach(classes) { occurrence in
                    HStack(spacing: 10) {
                        CourseBadge(course: occurrence.course, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(occurrence.course.name).font(.subheadline.weight(.medium))
                            Text([occurrence.meeting.kind, occurrence.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(occurrence.start, format: .dateTime.hour().minute())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(occurrence.end < now ? Color.secondary.opacity(0.6) : Color.secondary)
                    }
                    .opacity(occurrence.end < now ? 0.6 : 1)
                }
            }
            if !due.isEmpty {
                SubsectionTitle("Due Today")
                ForEach(due) { assignment in
                    AssignmentLine(assignment: assignment, now: now, showsDay: false) { editAssignment(assignment) }
                }
            }
            if !overdue.isEmpty {
                SubsectionTitle("Overdue")
                ForEach(overdue.prefix(5)) { assignment in
                    AssignmentLine(assignment: assignment, now: now, showsDay: true) { editAssignment(assignment) }
                }
            }
        }
    }
}

struct SubsectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

/// A compact assignment row with a completion checkbox, used in cards.
struct AssignmentLine: View {
    @EnvironmentObject private var store: AcademicStore
    let assignment: Assignment
    let now: Date
    var showsDay = true
    var showsCourse = true
    let open: () -> Void

    var body: some View {
        let course = store.db.course(withID: assignment.courseID)
        HStack(spacing: 10) {
            CompletionButton(assignment: assignment)
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(assignment.title)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(assignment.isCompleted)
                            .foregroundStyle(assignment.isCompleted ? Color.secondary : Color.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if showsCourse, let course {
                                Circle().fill(course.color.color).frame(width: 7, height: 7)
                                Text(course.shortName)
                            }
                            Text(assignment.type.displayName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if assignment.priority >= .high && !assignment.isCompleted {
                        Image(systemName: "exclamationmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(assignment.priority.tint)
                            .accessibilityLabel("\(assignment.priority.displayName) priority")
                    }
                    DueText(assignment: assignment, now: now, showsDay: showsDay)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct CompletionButton: View {
    @EnvironmentObject private var store: AcademicStore
    let assignment: Assignment

    var body: some View {
        Button {
            withAnimation(.snappy) { store.toggleCompleted(assignment.id) }
        } label: {
            Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(assignment.isCompleted ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(assignment.isCompleted ? "Mark not completed" : "Mark completed")
    }
}

struct DueText: View {
    let assignment: Assignment
    let now: Date
    var showsDay = true

    var body: some View {
        let overdue = assignment.isOverdue(now: now)
        VStack(alignment: .trailing, spacing: 1) {
            if showsDay {
                Text(DateText.relativeDay(assignment.dueDate, now: now))
            }
            if assignment.hasDueTime {
                Text(assignment.dueDate, format: .dateTime.hour().minute())
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(overdue ? Color.red : Color.secondary)
    }
}

// MARK: - Due soon

private struct DueSoonCard: View {
    @EnvironmentObject private var store: AcademicStore
    let now: Date
    let editAssignment: (Assignment) -> Void

    var body: some View {
        let soon = store.db.assignmentsDueSoon(after: now, days: 7)
        Card("Due Soon", systemImage: "calendar.badge.clock") {
            if soon.isEmpty {
                CardEmptyText("Nothing due in the next 7 days.")
            } else {
                ForEach(soon.prefix(8)) { assignment in
                    AssignmentLine(assignment: assignment, now: now) { editAssignment(assignment) }
                }
                if soon.count > 8 {
                    Text("+\(soon.count - 8) more in Assignments")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Exams

private struct UpcomingExamsCard: View {
    @EnvironmentObject private var store: AcademicStore
    let now: Date
    let editExam: (Exam) -> Void

    var body: some View {
        let exams = store.db.upcomingExams(from: now, limit: 5)
        Card("Upcoming Exams", systemImage: "doc.text.magnifyingglass") {
            if exams.isEmpty {
                CardEmptyText("No upcoming exams.")
            } else {
                ForEach(exams) { exam in
                    Button { editExam(exam) } label: {
                        ExamCountdownRow(exam: exam, course: store.db.course(withID: exam.courseID), now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ExamCountdownRow: View {
    let exam: Exam
    let course: Course?
    let now: Date

    var body: some View {
        let days = DateText.dayDifference(from: now, to: exam.date)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(days <= 0 ? "Today" : "\(days)")
                    .font(.system(days <= 0 ? .subheadline : .title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                if days > 0 {
                    Text(days == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52)
            .padding(.vertical, 6)
            .background((course?.color.color ?? .gray).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(course.map { "\($0.name) — \(exam.title)" } ?? exam.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(exam.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: exam.preparation)
                    .tint(course?.color.color ?? .accentColor)
                    .accessibilityLabel("Self-rated preparation")
                    .accessibilityValue("\(Int(exam.preparation * 100)) percent")
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Overview

private struct OverviewCard: View {
    @EnvironmentObject private var store: AcademicStore
    let now: Date

    var body: some View {
        let cumulative = store.db.cumulativeGPA
        let projected = store.db.projectedCumulativeGPA
        let semester = store.db.semesterGPA(store.db.student.currentSemesterID)
        let completion = store.db.completionRate(now: now)
        let week = StudyStatistics.week(containing: now)
        let studied = StudyStatistics.totalSeconds(store.db.studySessions, in: week)

        Card("Academic Overview", systemImage: "chart.line.uptrend.xyaxis") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    if cumulative.gpa != nil {
                        StatTile(title: "Cumulative GPA", value: PercentFormat.gpa(cumulative.gpa),
                                 caption: "\(PercentFormat.points(cumulative.credits)) credits", tag: "Actual")
                    } else {
                        StatTile(title: "Cumulative GPA", value: PercentFormat.gpa(projected.gpa),
                                 caption: "No final grades recorded yet", tag: projected.gpa == nil ? nil : "Projected")
                    }
                    StatTile(title: "Semester GPA", value: PercentFormat.gpa(semester.gpa),
                             caption: store.db.currentSemester?.name,
                             tag: semester.gpa == nil ? nil : (semester.includesProjection ? "Projected" : "Actual"))
                }
                GridRow {
                    StatTile(title: "Completion",
                             value: completion.total == 0 ? "—" : PercentFormat.string(Double(completion.completed) / Double(completion.total) * 100, digits: 0),
                             caption: "\(completion.completed) of \(completion.total) due so far")
                    StatTile(title: "Studied This Week", value: DurationFormat.short(studied),
                             caption: "\(StudyStatistics.sessions(store.db.studySessions, in: week).count) sessions")
                }
            }
        }
    }
}
