import Foundation

// Developer-only checks for StudyOS's non-UI code (models, persistence,
// grade/GPA/study calculations). Not part of the app package.
// Run with: StudyOS/Tests/run-logic-tests.sh

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL [line \(line)]: \(message)")
    }
}

func near(_ a: Double?, _ b: Double, tolerance: Double = 0.0001) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
calendar.firstWeekday = 1
calendar.locale = Locale(identifier: "en_US")

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// MARK: - Grade calculation

do {
    // Points-based course (no categories)
    let course = Course(semesterID: nil, name: "Statics")
    let items = [
        GradedItem(id: UUID(), title: "A", courseID: course.id, categoryID: nil, grade: Grade(pointsEarned: 88, pointsPossible: 100), date: Date()),
        GradedItem(id: UUID(), title: "B", courseID: course.id, categoryID: nil, grade: Grade(pointsEarned: 37, pointsPossible: 40), date: Date()),
    ]
    let r = GradeCalculator.calculate(course: course, items: items)
    check(r.method == .totalPoints, "points method")
    check(near(r.percent, 125.0 / 140.0 * 100), "points percent = 89.2857, got \(String(describing: r.percent))")
    check(r.pointsEarned == 125 && r.pointsPossible == 140, "points totals")

    let empty = GradeCalculator.calculate(course: course, items: [])
    check(empty.method == .none && empty.percent == nil, "no grades -> nil")
}

do {
    // Weighted course, matching the spec example weights.
    let hw = GradeCategory(name: "Homework", weight: 15)
    let labs = GradeCategory(name: "Labs", weight: 20)
    let quizzes = GradeCategory(name: "Quizzes", weight: 15)
    let exams = GradeCategory(name: "Exams", weight: 30)
    let final = GradeCategory(name: "Final", weight: 20)
    let course = Course(semesterID: nil, name: "Physics II", categories: [hw, labs, quizzes, exams, final])
    func item(_ cat: GradeCategory?, _ e: Double, _ p: Double) -> GradedItem {
        GradedItem(id: UUID(), title: "x", courseID: course.id, categoryID: cat?.id, grade: Grade(pointsEarned: e, pointsPossible: p), date: Date())
    }
    // HW: 37/40 = 92.5%, Labs: 46/50 = 92%, Quizzes: 8.5/10 = 85%, Exams: 92/100 = 92%, Final: none.
    let items = [item(hw, 19, 20), item(hw, 18, 20), item(labs, 46, 50), item(quizzes, 8.5, 10), item(exams, 92, 100)]
    let r = GradeCalculator.calculate(course: course, items: items)
    // (92.5*15 + 92*20 + 85*15 + 92*30) / 80 = (1387.5 + 1840 + 1275 + 2760) / 80 = 7262.5 / 80 = 90.78125
    check(r.method == .weighted, "weighted method")
    check(near(r.percent, 90.78125), "weighted percent = 90.78125, got \(String(describing: r.percent))")
    check(r.gradedWeight == 80 && r.totalWeight == 100, "graded weight 80 of 100")
    check(near(r.categories.first { $0.category.id == hw.id }?.percent, 92.5), "homework category avg")
    check(r.categories.first { $0.category.id == final.id }?.percent == nil, "final ungraded")

    // Uncategorized grades are excluded and counted.
    let withLoose = GradeCalculator.calculate(course: course, items: items + [item(nil, 0, 100)])
    check(near(withLoose.percent, 90.78125), "uncategorized excluded from weighted grade")
    check(withLoose.uncategorizedCount == 1, "uncategorized counted")

    // Item referring to a deleted category is treated as uncategorized.
    let ghost = GradedItem(id: UUID(), title: "g", courseID: course.id, categoryID: UUID(), grade: Grade(pointsEarned: 0, pointsPossible: 10), date: Date())
    check(GradeCalculator.calculate(course: course, items: items + [ghost]).uncategorizedCount == 1, "unknown category -> uncategorized")

    // Extra credit above 100% is allowed.
    let ec = GradeCalculator.calculate(course: Course(semesterID: nil, name: "EC"), items: [item(nil, 105, 100)])
    check(near(ec.percent, 105), "extra credit over 100%")
}

