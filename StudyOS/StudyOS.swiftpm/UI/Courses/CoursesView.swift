import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var store: AcademicStore
    /// nil shows the current semester.
    @State private var semesterFilter: UUID?
    @State private var showingAll = false
    @State private var editing: Course?
    @State private var creating = false
    @State private var deleting: Course?

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)]

    private var visibleSemesterID: UUID? { semesterFilter ?? store.db.student.currentSemesterID }

    private var courses: [Course] {
        if showingAll || store.db.semesters.isEmpty {
            return store.db.courses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return store.db.courses(inSemester: visibleSemesterID)
    }

    var body: some View {
        ScrollView {
            if courses.isEmpty {
                ContentUnavailableView {
                    Label("No Courses", systemImage: "books.vertical")
                } description: {
                    Text("Add the courses you're taking. Everything else in StudyOS connects to them.")
                } actions: {
                    Button("Add Course") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(courses) { course in
                        NavigationLink(value: CourseRoute(courseID: course.id)) {
                            CourseCard(course: course)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = course }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = course }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(showingAll ? "All Courses" : (store.db.semester(withID: visibleSemesterID)?.name ?? "Courses"))
        .navigationDestination(for: CourseRoute.self) { route in
            CourseDashboardView(courseID: route.courseID)
        }
        .navigationDestination(for: CourseGradesRoute.self) { route in
            CourseGradesView(courseID: route.courseID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !store.db.semesters.isEmpty {
                    Menu {
                        Picker("Semester", selection: Binding(
                            get: { showingAll ? nil : visibleSemesterID },
                            set: { value in
                                showingAll = value == nil
                                semesterFilter = value
                            }
                        )) {
                            ForEach(store.db.sortedSemesters) { semester in
                                Text(semester.isArchived ? "\(semester.name) (Archived)" : semester.name)
                                    .tag(UUID?.some(semester.id))
                            }
                            Text("All Semesters").tag(UUID?.none)
                        }
                    } label: {
                        Label("Semester", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Course", systemImage: "plus") { creating = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        .sheet(isPresented: $creating) {
            CourseEditorView(course: nil, defaultSemesterID: showingAll ? nil : visibleSemesterID)
        }
        .sheet(item: $editing) { CourseEditorView(course: $0) }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "course")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Course", role: .destructive) {
                if let id = deleting?.id { store.deleteCourse(id) }
                deleting = nil
            }
        } message: {
            Text("Its assignments, exams and grades will be deleted. Study time is kept in your statistics.")
        }
    }
}

private struct CourseCard: View {
    @EnvironmentObject private var store: AcademicStore
    let course: Course

    var body: some View {
        let grade = store.db.effectiveGrade(for: course)
        let next = store.db.activeAssignments
            .filter { $0.courseID == course.id && !$0.isCompleted }
            .sorted(by: AcademicDatabase.dueOrder)
            .first

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                CourseBadge(course: course, size: 40)
                Spacer()
                if let grade {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(PercentFormat.string(grade.percent))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(store.db.student.gradingScale.letter(forPercent: grade.percent) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([course.code, course.professor].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Divider()
            if let next {
                HStack {
                    Text("Next: \(next.title)")
                        .lineLimit(1)
                    Spacer()
                    Text(DateText.relativeDay(next.dueDate))
                        .foregroundStyle(next.isOverdue() ? Color.red : Color.secondary)
                }
                .font(.caption)
            } else {
                Text("Nothing due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                .fill(course.color.color)
                .frame(height: 4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
