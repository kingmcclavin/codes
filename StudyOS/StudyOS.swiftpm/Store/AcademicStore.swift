import Foundation
import SwiftUI

/// The app's single source of truth. Views read `db` and change data only
/// through the methods below; every change is saved automatically.
@MainActor
final class AcademicStore: ObservableObject {
    @Published private(set) var db: AcademicDatabase
    /// Shown once at launch when data had to be recovered.
    @Published var startupMessage: String?
    @Published private(set) var lastSaveError: String?

    private let fileStore: DatabaseFileStore
    private var pendingSave: Task<Void, Never>?

    init(fileStore: DatabaseFileStore = .standard()) {
        self.fileStore = fileStore
        let (loaded, outcome) = fileStore.load()
        self.db = loaded
        switch outcome {
        case .empty, .loaded:
            startupMessage = nil
        case .recoveredFromBackup(let file):
            startupMessage = "StudyOS couldn't read its latest data file, so it restored your most recent backup."
                + (file.isEmpty ? "" : " The unreadable file was kept as “\(file)”.")
        case .failed(let file):
            startupMessage = "StudyOS couldn't read its data file and no backup was available."
                + (file.map { " The unreadable file was kept as “\($0)” so it can be recovered." } ?? "")
        }
    }

    // MARK: Saving

    private func mutate(_ change: (inout AcademicDatabase) -> Void) {
        change(&db)
        scheduleSave()
    }

    /// Saves shortly after the last change, so rapid edits are written once.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes immediately (used when the app goes to the background).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try fileStore.save(db)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    // MARK: Student & semesters

    func updateStudent(_ change: (inout Student) -> Void) {
        mutate { change(&$0.student) }
    }

    func upsertSemester(_ semester: Semester) {
        mutate { db in
            if let i = db.semesters.firstIndex(where: { $0.id == semester.id }) {
                db.semesters[i] = semester
            } else {
                db.semesters.append(semester)
            }
            if db.student.currentSemesterID == nil { db.student.currentSemesterID = semester.id }
        }
    }

    func setCurrentSemester(_ id: UUID) {
        mutate { db in
            db.student.currentSemesterID = id
            // The current semester is in use, so it can't stay archived.
            if let i = db.semesters.firstIndex(where: { $0.id == id }) { db.semesters[i].isArchived = false }
        }
    }

    func setSemesterArchived(_ id: UUID, archived: Bool) {
        mutate { db in
            guard let i = db.semesters.firstIndex(where: { $0.id == id }) else { return }
            db.semesters[i].isArchived = archived
        }
    }

    /// Only empty semesters can be deleted; the UI archives others instead.
    func deleteSemester(_ id: UUID) {
        guard !db.courses.contains(where: { $0.semesterID == id }) else { return }
        mutate { db in
            db.semesters.removeAll { $0.id == id }
            if db.student.currentSemesterID == id {
                db.student.currentSemesterID = db.sortedSemesters.first(where: { !$0.isArchived })?.id
            }
        }
    }

    // MARK: Courses

    func upsertCourse(_ course: Course) {
        var course = course
        mutate { db in
            // The very first course gets a semester automatically, so nobody has to
            // set up semesters before they can start.
            if course.semesterID == nil && db.semesters.isEmpty {
                let semester = SemesterSuggestion.suggested(for: Date())
                db.semesters.append(semester)
                db.student.currentSemesterID = semester.id
                course.semesterID = semester.id
            }
            if let i = db.courses.firstIndex(where: { $0.id == course.id }) {
                let removedCategories = Set(db.courses[i].categories.map(\.id)).subtracting(course.categories.map(\.id))
                db.courses[i] = course
                // Work that pointed at a deleted category becomes uncategorized.
                if !removedCategories.isEmpty {
                    for j in db.assignments.indices where db.assignments[j].categoryID.map(removedCategories.contains) == true {
                        db.assignments[j].categoryID = nil
                    }
                    for j in db.exams.indices where db.exams[j].categoryID.map(removedCategories.contains) == true {
                        db.exams[j].categoryID = nil
                    }
                }
            } else {
                db.courses.append(course)
            }
        }
    }

