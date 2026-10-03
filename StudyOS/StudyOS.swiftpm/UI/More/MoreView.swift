import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var store: AcademicStore
    @State private var editingSemester: Semester?
    @State private var creatingSemester = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmingSample = false
    @State private var confirmingErase = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your Name", text: Binding(
                    get: { store.db.student.name },
                    set: { value in store.updateStudent { $0.name = value } }
                ))
                TextField("School", text: Binding(
                    get: { store.db.student.institution },
                    set: { value in store.updateStudent { $0.institution = value } }
                ))
            }

            Section {
                ForEach(store.db.sortedSemesters) { semester in
                    SemesterRow(semester: semester, isCurrent: semester.id == store.db.student.currentSemesterID)
                        .contentShape(Rectangle())
                        .onTapGesture { editingSemester = semester }
                        .swipeActions(edge: .leading) {
                            if semester.id != store.db.student.currentSemesterID {
                                Button("Make Current") { store.setCurrentSemester(semester.id) }
                                    .tint(.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if semester.id != store.db.student.currentSemesterID {
                                Button(semester.isArchived ? "Unarchive" : "Archive") {
                                    store.setSemesterArchived(semester.id, archived: !semester.isArchived)
                                }
                                .tint(.gray)
                            }
                        }
                }
                Button("Add Semester", systemImage: "plus") { creatingSemester = true }
            } header: {
                Text("Semesters")
            } footer: {
                Text("Archiving a finished semester hides its courses and work from everyday views. Its grades and history are kept and still count toward your GPA.")
            }

            Section {
                LabeledContent("Earlier Credits") {
                    TextField("0", value: Binding(
                        get: { store.db.student.priorCredits },
                        set: { value in store.updateStudent { $0.priorCredits = max(0, value) } }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("GPA for Those Credits") {
                    TextField("Optional", value: Binding(
                        get: { store.db.student.priorGPA },
                        set: { value in store.updateStudent { $0.priorGPA = value.map { min(max($0, 0), 5) } } }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Academic Record")
            } footer: {
                Text("Credits and GPA from before you started using StudyOS (for example, from your transcript). They're combined with courses that have a final grade to calculate your cumulative GPA.")
            }

            Section {
                NavigationLink("Grading Scale") { GradingScaleView() }
            } footer: {
                Text("Used to turn percentages into letter grades and grade points. Custom scales are planned for the Grades phase.")
            }

            Section {
                Button("Export All Data (JSON)", systemImage: "square.and.arrow.up") { export() }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share \(exportURL.lastPathComponent)", systemImage: "doc")
                    }
                }
                Button("Load Sample Data…", systemImage: "wand.and.stars") { confirmingSample = true }
                Button("Erase All Data…", systemImage: "trash", role: .destructive) { confirmingErase = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Everything is stored on this iPad, in an open JSON format. Saved at: \(store.storageLocation)")
            }

            Section("About") {
                LabeledContent("Version", value: "0.1 — Foundation (Phase 1)")
                Text("StudyOS is a standalone app. It doesn't read data from other apps such as Basis; importing study packages exported by Basis is planned for a later version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("More")
        .sheet(isPresented: $creatingSemester) {
            SemesterEditorView(semester: nil)
        }
        .sheet(item: $editingSemester) { SemesterEditorView(semester: $0) }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .confirmationDialog("Replace all data with sample data?", isPresented: $confirmingSample, titleVisibility: .visible) {
            Button("Replace with Sample Data", role: .destructive) { store.loadSampleData() }
        } message: {
            Text("Your current courses, assignments, grades and study sessions will be replaced. Export first if you want to keep them.")
        }
        .confirmationDialog("Erase all StudyOS data?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) { store.eraseAllData() }
        } message: {
            Text("This can't be undone. Export first if you want a copy.")
        }
    }

    private func export() {
        do {
            store.saveNow()
            exportURL = try store.makeExportFile()
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct SemesterRow: View {
    let semester: Semester
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(semester.name)
                Text("\(semester.startDate.formatted(date: .abbreviated, time: .omitted)) – \(semester.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent { SourceTag(text: "Current") }
            if semester.isArchived { SourceTag(text: "Archived") }
        }
    }
}

struct SemesterEditorView: View {
    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool
    @State private var draft: Semester
    @State private var makeCurrent: Bool

    init(semester: Semester?) {
        isNew = semester == nil
        _draft = State(initialValue: semester ?? SemesterSuggestion.suggested(for: Date()))
        _makeCurrent = State(initialValue: semester == nil)
    }

    private var courseCount: Int { store.db.courses.filter { $0.semesterID == draft.id }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Fall 2026"))
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
                if draft.id != store.db.student.currentSemesterID {
                    Section {
                        Toggle("Current Semester", isOn: $makeCurrent)
                        if !isNew {
                            Toggle("Archived", isOn: $draft.isArchived)
                                .disabled(makeCurrent)
                        }
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete Semester", role: .destructive) {
                            store.deleteSemester(draft.id)
                            dismiss()
                        }
                        .disabled(courseCount > 0)
                    } footer: {
                        if courseCount > 0 {
                            Text("This semester has \(courseCount) course(s). Archive it instead to keep its history.")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Semester" : "Edit Semester")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        var semester = draft
                        semester.name = semester.name.trimmingCharacters(in: .whitespaces)
                        // Include the whole final day.
                        let calendar = Calendar.current
                        semester.endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: semester.endDate) ?? semester.endDate
                        semester.startDate = calendar.startOfDay(for: semester.startDate)
                        store.upsertSemester(semester)
                        if makeCurrent { store.setCurrentSemester(semester.id) }
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct GradingScaleView: View {
    @EnvironmentObject private var store: AcademicStore

    var body: some View {
        let scale = store.db.student.gradingScale
        List {
            Section(scale.name) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Letter")
                        Text("Minimum")
                        Text("Grade Points")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(scale.steps) { step in
                        GridRow {
                            Text(step.letter).fontWeight(.medium)
                            Text(PercentFormat.string(step.minimumPercent, digits: 0))
                            Text(String(format: "%.1f", step.gradePoints))
                        }
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Grading Scale")
    }
}
