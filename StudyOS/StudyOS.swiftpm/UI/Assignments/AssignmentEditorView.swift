import SwiftUI

struct AssignmentEditorView: View {
    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: Assignment
    @State private var isGraded: Bool
    @State private var earned: Double?
    @State private var possible: Double?
    @State private var confirmingDelete = false

    init(assignment: Assignment?, defaultCourseID: UUID? = nil) {
        isNew = assignment == nil
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let defaultDue = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
        let initial = assignment ?? Assignment(courseID: defaultCourseID, title: "", dueDate: defaultDue)
        _draft = State(initialValue: initial)
        _isGraded = State(initialValue: initial.grade != nil)
        _earned = State(initialValue: initial.grade?.pointsEarned)
        _possible = State(initialValue: initial.grade?.pointsPossible ?? initial.pointsPossible)
    }

    private var course: Course? { store.db.course(withID: draft.courseID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("Problem Set 5"))
                        .font(.headline)
                    CoursePicker(title: "Course", courses: courseChoices, selection: $draft.courseID)
                    Picker("Type", selection: $draft.type) {
                        ForEach(AssignmentType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbol).tag(type)
                        }
                    }
                }

                Section("Due") {
                    DatePicker("Due", selection: $draft.dueDate,
                               displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : [.date])
                    Toggle("Specific Time", isOn: $draft.hasDueTime)
                }

                Section("Progress") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(AssignmentStatus.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper(value: Binding(
                        get: { draft.estimatedMinutes ?? 0 },
                        set: { draft.estimatedMinutes = $0 == 0 ? nil : $0 }
                    ), in: 0...(24 * 60), step: 15) {
                        LabeledContent("Estimated Time",
                                       value: draft.estimatedMinutes.map { DurationFormat.short(TimeInterval($0 * 60)) } ?? "None")
                    }
                }

                Section {
                    CategoryPicker(course: course, selection: $draft.categoryID)
                    HStack {
                        Text("Points Possible")
                        Spacer()
                        TextField("Optional", value: $draft.pointsPossible, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    Toggle("Graded", isOn: $isGraded.animation())
                    if isGraded {
                        ScoreFields(earned: $earned, possible: $possible)
                    }
                } header: {
                    Text("Grade")
                } footer: {
                    if let course, !course.categories.isEmpty, draft.categoryID == nil, isGraded {
                        Text("Choose a category so this grade counts toward \(course.name)'s weighted grade.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Details") {
                    TextField("Description", text: $draft.details, axis: .vertical)
                        .lineLimit(2...8)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...8)
                }

                if !isNew {
                    Section {
                        Button("Delete Assignment", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Assignment" : "Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.courseID) { _, _ in
                // A category belongs to one course.
                if course?.category(withID: draft.categoryID) == nil { draft.categoryID = nil }
            }
            .onChange(of: draft.pointsPossible) { _, newValue in
                if possible == nil || !isGraded { possible = newValue }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .confirmationDialog("Delete this assignment?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteAssignment(draft.id)
                    dismiss()
                }
            }
        }
    }

    /// Current-semester courses, plus the assignment's own course if it's elsewhere.
    private var courseChoices: [Course] {
        var list = store.db.currentCourses
        if let course, !list.contains(where: { $0.id == course.id }) { list.append(course) }
        return list
    }

    private var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isGraded { return earned != nil && (possible ?? 0) > 0 }
        return true
    }

    private func save() {
        var assignment = draft
        assignment.title = assignment.title.trimmingCharacters(in: .whitespaces)
        if isGraded, let earned, let possible, possible > 0 {
            let unchanged = draft.grade?.pointsEarned == earned && draft.grade?.pointsPossible == possible
            assignment.grade = unchanged ? draft.grade : Grade(pointsEarned: earned, pointsPossible: possible)
            if assignment.pointsPossible == nil { assignment.pointsPossible = possible }
        } else {
            assignment.grade = nil
        }
        store.upsertAssignment(assignment)
        dismiss()
    }
}
