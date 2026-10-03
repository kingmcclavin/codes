import SwiftUI

struct CourseEditorView: View {
    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: Course
    @State private var hasTarget: Bool
    @State private var hasManualGrade: Bool

    init(course: Course?, defaultSemesterID: UUID? = nil) {
        isNew = course == nil
        let initial = course ?? Course(semesterID: defaultSemesterID, name: "")
        _draft = State(initialValue: initial)
        _hasTarget = State(initialValue: initial.targetGrade != nil)
        _hasManualGrade = State(initialValue: initial.manualGrade != nil)
    }

    private var totalWeight: Double { draft.categories.reduce(0) { $0 + $1.weight } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Course Name", text: $draft.name, prompt: Text("Physics II"))
                        .font(.headline)
                    TextField("Course Code", text: $draft.code, prompt: Text("PHYS 222"))
                    TextField("Professor", text: $draft.professor)
                    TextField("Room", text: $draft.room)
                    Stepper(value: $draft.credits, in: 0...12, step: 0.5) {
                        LabeledContent("Credits", value: PercentFormat.points(draft.credits))
                    }
                    if !store.db.semesters.isEmpty {
                        Picker("Semester", selection: $draft.semesterID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.db.sortedSemesters) { semester in
                                Text(semester.name).tag(UUID?.some(semester.id))
                            }
                        }
                    }
                } footer: {
                    if store.db.semesters.isEmpty && isNew {
                        Text("A semester will be created for you. You can manage semesters in More.")
                    }
                }

                Section("Appearance") {
                    ColorRow(selection: $draft.color)
                    IconRow(selection: $draft.icon, tint: draft.color.color)
                }

                MeetingsSection(meetings: $draft.meetings)

                Section {
                    ForEach($draft.categories) { $category in
                        HStack {
                            TextField("Category", text: $category.name)
                            TextField("Weight", value: $category.weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { draft.categories.remove(atOffsets: $0) }
                    Button("Add Category", systemImage: "plus") {
                        draft.categories.append(GradeCategory(name: "", weight: 0))
                    }
                    if draft.categories.isEmpty {
                        Menu("Use a Common Template") {
                            Button("Homework / Quizzes / Exams / Final") {
                                draft.categories = [
                                    GradeCategory(name: "Homework", weight: 20), GradeCategory(name: "Quizzes", weight: 15),
                                    GradeCategory(name: "Exams", weight: 40), GradeCategory(name: "Final", weight: 25),
                                ]
                            }
                            Button("Homework / Labs / Quizzes / Exams / Final") {
                                draft.categories = [
                                    GradeCategory(name: "Homework", weight: 15), GradeCategory(name: "Labs", weight: 20),
                                    GradeCategory(name: "Quizzes", weight: 15), GradeCategory(name: "Exams", weight: 30),
                                    GradeCategory(name: "Final", weight: 20),
                                ]
                            }
                        }
                    }
                } header: {
                    Text("Grade Categories")
                } footer: {
                    if draft.categories.isEmpty {
                        Text("Without categories, the course grade is total points earned ÷ total points possible.")
                    } else if abs(totalWeight - 100) > 0.001 {
                        Text("Weights add up to \(PercentFormat.points(totalWeight))%. They usually add up to 100%; StudyOS scales the graded categories proportionally either way.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Weights add up to 100%.")
                    }
                }

                Section {
                    Toggle("Target Grade", isOn: $hasTarget.animation())
                    if hasTarget {
                        PercentField(title: "Target", value: $draft.targetGrade)
                    }
                    Toggle("Enter Current Grade Manually", isOn: $hasManualGrade.animation())
                    if hasManualGrade {
                        PercentField(title: "Current Grade", value: $draft.manualGrade)
                    }
                    Picker("Final Grade", selection: $draft.finalLetterGrade) {
                        Text("In Progress").tag(String?.none)
                        ForEach(store.db.student.gradingScale.letters, id: \.self) { letter in
                            Text(letter).tag(String?.some(letter))
                        }
                    }
                    Toggle("Counts Toward GPA", isOn: $draft.countsTowardGPA)
                } header: {
                    Text("Grades")
                } footer: {
                    Text("A manual grade replaces the calculated one (useful if you only know your grade from a school portal). Record the final letter grade when the course ends — that is what your actual GPA uses.")
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(isNew ? "New Course" : "Edit Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private func save() {
        var course = draft
        course.name = course.name.trimmingCharacters(in: .whitespaces)
        course.code = course.code.trimmingCharacters(in: .whitespaces)
        if !hasTarget { course.targetGrade = nil }
        if !hasManualGrade { course.manualGrade = nil }
        course.categories = course.categories
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { var c = $0; c.weight = max(0, c.weight); return c }
        store.upsertCourse(course)
        dismiss()
    }
}

/// Optional percentage entry.
struct PercentField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("%").foregroundStyle(.secondary)
        }
    }
}

private struct ColorRow: View {
    @Binding var selection: CourseColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CourseColor.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IconRow: View {
    @Binding var selection: String
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
            ForEach(CourseIcon.all, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(symbol == selection ? Color.white : tint)
                        .background(symbol == selection ? tint : tint.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MeetingsSection: View {
    @Binding var meetings: [MeetingTime]

    var body: some View {
        Section {
            ForEach($meetings) { $meeting in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Day", selection: $meeting.weekday) {
                            ForEach(DateText.orderedWeekdays(), id: \.self) { day in
                                Text(DateText.weekdayName(day, short: false)).tag(day)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Picker("Kind", selection: $meeting.kind) {
                            ForEach(["Lecture", "Lab", "Discussion", "Recitation", "Seminar", "Studio"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                    }
                    HStack {
                        DatePicker("Starts", selection: $meeting.startMinute.asTimeOfDay(), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("to").foregroundStyle(.secondary)
                        DatePicker("Ends", selection: $meeting.endMinute.asTimeOfDay(), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        TextField("Room (optional)", text: $meeting.location)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { meetings.remove(atOffsets: $0) }
            Button("Add Class Time", systemImage: "plus") {
                let last = meetings.last
                meetings.append(MeetingTime(
                    weekday: last.map { $0.weekday % 7 + 1 } ?? 2,
                    startMinute: last?.startMinute ?? 9 * 60,
                    endMinute: last?.endMinute ?? 9 * 60 + 50
                ))
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Weekly class times appear on your Dashboard on the days they meet.")
        }
    }
}