do {
    // Categories whose weights are all zero fall back to points.
    let course = Course(semesterID: nil, name: "Zero", categories: [GradeCategory(name: "A", weight: 0)])
    let r = GradeCalculator.calculate(course: course, items: [
        GradedItem(id: UUID(), title: "x", courseID: course.id, categoryID: course.categories[0].id, grade: Grade(pointsEarned: 9, pointsPossible: 10), date: Date())
    ])
    check(r.method == .totalPoints && near(r.percent, 90), "zero weights -> points fallback")
}

// MARK: - Grading scale

do {
    let s = GradingScale.standard
    check(s.letter(forPercent: 93) == "A", "93 -> A")
    check(s.letter(forPercent: 92.99) == "A-", "92.99 -> A-")
    check(s.letter(forPercent: 87.4) == "B+", "87.4 -> B+")
    check(s.letter(forPercent: 59.9) == "F", "59.9 -> F")
    check(s.letter(forPercent: -5) == "F", "negative -> F")
    check(s.letter(forPercent: 110) == "A", "110 -> A")
    check(s.gradePoints(forLetter: "b-") == 2.7, "b- -> 2.7")
    check(s.gradePoints(forLetter: "Z") == nil, "unknown letter")
}

// MARK: - GPA

do {
    let scale = GradingScale.standard
    var a = Course(semesterID: nil, name: "A", credits: 4)
    a.finalLetterGrade = "A"
    var b = Course(semesterID: nil, name: "B", credits: 3)
    b.finalLetterGrade = "B+"
    let c = Course(semesterID: nil, name: "C", credits: 3) // in progress
    var nonGPA = Course(semesterID: nil, name: "PF", credits: 1)
    nonGPA.countsTowardGPA = false
    nonGPA.finalLetterGrade = "F"

    let actual = [a, b, c, nonGPA].compactMap {
        GPACalculator.contribution(for: $0, effectivePercent: $0.id == c.id ? 81 : nil, scale: scale, allowProjection: false)
    }
    // (4*4.0 + 3*3.3) / 7 = 25.9 / 7 = 3.7
    check(near(GPACalculator.gpa(actual), 3.7), "actual GPA 3.7, got \(String(describing: GPACalculator.gpa(actual)))")

    let projected = [a, b, c].compactMap {
        GPACalculator.contribution(for: $0, effectivePercent: $0.id == c.id ? 81 : nil, scale: scale, allowProjection: true)
    }
    // + 3 * 2.7 -> (25.9 + 8.1) / 10 = 3.4
    check(near(GPACalculator.gpa(projected), 3.4), "projected GPA 3.4")
    let summary = GPACalculator.summary(projected)
    check(summary.includesProjection && summary.credits == 10, "projection flagged")

    // Prior credits: 30 credits @ 3.5 + 7 credits @ 3.7 = (105 + 25.9) / 37
    let withPrior = GPACalculator.summary(actual, priorCredits: 30, priorGPA: 3.5)
    check(near(withPrior.gpa, 130.9 / 37), "prior credits combined")
    check(!withPrior.includesProjection, "actual not flagged")
    check(GPACalculator.gpa([]) == nil, "empty GPA nil")
}

// MARK: - Database queries

