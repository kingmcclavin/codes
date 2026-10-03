import SwiftUI

struct AssignmentsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case assignments = "Assignments"
        case exams = "Exams"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .assignments

    var body: some View {
        Group {
            switch mode {
            case .assignments: AssignmentListView()
            case .exams: ExamListView()
            }
        }
        .navigationTitle(mode.rawValue)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }
}

// MARK: - Assignments

enum AssignmentSort: String, CaseIterable, Identifiable {
    case dueDate = "Due Date"
    case priority = "Priority"
    case course = "Course"
    case type = "Type"
    var id: String { rawValue }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case open = "Open"
    case all = "All"
    case completed = "Completed"
    var id: String { rawValue }
}

private struct AssignmentListView: View {
    @EnvironmentObject private var store: AcademicStore
    @State private var sort: AssignmentSort = .dueDate
    @State private var statusFilter: StatusFilter = .open
    @State private var courseFilter: UUID?
    @State private var typeFilter: AssignmentType?
    @State private var priorityFilter: Priority?
    @State private var searchText = ""
    @State private var editing: Assignment?
    @State private var creating = false

    private var filtered: [Assignment] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return store.db.activeAssignments.filter { a in
            switch statusFilter {
            case .open: if a.isCompleted { return false }
            case .completed: if !a.isCompleted { return false }
            case .all: break
            }
            if let courseFilter, a.courseID != courseFilter { return false }
            if let typeFilter, a.type != typeFilter { return false }
            if let priorityFilter, a.priority != priorityFilter { return false }
            if !query.isEmpty {
                let courseName = store.db.course(withID: a.courseID).map { "\($0.name) \($0.code)" } ?? ""
                let haystack = "\(a.title) \(a.details) \(a.notes) \(courseName)"
                if !haystack.localizedCaseInsensitiveContains(query) { return false }
            }
            return true
        }
    }

    private var hasFilters: Bool { courseFilter != nil || typeFilter != nil || priorityFilter != nil }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let groups = grouped(filtered, now: context.date)
            List {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { assignment in
                            AssignmentRow(assignment: assignment, now: context.date)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = assignment }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.toggleCompleted(assignment.id)
                                    } label: {
                                        Label(assignment.isCompleted ? "Reopen" : "Complete",
                                              systemImage: assignment.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteAssignment(assignment.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = assignment }
                                    Menu("Status") {
                                        ForEach(AssignmentStatus.allCases) { status in
                                            Button(status.displayName) {
                                                var updated = assignment
                                                updated.status = status
                                                store.upsertAssignment(updated)
                                            }
                                        }
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.deleteAssignment(assignment.id)
                                    }
                                }
                        }
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    if store.db.assignments.isEmpty {
                        ContentUnavailableView {
                            Label("No Assignments", systemImage: "checklist")
                        } description: {
                            Text("Add homework, labs, projects and anything else with a due date.")
                        } actions: {
                            Button("Add Assignment") { creating = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else if !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView("Nothing Here", systemImage: "checkmark.circle",
                                               description: Text(statusFilter == .open ? "You're all caught up." : "No assignments match these filters."))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search assignments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                Button("Add Assignment", systemImage: "plus") { creating = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $creating) { AssignmentEditorView(assignment: nil, defaultCourseID: courseFilter) }
        .sheet(item: $editing) { AssignmentEditorView(assignment: $0) }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(AssignmentSort.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Course", selection: $courseFilter) {
                Text("All Courses").tag(UUID?.none)
                ForEach(store.db.activeCourses) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            Picker("Type", selection: $typeFilter) {
                Text("All Types").tag(AssignmentType?.none)
                ForEach(AssignmentType.allCases) { Text($0.displayName).tag(AssignmentType?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Priority", selection: $priorityFilter) {
                Text("All Priorities").tag(Priority?.none)
                ForEach(Priority.allCases.reversed()) { Text($0.displayName).tag(Priority?.some($0)) }
            }
            .pickerStyle(.menu)
            if hasFilters {
                Button("Clear Filters", role: .destructive) {
                    courseFilter = nil
                    typeFilter = nil
                    priorityFilter = nil
                }
            }
        } label: {
            Label("Sort & Filter", systemImage: hasFilters
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private struct AssignmentGroup: Identifiable {
        var id: String { title }
        let title: String
        let items: [Assignment]
    }

    private func grouped(_ items: [Assignment], now: Date) -> [AssignmentGroup] {
        let calendar = Calendar.current
        switch sort {
        case .dueDate:
            let sorted = items.sorted(by: AcademicDatabase.dueOrder)
            var buckets: [(String, [Assignment])] = [
                ("Overdue", []), ("Today", []), ("Tomorrow", []), ("Next 7 Days", []), ("Later", []), ("Completed Earlier", []),
            ]
            for a in sorted {
                let days = DateText.dayDifference(from: now, to: a.dueDate, calendar: calendar)
                let index: Int
                if days < 0 { index = a.isCompleted ? 5 : 0 }
                else if days == 0 { index = 1 }
                else if days == 1 { index = 2 }
                else if days <= 7 { index = 3 }
                else { index = 4 }
                buckets[index].1.append(a)
            }
            // Most recent first for past completed work.
            buckets[5].1.reverse()
            return buckets.filter { !$0.1.isEmpty }.map { AssignmentGroup(title: $0.0, items: $0.1) }
        case .priority:
            return Priority.allCases.reversed().compactMap { p in
                let matching = items.filter { $0.priority == p }.sorted(by: AcademicDatabase.dueOrder)
                return matching.isEmpty ? nil : AssignmentGroup(title: p.displayName, items: matching)
            }
        case .type:
            return AssignmentType.allCases.compactMap { t in
                let matching = items.filter { $0.type == t }.sorted(by: AcademicDatabase.dueOrder)
                return matching.isEmpty ? nil : AssignmentGroup(title: t.displayName, items: matching)
            }
        case .course:
            var result = store.db.activeCourses
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .compactMap { c -> AssignmentGroup? in
                    let matching = items.filter { $0.courseID == c.id }.sorted(by: AcademicDatabase.dueOrder)
                    return matching.isEmpty ? nil : AssignmentGroup(title: c.name, items: matching)
                }
            let none = items.filter { $0.courseID == nil }.sorted(by: AcademicDatabase.dueOrder)
            if !none.isEmpty { result.append(AssignmentGroup(title: "No Course", items: none)) }
            return result
        }
    }
}

struct AssignmentRow: View {
    @EnvironmentObject private var store: AcademicStore
    let assignment: Assignment
    let now: Date

    var body: some View {
        let course = store.db.course(withID: assignment.courseID)
        HStack(spacing: 12) {
            CompletionButton(assignment: assignment)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(assignment.title)
                        .font(.body.weight(.medium))
                        .strikethrough(assignment.isCompleted)
                        .foregroundStyle(assignment.isCompleted ? Color.secondary : Color.primary)
                    if assignment.status == .inProgress {
                        Text("In Progress")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let course {
                        Circle().fill(course.color.color).frame(width: 8, height: 8)
                        Text(course.shortName)
                    }
                    Label(assignment.type.displayName, systemImage: assignment.type.symbol)
                        .labelStyle(.titleAndIcon)
                    if let minutes = assignment.estimatedMinutes, !assignment.isCompleted {
                        Text("· \(DurationFormat.short(TimeInterval(minutes * 60)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let grade = assignment.grade {
                Text(PercentFormat.string(grade.percent))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            if assignment.priority != .normal && !assignment.isCompleted {
                Text(assignment.priority.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(assignment.priority.tint)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(assignment.dueDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                if assignment.hasDueTime {
                    Text(assignment.dueDate, format: .dateTime.hour().minute())
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(assignment.isOverdue(now: now) ? Color.red : Color.secondary)
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Exams

private struct ExamListView: View {
    @EnvironmentObject private var store: AcademicStore
    @State private var editing: Exam?
    @State private var creating = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let activeIDs = Set(store.db.activeCourses.map(\.id))
            let exams = store.db.exams.filter { $0.courseID == nil || activeIDs.contains($0.courseID!) }
            let upcoming = exams.filter { $0.date >= now }.sorted { $0.date < $1.date }
            let past = exams.filter { $0.date < now }.sorted { $0.date > $1.date }
            List {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { exam in
                            Button { editing = exam } label: {
                                ExamCountdownRow(exam: exam, course: store.db.course(withID: exam.courseID), now: now)
                            }
                            .buttonStyle(.plain)
                            .swipeActions { deleteButton(exam) }
                        }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { exam in
                            Button { editing = exam } label: { PastExamRow(exam: exam) }
                                .buttonStyle(.plain)
                                .swipeActions { deleteButton(exam) }
                        }
                    }
                }
            }
            .overlay {
                if exams.isEmpty {
                    ContentUnavailableView {
                        Label("No Exams", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Add exams to see countdowns and track how prepared you feel.")
                    } actions: {
                        Button("Add Exam") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Exam", systemImage: "plus") { creating = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $creating) { ExamEditorView(exam: nil) }
        .sheet(item: $editing) { ExamEditorView(exam: $0) }
    }

    private func deleteButton(_ exam: Exam) -> some View {
        Button(role: .destructive) {
            store.deleteExam(exam.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct PastExamRow: View {
    @EnvironmentObject private var store: AcademicStore
    let exam: Exam

    var body: some View {
        let course = store.db.course(withID: exam.courseID)
        HStack(spacing: 12) {
            CourseBadge(course: course)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.map { "\($0.name) — \(exam.title)" } ?? exam.title)
                    .font(.body.weight(.medium))
                Text(exam.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let grade = exam.grade {
                Text(PercentFormat.string(grade.percent))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            } else {
                Text("Not graded").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