    /// Deletes a course with its assignments and exams. Study sessions are kept
    /// (unlinked) so study-time history stays accurate.
    func deleteCourse(_ id: UUID) {
        mutate { db in
            db.courses.removeAll { $0.id == id }
            db.assignments.removeAll { $0.courseID == id }
            db.exams.removeAll { $0.courseID == id }
            for i in db.studySessions.indices where db.studySessions[i].courseID == id {
                db.studySessions[i].courseID = nil
            }
            if db.activeTimer?.courseID == id { db.activeTimer?.courseID = nil }
        }
    }

    // MARK: Assignments

    func upsertAssignment(_ assignment: Assignment) {
        var assignment = assignment
        if assignment.status == .completed && assignment.completedAt == nil { assignment.completedAt = Date() }
        if assignment.status != .completed { assignment.completedAt = nil }
        mutate { db in
            if let i = db.assignments.firstIndex(where: { $0.id == assignment.id }) {
                db.assignments[i] = assignment
            } else {
                db.assignments.append(assignment)
            }
        }
    }

    func deleteAssignment(_ id: UUID) {
        mutate { $0.assignments.removeAll { $0.id == id } }
    }

    func toggleCompleted(_ id: UUID) {
        guard var assignment = db.assignments.first(where: { $0.id == id }) else { return }
        assignment.status = assignment.isCompleted ? .notStarted : .completed
        upsertAssignment(assignment)
    }

    func setGrade(_ grade: Grade?, forAssignment id: UUID) {
        mutate { db in
            guard let i = db.assignments.firstIndex(where: { $0.id == id }) else { return }
            db.assignments[i].grade = grade
            if grade != nil && !db.assignments[i].isCompleted {
                db.assignments[i].status = .completed
                db.assignments[i].completedAt = Date()
            }
        }
    }

    // MARK: Exams

    func upsertExam(_ exam: Exam) {
        mutate { db in
            if let i = db.exams.firstIndex(where: { $0.id == exam.id }) {
                db.exams[i] = exam
            } else {
                db.exams.append(exam)
            }
        }
    }

    func deleteExam(_ id: UUID) {
        mutate { $0.exams.removeAll { $0.id == id } }
    }

    func setGrade(_ grade: Grade?, forExam id: UUID) {
        mutate { db in
            guard let i = db.exams.firstIndex(where: { $0.id == id }) else { return }
            db.exams[i].grade = grade
        }
    }

    // MARK: Study timer

    func startTimer(courseID: UUID?, topic: String) {
        guard db.activeTimer == nil else { return }
        mutate { $0.activeTimer = ActiveStudyTimer(courseID: courseID, topic: topic.trimmingCharacters(in: .whitespacesAndNewlines), startedAt: Date()) }
    }

    func pauseTimer() {
        mutate { $0.activeTimer?.pause(at: Date()) }
    }

    func resumeTimer() {
        mutate { $0.activeTimer?.resume(at: Date()) }
    }

    func updateTimer(courseID: UUID?, topic: String) {
        mutate { db in
            db.activeTimer?.courseID = courseID
            db.activeTimer?.topic = topic
        }
    }

    /// Ends the running timer and records it as a study session.
    @discardableResult
    func finishTimer(notes: String) -> StudySession? {
        guard let timer = db.activeTimer else { return nil }
        let now = Date()
        let session = StudySession(courseID: timer.courseID, topic: timer.topic, startedAt: timer.startedAt,
                                   endedAt: now, durationSeconds: timer.elapsed(at: now),
                                   notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        mutate { db in
            db.studySessions.append(session)
            db.activeTimer = nil
        }
        return session
    }

    func discardTimer() {
        mutate { $0.activeTimer = nil }
    }

    func deleteStudySession(_ id: UUID) {
        mutate { $0.studySessions.removeAll { $0.id == id } }
    }

    // MARK: Data

    func loadSampleData() {
        mutate { $0 = SampleData.make() }
    }

    func eraseAllData() {
        mutate { $0 = AcademicDatabase() }
    }

    /// Writes a JSON copy of all data to a temporary file for sharing.
    func makeExportFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyOS Export \(formatter.string(from: Date())).json")
        try fileStore.exportCopy(db, to: url)
        return url
    }

    var storageLocation: String { fileStore.databaseURL.path }
}
