import SwiftUI

/// Category breakdown and every graded item for one course.
struct CourseGradesView: View {
    @EnvironmentObject private var store: AcademicStore
    let courseID: UUID

    @State private var addingGrade = false
    @State private var editingCourse: Course?
    @State private var editingAssignment: Assignment?
    @State private var editingExam: Exam?

    var body: some View {
        if let course = store.db.course(withID: courseID) {
            content(course)
        } else {
            ContentUnavailableView("Course Not Found", systemImage: "questionmark.folder")
        }
    }

    private func content(_ course: Course) -> some View {
        let result = store.db.gradeResult(for: course)
        let items = store.db.gradedItems(forCourse: course.id)

        return List {
            Section {
                CourseGradeCard(course: course, showsDetailsLink: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !course.categories.isEmpty {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Category")
                            Text("Weight").gridColumnAlignment(.trailing)
                            Text("Points").gridColumnAlignment(.trailing)
                            Text("Average").gridColumnAlignment(.trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(result.categories) { category in
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.category.name)
                                    Text(category.gradedCount == 1 ? "1 grade" : "\(category.gradedCount) grades")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(PercentFormat.points(category.category.weight))%")
                                Text(category.pointsPossible > 0
                                     ? "\(PercentFormat.points(category.pointsEarned)) / \(PercentFormat.points(category.pointsPossible))"
                                     : "—")
                                    .foregroundStyle(.secondary)
                                Text(PercentFormat.string(category.percent))
                                    .fontWeight(.medium)
                            }
                            .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Categories")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Each category's average is its points earned ÷ points possible. Averages are combined by weight, counting only categories with grades so far.")
                        if abs(result.totalWeight - 100) > 0.001 {
                            Text("Category weights add up to \(PercentFormat.points(result.totalWeight))%, not 100%.")
                                .foregroundStyle(.orange)
                        }
                        if result.uncategorizedCount > 0 {
                            Text("\(result.uncategorizedCount) graded item(s) have no category and aren't counted. Edit them to choose a category.")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else if result.method == .totalPoints {
                Section {
                    LabeledContent("Points Earned", value: PercentFormat.points(result.pointsEarned))
                    LabeledContent("Points Possible", value: PercentFormat.points(result.pointsPossible))
                } header: {
                    Text("Points")
                } footer: {
                    Text("This course has no grade categories, so the grade is total points earned ÷ total points possible. Add weighted categories in Edit Course.")
                }
            }

            Section("Graded Work") {
                if items.isEmpty {
                    Text("No grades recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.id) { item in
                    Button { open(item) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(Color.primary)
                                Text("\(course.category(withID: item.categoryID)?.name ?? "Uncategorized") · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(PercentFormat.string(item.grade.percent))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.primary)
                                Text("\(PercentFormat.points(item.grade.pointsEarned)) / \(PercentFormat.points(item.grade.pointsPossible))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                    }
                    .swipeActions {
                        Button("Remove Grade", systemImage: "minus.circle", role: .destructive) {
                            removeGrade(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(course.name) Grades")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit Categories") { editingCourse = course }
                Button("Add Grade", systemImage: "plus") { addingGrade = true }
            }
        }
        .sheet(isPresented: $addingGrade) { GradeEntryView(courseID: course.id) }
        .sheet(item: $editingCourse) { CourseEditorView(course: $0) }
        .sheet(item: $editingAssignment) { AssignmentEditorView(assignment: $0) }
        .sheet(item: $editingExam) { ExamEditorView(exam: $0) }
    }

    private func open(_ item: GradedItem) {
        if let assignment = store.db.assignments.first(where: { $0.id == item.id }) {
            editingAssignment = assignment
        } else if let exam = store.db.exams.first(where: { $0.id == item.id }) {
            editingExam = exam
        }
    }

    private func removeGrade(_ item: GradedItem) {
        if store.db.assignments.contains(where: { $0.id == item.id }) {
            store.setGrade(nil, forAssignment: item.id)
        } else {
            store.setGrade(nil, forExam: item.id)
        }
    }
}
