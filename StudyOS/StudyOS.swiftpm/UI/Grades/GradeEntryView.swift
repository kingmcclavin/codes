import SwiftUI

/// Records a grade, either on existing work or as a new graded item.
struct GradeEntryView: View {
    enum Target: Hashable {
        case newItem
        case assignment(UUID)
        case exam(UUID)
    }

    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss
    let courseID: UUID

    @State private var target: Target = .newItem
    @State private var title = ""
    @State private var type: AssignmentType = .homework
    @State private var categoryID: UUID?
    @State private var date = Date()
    @State private var earned: Double?
    @State private var possible: Double?

    private var course: Course? { store.db.course(withID: courseID) }

    private var ungradedAssignments: [Assignment] {
        store.db.assignments
            .filter { $0.courseID == courseID && $0.grade == nil }
            .sorted { $0.dueDate > $1.dueDate }
    }

    private var ungradedExams: [Exam] {
        store.db.exams
            .filter { $0.courseID == courseID && $0.grade == nil }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grade For", selection: $target) {
                        Text("New Graded Item").tag(Target.newItem)
                        ForEach(ungradedExams) { Text("Exam: \($0.title)").tag(Target.exam($0.id)) }
                        ForEach(ungradedAssignments) { Text($0.title).tag(Target.assignment($0.id)) }
                    }
                } footer: {
                    Text("Choose existing work without a grade, or add a new graded item.")
                }

                if target == .newItem {
                    Section("Item") {
                        TextField("Title", text: $title, prompt: Text("Quiz 4"))
                        Picker("Type", selection: $type) {
                            ForEach(AssignmentType.allCases) { Text($0.displayName).tag($0) }
                        }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        CategoryPicker(course: course, selection: $categoryID)
                    }
                }

                Section("Score") {
                    ScoreFields(earned: $earned, possible: $possible)
                }
            }
            .navigationTitle(course.map { "Grade — \($0.name)" } ?? "Add Grade")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: target) { _, newTarget in
                switch newTarget {
                case .assignment(let id):
                    if let points = store.db.assignments.first(where: { $0.id == id })?.pointsPossible { possible = points }
                case .exam:
                    if possible == nil { possible = 100 }
                case .newItem:
                    break
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private var canSave: Bool {
        guard earned != nil, (possible ?? 0) > 0 else { return false }
        if target == .newItem { return !title.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func save() {
        guard let earned, let possible, possible > 0 else { return }
        let grade = Grade(pointsEarned: earned, pointsPossible: possible)
        switch target {
        case .assignment(let id):
            store.setGrade(grade, forAssignment: id)
        case .exam(let id):
            store.setGrade(grade, forExam: id)
        case .newItem:
            store.upsertAssignment(Assignment(
                courseID: courseID, title: title.trimmingCharacters(in: .whitespaces), type: type,
                dueDate: date, hasDueTime: false, status: .completed, categoryID: categoryID,
                pointsPossible: possible, grade: grade
            ))
        }
        dismiss()
    }
}
