import SwiftUI

struct ExamEditorView: View {
    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: Exam
    @State private var newTopic = ""
    @State private var isGraded: Bool
    @State private var earned: Double?
    @State private var possible: Double?
    @State private var confirmingDelete = false

    init(exam: Exam?, defaultCourseID: UUID? = nil) {
        isNew = exam == nil
        let calendar = Calendar.current
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date())) ?? Date()
        let defaultDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: inAWeek) ?? inAWeek
        let initial = exam ?? Exam(courseID: defaultCourseID, title: "", date: defaultDate)
        _draft = State(initialValue: initial)
        _isGraded = State(initialValue: initial.grade != nil)
        _earned = State(initialValue: initial.grade?.pointsEarned)
        _possible = State(initialValue: initial.grade?.pointsPossible ?? 100)
    }

    private var course: Course? { store.db.course(withID: draft.courseID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("Exam 2"))
                        .font(.headline)
                    CoursePicker(title: "Course", courses: courseChoices, selection: $draft.courseID)
                    DatePicker("Date", selection: $draft.date)
                    Stepper(value: Binding(
                        get: { draft.durationMinutes ?? 0 },
                        set: { draft.durationMinutes = $0 == 0 ? nil : $0 }
                    ), in: 0...600, step: 15) {
                        LabeledContent("Length", value: draft.durationMinutes.map { DurationFormat.short(TimeInterval($0 * 60)) } ?? "Not set")
                    }
                    TextField("Location", text: $draft.location)
                }

                Section("Topics") {
                    ForEach(Array(draft.topics.enumerated()), id: \.offset) { _, topic in
                        Text(topic)
                    }
                    .onDelete { draft.topics.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a topic", text: $newTopic)
                            .onSubmit(addTopic)
                        Button("Add", action: addTopic)
                            .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("How prepared do you feel?", value: "\(Int((draft.preparation * 100).rounded()))%")
                        Slider(value: $draft.preparation, in: 0...1, step: 0.05)
                    }
                    Stepper(value: Binding(
                        get: { draft.studyGoalMinutes ?? 0 },
                        set: { draft.studyGoalMinutes = $0 == 0 ? nil : $0 }
                    ), in: 0...(100 * 60), step: 30) {
                        LabeledContent("Study Goal", value: draft.studyGoalMinutes.map { DurationFormat.short(TimeInterval($0 * 60)) } ?? "None")
                    }
                } header: {
                    Text("Preparation")
                } footer: {
                    Text("Your own estimate, updated whenever you like. It's a planning aid, not a measurement of what you know.")
                }

                Section("Grade") {
                    CategoryPicker(course: course, selection: $draft.categoryID)
                    Toggle("Graded", isOn: $isGraded.animation())
                    if isGraded {
                        ScoreFields(earned: $earned, possible: $possible)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...8)
                }

                if !isNew {
                    Section {
                        Button("Delete Exam", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Exam" : "Edit Exam")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.courseID) { _, _ in
                if course?.category(withID: draft.categoryID) == nil {
                    // Suggest the course's exam-like category.
                    draft.categoryID = course?.categories.first {
                        let name = $0.name.lowercased()
                        return name.contains("exam") || name.contains("midterm") || name.contains("test")
                    }?.id
                }
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
            .confirmationDialog("Delete this exam?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteExam(draft.id)
                    dismiss()
                }
            }
        }
    }

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

    private func addTopic() {
        let topic = newTopic.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty else { return }
        draft.topics.append(topic)
        newTopic = ""
    }

    private func save() {
        var exam = draft
        exam.title = exam.title.trimmingCharacters(in: .whitespaces)
        let pending = newTopic.trimmingCharacters(in: .whitespaces)
        if !pending.isEmpty { exam.topics.append(pending) }
        exam.topics = exam.topics.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isGraded, let earned, let possible, possible > 0 {
            let unchanged = draft.grade?.pointsEarned == earned && draft.grade?.pointsPossible == possible
            exam.grade = unchanged ? draft.grade : Grade(pointsEarned: earned, pointsPossible: possible)
        } else {
            exam.grade = nil
        }
        store.upsertExam(exam)
        dismiss()
    }
}