do {
    var db = AcademicDatabase()
    let sem = Semester(name: "Fall 2026", startDate: date(2026, 8, 25), endDate: date(2026, 12, 18, 23, 59))
    let old = Semester(name: "Spring 2026", startDate: date(2026, 1, 20), endDate: date(2026, 5, 15), isArchived: true)
    db.semesters = [sem, old]
    db.student.currentSemesterID = sem.id
    // Monday Oct 5 2026
    let monday = date(2026, 10, 5, 8, 0)
    var physics = Course(semesterID: sem.id, name: "Physics II", room: "1410",
                         meetings: [MeetingTime(weekday: 2, startMinute: 600, endMinute: 650),
                                    MeetingTime(weekday: 2, startMinute: 540, endMinute: 590, location: "Lab")])
    physics.manualGrade = nil
    let oldCourse = Course(semesterID: old.id, name: "Old", meetings: [MeetingTime(weekday: 2, startMinute: 600, endMinute: 650)])
    db.courses = [physics, oldCourse]

    let classes = db.classes(on: monday, calendar: calendar)
    check(classes.count == 2, "two physics meetings Monday (old semester excluded)")
    check(classes.first?.meeting.startMinute == 540 && classes.first?.location == "Lab", "sorted by start; location override")
    check(classes.last?.location == "1410", "falls back to course room")
    check(db.classes(on: date(2026, 10, 6), calendar: calendar).isEmpty, "no classes Tuesday")
    check(db.classes(on: date(2027, 1, 4), calendar: calendar).isEmpty, "no classes after semester ends")

    db.assignments = [
        Assignment(courseID: physics.id, title: "Today late", dueDate: date(2026, 10, 5, 17, 0)),
        Assignment(courseID: physics.id, title: "Today early", dueDate: date(2026, 10, 5, 9, 0), status: .completed),
        Assignment(courseID: physics.id, title: "Tomorrow", dueDate: date(2026, 10, 6, 9, 0)),
        Assignment(courseID: physics.id, title: "Next week", dueDate: date(2026, 10, 12, 9, 0)),
        Assignment(courseID: physics.id, title: "Overdue", dueDate: date(2026, 10, 1, 9, 0)),
        Assignment(courseID: physics.id, title: "Done past", dueDate: date(2026, 9, 30, 9, 0), status: .completed),
        Assignment(courseID: oldCourse.id, title: "Archived", dueDate: date(2026, 10, 5, 12, 0)),
    ]
    let today = db.assignmentsDue(on: monday, calendar: calendar)
    check(today.map(\.title) == ["Today early", "Today late"], "today's assignments sorted, archived excluded: \(today.map(\.title))")
    let soon = db.assignmentsDueSoon(after: monday, days: 3, calendar: calendar)
    check(soon.map(\.title) == ["Tomorrow"], "due soon within 3 days: \(soon.map(\.title))")
    check(db.overdueAssignments(now: monday, calendar: calendar).map(\.title) == ["Overdue"], "overdue")

    // Completion: due by Monday 08:00 or completed -> Overdue (no), Done past (yes), Today early (yes, completed)
    let rate = db.completionRate(now: monday, calendar: calendar)
    check(rate.completed == 2 && rate.total == 3, "completion 2/3, got \(rate)")

    // Date-only assignment is due at the end of the day.
    let dateOnly = Assignment(courseID: nil, title: "d", dueDate: date(2026, 10, 5, 0, 0), hasDueTime: false)
    check(!dateOnly.isOverdue(now: date(2026, 10, 5, 22, 0), calendar: calendar), "date-only not overdue same evening")
    check(dateOnly.isOverdue(now: date(2026, 10, 6, 0, 1), calendar: calendar), "date-only overdue next day")

    db.exams = [
        Exam(courseID: physics.id, title: "Exam 2", date: date(2026, 10, 16, 18, 0)),
        Exam(courseID: physics.id, title: "Exam 1", date: date(2026, 9, 20, 18, 0)),
        Exam(courseID: oldCourse.id, title: "Old exam", date: date(2026, 10, 20, 18, 0)),
    ]
    check(db.upcomingExams(from: monday).map(\.title) == ["Exam 2"], "upcoming exams exclude past and archived")

    // Exam grades count toward the course grade.
    db.exams[0].grade = Grade(pointsEarned: 45, pointsPossible: 50)
    db.assignments[0].grade = Grade(pointsEarned: 15, pointsPossible: 20)
    let pg = db.gradeResult(for: physics)
    check(near(pg.percent, 60.0 / 70.0 * 100), "assignment + exam grades combined")
    check(db.effectiveGrade(for: physics)?.source == .calculated, "calculated source")
    var manual = physics
    manual.manualGrade = 91.4
    check(db.effectiveGrade(for: manual) == EffectiveGrade(percent: 91.4, source: .manual), "manual grade wins")
}

