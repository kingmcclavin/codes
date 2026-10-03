import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var store: AcademicStore
    @State private var addingGradeFor: CourseRef?

    var body: some View {
        let db = store.db
        let cumulative = db.cumulativeGPA
        let projected = db.projectedCumulativeGPA
        let semesterGPA = db.semesterGPA(db.student.currentSemesterID)
        let courses = db.currentCourses

        List {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "Cumulative GPA", value: PercentFormat.gpa(cumulative.gpa),
                                 caption: cumulative.gpa == nil ? "Record final grades to see this"
                                    : "\(PercentFormat.points(cumulative.credits)) credits", tag: "Actual")
                        StatTile(title: "Projected Cumulative", value: PercentFormat.gpa(projected.gpa),
                                 caption: "If current grades hold", tag: "Projected")
                        StatTile(title: db.currentSemester?.name ?? "This Semester", value: PercentFormat.gpa(semesterGPA.gpa),
                                 caption: "\(PercentFormat.points(semesterGPA.credits)) credits",
                                 tag: semesterGPA.includesProjection ? "Projected" : "Actual")
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Actual GPA uses only final letter grades you've recorded (plus earlier credits entered in More). Projected GPA also counts courses in progress at their current grade.")
            }

            Section(db.currentSemester?.name ?? "Courses") {
                if courses.isEmpty {
                    Text("Add courses to start tracking grades.")
                        .foregroundStyle(.secondary)
                }
                ForEach(courses) { course in
                    NavigationLink(value: CourseGradesRoute(courseID: course.id)) {
                        CourseGradeRow(course: course)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Add Grade", systemImage: "plus") { addingGradeFor = CourseRef(id: course.id) }
                            .tint(.accentColor)
                    }
                }
            }

            let pastSemesters = db.sortedSemesters.filter { $0.id != db.student.currentSemesterID }
            if !pastSemesters.isEmpty {
                Section("Other Semesters") {
                    ForEach(pastSemesters) { semester in
                        let summary = db.semesterGPA(semester.id)
                        HStack {
                            VStack(alignment: .leading) {
                                Text(semester.name)
                                Text("\(db.courses(inSemester: semester.id).count) courses · \(PercentFormat.points(summary.credits)) credits")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if summary.gpa != nil {
                                SourceTag(text: summary.includesProjection ? "Projected" : "Actual")
                            }
                            Text(PercentFormat.gpa(summary.gpa))
                                .font(.headline).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Grades")
        .navigationDestination(for: CourseGradesRoute.self) { route in
            CourseGradesView(courseID: route.courseID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(courses) { course in
                        Button(course.name) { addingGradeFor = CourseRef(id: course.id) }
                    }
                } label: {
                    Label("Add Grade", systemImage: "plus")
                }
                .disabled(courses.isEmpty)
            }
        }
        .sheet(item: $addingGradeFor) { ref in
            GradeEntryView(courseID: ref.id)
        }
    }
}

struct CourseRef: Identifiable, Hashable {
    let id: UUID
}

private struct CourseGradeRow: View {
    @EnvironmentObject private var store: AcademicStore
    let course: Course

    var body: some View {
        let effective = store.db.effectiveGrade(for: course)
        let scale = store.db.student.gradingScale
        HStack(spacing: 12) {
            CourseBadge(course: course, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text("\(PercentFormat.points(course.credits)) credits")
                    if let target = course.targetGrade {
                        Text("· Target \(PercentFormat.string(target, digits: 0))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let final = course.finalLetterGrade {
                SourceTag(text: "Final")
                Text(final).font(.title3.weight(.semibold))
            } else if let effective {
                if effective.source == .manual { SourceTag(text: "Manual") }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(PercentFormat.string(effective.percent))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text(scale.letter(forPercent: effective.percent) ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No grades").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
