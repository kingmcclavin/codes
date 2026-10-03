import SwiftUI

struct CourseDashboardView: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation
    let courseID: UUID

    @State private var editingCourse: Course?
    @State private var sheet: CreateSheet?
    @State private var editingAssignment: Assignment?
    @State private var editingExam: Exam?

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]

    var body: some View {
        if let course = store.db.course(withID: courseID) {
            content(course)
        } else {
            ContentUnavailableView("Course Not Found", systemImage: "questionmark.folder")
        }
    }

    private func content(_ course: Course) -> some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CourseHeader(course: course, semester: store.db.semester(withID: course.semesterID))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        CourseGradeCard(course: course)
                        upcomingCard(course, now: context.date)
                        recentGradesCard(course)
                        CourseStudyCard(course: course, now: context.date)
                        scheduleCard(course)
                        if !course.notes.isEmpty {
                            Card("Notes", systemImage: "note.text") {
                                Text(course.notes)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Study", systemImage: "timer") {
                    navigation.startStudying(courseID: course.id)
                }
                Menu {
                    Button("Assignment", systemImage: "checklist") { sheet = .assignment(courseID: course.id) }
                    Button("Exam", systemImage: "doc.text.magnifyingglass") { sheet = .exam(courseID: course.id) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button("Edit") { editingCourse = course }
            }
        }
        .sheet(item: $editingCourse) { CourseEditorView(course: $0) }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .course: CourseEditorView(course: nil)
            case .assignment(let id): AssignmentEditorView(assignment: nil, defaultCourseID: id)
            case .exam(let id): ExamEditorView(exam: nil, defaultCourseID: id)
            }
        }
        .sheet(item: $editingAssignment) { AssignmentEditorView(assignment: $0) }
        .sheet(item: $editingExam) { ExamEditorView(exam: $0) }
    }

    private func upcomingCard(_ course: Course, now: Date) -> some View {
        let assignments = store.db.assignments
            .filter { $0.courseID == course.id && !$0.isCompleted }
            .sorted(by: AcademicDatabase.dueOrder)
        let exams = store.db.upcomingExams(from: now).filter { $0.courseID == course.id }
        return Card("Upcoming", systemImage: "calendar.badge.clock") {
            if assignments.isEmpty && exams.isEmpty {
                CardEmptyText("Nothing coming up.")
            }
            ForEach(exams) { exam in
                Button { editingExam = exam } label: {
                    ExamCountdownRow(exam: exam, course: course, now: now)
                }
                .buttonStyle(.plain)
            }
            ForEach(assignments.prefix(8)) { assignment in
                AssignmentLine(assignment: assignment, now: now, showsCourse: false) { editingAssignment = assignment }
            }
        }
    }

    private func recentGradesCard(_ course: Course) -> some View {
        let items = store.db.gradedItems(forCourse: course.id)
        return Card("Recent Grades", systemImage: "list.number", accessory: {
            NavigationLink(value: CourseGradesRoute(courseID: course.id)) {
                Text("All Grades")
                    .font(.subheadline)
            }
        }) {
            if items.isEmpty {
                CardEmptyText("No grades yet.")
            } else {
                ForEach(items.prefix(6), id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline)
                            Text(course.category(withID: item.categoryID)?.name ?? "Uncategorized")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(PercentFormat.string(item.grade.percent))
                                .font(.subheadline.weight(.medium)).monospacedDigit()
                            Text("\(PercentFormat.points(item.grade.pointsEarned))/\(PercentFormat.points(item.grade.pointsPossible))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func scheduleCard(_ course: Course) -> some View {
        Card("Schedule", systemImage: "clock") {
            if course.meetings.isEmpty {
                CardEmptyText("No class times. Add them in Edit.")
            } else {
                let order = DateText.orderedWeekdays()
                ForEach(course.meetings.sorted {
                    (order.firstIndex(of: $0.weekday) ?? 0, $0.startMinute) < (order.firstIndex(of: $1.weekday) ?? 0, $1.startMinute)
                }) { meeting in
                    HStack {
                        Text(DateText.weekdayName(meeting.weekday, short: false))
                            .frame(width: 100, alignment: .leading)
                        Text("\(DateText.time(minutes: meeting.startMinute)) – \(DateText.time(minutes: meeting.endMinute))")
                            .monospacedDigit()
                        Spacer()
                        Text([meeting.kind, meeting.location.isEmpty ? course.room : meeting.location]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct CourseHeader: View {
    let course: Course
    let semester: Semester?

    var body: some View {
        HStack(spacing: 16) {
            CourseBadge(course: course, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.largeTitle.weight(.bold))
                Text([
                    course.code,
                    course.professor,
                    "\(PercentFormat.points(course.credits)) credits",
                    course.room,
                    semester?.name ?? "",
                ].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Current vs. target grade for a course.
struct CourseGradeCard: View {
    @EnvironmentObject private var store: AcademicStore
    let course: Course
    var showsDetailsLink = true

    var body: some View {
        let effective = store.db.effectiveGrade(for: course)
        let result = store.db.gradeResult(for: course)
        let scale = store.db.student.gradingScale

        Card("Grade", systemImage: "chart.bar.doc.horizontal", accessory: {
            if showsDetailsLink {
                NavigationLink(value: CourseGradesRoute(courseID: course.id)) {
                    Text("Details").font(.subheadline)
                }
            }
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Current").font(.subheadline).foregroundStyle(.secondary)
                        if let effective {
                            SourceTag(text: effective.source == .manual ? "Manual" : "Actual")
                        }
                    }
                    Text(PercentFormat.string(effective?.percent))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let percent = effective?.percent, let letter = scale.letter(forPercent: percent) {
                        Text(letter).font(.headline).foregroundStyle(.secondary)
                    }
                }
                if let target = course.targetGrade {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target").font(.subheadline).foregroundStyle(.secondary)
                        Text(PercentFormat.string(target))
                            .font(.system(.title, design: .rounded).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let percent = effective?.percent {
                            let gap = percent - target
                            Text(gap >= 0 ? "On target" : "\(PercentFormat.string(-gap)) below")
                                .font(.caption)
                                .foregroundStyle(gap >= 0 ? Color.green : Color.orange)
                        }
                    }
                }
            }
            if let final = course.finalLetterGrade {
                Text("Final grade recorded: \(final)")
                    .font(.caption).foregroundStyle(.secondary)
            } else if result.method == .weighted {
                Text("Based on \(PercentFormat.points(result.gradedWeight))% of the course weight graded so far.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if result.method == .none && effective == nil {
                Text("Enter grades to see your current grade.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CourseStudyCard: View {
    @EnvironmentObject private var store: AcademicStore
    let course: Course
    let now: Date

    var body: some View {
        let sessions = store.db.studySessions(forCourse: course.id)
        let week = StudyStatistics.week(containing: now)
        let thisWeek = StudyStatistics.totalSeconds(sessions, in: week)
        let total = sessions.reduce(0) { $0 + $1.durationSeconds }

        Card("Study Time", systemImage: "timer") {
            HStack(spacing: 24) {
                StatTile(title: "This Week", value: DurationFormat.short(thisWeek))
                StatTile(title: "All Time", value: DurationFormat.short(total), caption: "\(sessions.count) sessions")
            }
            if let last = sessions.first {
                Divider()
                HStack {
                    Text(last.topic.isEmpty ? "Last session" : last.topic)
                        .lineLimit(1)
                    Spacer()
                    Text("\(DurationFormat.short(last.durationSeconds)) · \(DateText.relativeDay(last.startedAt, now: now))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }
}