// MARK: - Study timer & statistics

do {
    let start = date(2026, 10, 5, 19, 0)
    var timer = ActiveStudyTimer(courseID: nil, topic: "Electric Fields", startedAt: start)
    check(near(timer.elapsed(at: start.addingTimeInterval(600)), 600), "10 minutes running")
    timer.pause(at: start.addingTimeInterval(600))
    check(timer.isPaused, "paused")
    check(near(timer.elapsed(at: start.addingTimeInterval(3600)), 600), "paused time not counted")
    timer.pause(at: start.addingTimeInterval(3700)) // double pause is a no-op
    timer.resume(at: start.addingTimeInterval(1200))
    timer.resume(at: start.addingTimeInterval(1300)) // double resume is a no-op
    check(near(timer.elapsed(at: start.addingTimeInterval(1500)), 900), "resumed: 600 + 300")

    let c1 = UUID(), c2 = UUID()
    let sessions = [
        StudySession(courseID: c1, topic: "", startedAt: date(2026, 10, 5, 19, 0), endedAt: date(2026, 10, 5, 19, 47), durationSeconds: 47 * 60),
        StudySession(courseID: c1, topic: "", startedAt: date(2026, 10, 6, 19, 0), endedAt: date(2026, 10, 6, 20, 0), durationSeconds: 3600),
        StudySession(courseID: c2, topic: "", startedAt: date(2026, 10, 7, 19, 0), endedAt: date(2026, 10, 7, 19, 30), durationSeconds: 1800),
        StudySession(courseID: c2, topic: "", startedAt: date(2026, 9, 28, 19, 0), endedAt: date(2026, 9, 28, 19, 30), durationSeconds: 1800),
    ]
    let week = StudyStatistics.week(containing: date(2026, 10, 7), calendar: calendar)
    check(near(StudyStatistics.totalSeconds(sessions, in: week), 47 * 60 + 3600 + 1800), "week total excludes last week")
    let byCourse = StudyStatistics.byCourse(sessions, in: week)
    check(byCourse.first?.courseID == c1 && near(byCourse.first?.seconds, 107 * 60), "by course sorted desc")
    check(DurationFormat.short(4 * 3600 + 32 * 60 + 59) == "4h 32m", "duration format")
    check(DurationFormat.short(47 * 60) == "47m", "minutes only")
    check(DurationFormat.clock(3727) == "1:02:07", "clock format")
    check(DurationFormat.clock(127) == "02:07", "short clock format")
    check(PercentFormat.string(91.44) == "91.4%", "percent format")
    check(PercentFormat.points(12.5) == "12.5" && PercentFormat.points(12) == "12", "points format")
}

// MARK: - Persistence

do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyos-test-\(UUID().uuidString)")
    let store = DatabaseFileStore(directory: dir)
    let (fresh, outcome) = store.load()
    check(outcome == .empty && fresh == AcademicDatabase(), "first launch empty")

    var db = SampleData.make(now: date(2026, 10, 5, 8, 0), calendar: calendar)
    db.activeTimer = ActiveStudyTimer(courseID: db.courses[0].id, topic: "Fields", startedAt: date(2026, 10, 5, 7, 0))
    try! store.save(db)
    let (loaded, o2) = store.load()
    check(o2 == .loaded, "loaded")
    // Dates are stored to the millisecond, so compare a re-saved copy for exact equality
    // and spot-check that nothing was dropped.
    check(loaded.courses.map(\.id) == db.courses.map(\.id) && loaded.courses.map(\.categories) == db.courses.map(\.categories), "courses preserved")
    check(loaded.assignments.map(\.grade) == db.assignments.map(\.grade), "grades preserved")
    check(loaded.exams.map(\.topics) == db.exams.map(\.topics) && loaded.studySessions == db.studySessions, "exams & sessions preserved")
    check(loaded.activeTimer == db.activeTimer && loaded.student == db.student, "timer & student preserved")
    check(abs(loaded.courses[0].createdAt.timeIntervalSince(db.courses[0].createdAt)) < 0.001, "dates kept to the millisecond")
    try! store.save(loaded)
    check(store.load().0 == loaded, "save/load is stable")

    // Second save creates a backup.
    db.student.name = "Changed"
    try! store.save(db)
    check(FileManager.default.fileExists(atPath: store.backupURL.path), "backup created")

    // Corrupt main file: recovered from backup, corrupt file kept aside.
    try! Data("{ not json".utf8).write(to: store.databaseURL)
    let (recovered, o3) = store.load()
    if case .recoveredFromBackup(let name) = o3 {
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), "corrupt file quarantined")
    } else {
        check(false, "expected recovery from backup, got \(o3)")
    }
    check(recovered.courses.count == 3, "backup data intact")

    // Older/smaller files still load (missing fields take defaults).
    let minimal = """
    {"courses":[{"id":"\(UUID().uuidString)","name":"Physics II"}],
     "assignments":[{"id":"\(UUID().uuidString)","title":"PS 1","dueDate":"2026-10-05T12:00:00Z"}]}
    """
    let decoded = try! store.decodeImported(Data(minimal.utf8))
    check(decoded.courses.first?.credits == 3 && decoded.courses.first?.countsTowardGPA == true, "course defaults")
    check(decoded.assignments.first?.status == .notStarted && decoded.assignments.first?.priority == .normal, "assignment defaults")
    check(decoded.student.gradingScale == .standard, "student default")

    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Sample data sanity

do {
    let db = SampleData.make(now: date(2026, 10, 5, 8, 0), calendar: calendar)
    let physics = db.courses[0]
    let pct = db.gradeResult(for: physics).percent
    check(pct != nil && pct! > 85 && pct! < 95, "sample physics grade plausible: \(String(describing: pct))")
    check(!db.upcomingExams(from: date(2026, 10, 5, 8, 0)).isEmpty, "sample has upcoming exams")
    check(db.cumulativeGPA.gpa != nil && !db.cumulativeGPA.includesProjection, "sample cumulative GPA actual")
    check(db.semesterGPA(db.student.currentSemesterID).includesProjection, "sample semester GPA projected")
}

// MARK: - Date text

do {
    let now = date(2026, 10, 3, 22, 0)
    check(DateText.relativeDay(date(2026, 10, 3, 8, 0), now: now, calendar: calendar) == "Today", "today")
    check(DateText.relativeDay(date(2026, 10, 4, 1, 0), now: now, calendar: calendar) == "Tomorrow", "tomorrow across midnight")
    check(DateText.relativeDay(date(2026, 10, 16, 18, 0), now: now, calendar: calendar) == "in 13 days", "in 13 days")
    check(DateText.relativeDay(date(2026, 9, 30), now: now, calendar: calendar) == "3 days ago", "3 days ago")
    check(DateText.weekdayName(2, short: false, calendar: calendar) == "Monday", "weekday name")
    var mondayFirst = calendar
    mondayFirst.firstWeekday = 2
    check(DateText.orderedWeekdays(calendar: mondayFirst) == [2, 3, 4, 5, 6, 7, 1], "monday-first order")
    check(DateText.orderedWeekdays(calendar: calendar) == [1, 2, 3, 4, 5, 6, 7], "sunday-first order")

    let fall = SemesterSuggestion.suggested(for: date(2026, 10, 3), calendar: calendar)
    check(fall.name == "Fall 2026" && fall.contains(date(2026, 12, 31, 23, 0)) && !fall.contains(date(2027, 1, 1, 0, 0)), "fall suggestion")
    check(SemesterSuggestion.suggested(for: date(2027, 2, 1), calendar: calendar).name == "Spring 2027", "spring suggestion")
}

print("\(checks - failures)/\(checks) checks passed")
if failures > 0 { exit(1) }
