import Foundation

/// A realistic example semester, built relative to today, so the app can be
/// explored before entering real data. Only ever loaded when the user asks.
enum SampleData {
    static func make(now: Date = Date(), calendar: Calendar = .current) -> AcademicDatabase {
        var db = AcademicDatabase()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        let semester = Semester(name: "Fall 2026", startDate: day(-40, 0, 0), endDate: day(75, 23, 59))
        db.semesters = [semester]
        db.student.name = "Student"
        db.student.currentSemesterID = semester.id
        db.student.priorCredits = 30
        db.student.priorGPA = 3.52

        // Physics II
        let pHomework = GradeCategory(name: "Homework", weight: 15)
        let pLabs = GradeCategory(name: "Labs", weight: 20)
        let pQuizzes = GradeCategory(name: "Quizzes", weight: 15)
        let pExams = GradeCategory(name: "Exams", weight: 30)
        let pFinal = GradeCategory(name: "Final", weight: 20)
        let physics = Course(
            semesterID: semester.id, name: "Physics II", code: "PHYS 222", professor: "Professor Smith",
            credits: 4, room: "Physics 1410",
            meetings: [
                MeetingTime(weekday: 2, startMinute: 9 * 60, endMinute: 9 * 60 + 50),
                MeetingTime(weekday: 4, startMinute: 9 * 60, endMinute: 9 * 60 + 50),
                MeetingTime(weekday: 6, startMinute: 9 * 60, endMinute: 9 * 60 + 50),
                MeetingTime(weekday: 5, startMinute: 14 * 60, endMinute: 16 * 60 + 50, location: "Physics Lab 2208", kind: "Lab"),
            ],
            categories: [pHomework, pLabs, pQuizzes, pExams, pFinal],
            targetGrade: 90, color: .indigo, icon: "atom"
        )

        // Calculus III
        let cHomework = GradeCategory(name: "Homework", weight: 20)
        let cQuizzes = GradeCategory(name: "Quizzes", weight: 20)
        let cExams = GradeCategory(name: "Midterms", weight: 35)
        let cFinal = GradeCategory(name: "Final", weight: 25)
        let calculus = Course(
            semesterID: semester.id, name: "Calculus III", code: "MATH 241", professor: "Dr. Alvarez",
            credits: 4, room: "Math 0103",
            meetings: [
                MeetingTime(weekday: 3, startMinute: 11 * 60, endMinute: 12 * 60 + 15),
                MeetingTime(weekday: 5, startMinute: 11 * 60, endMinute: 12 * 60 + 15),
            ],
            categories: [cHomework, cQuizzes, cExams, cFinal],
            targetGrade: 87, color: .teal, icon: "function"
        )

        // Engineering (points-based, no categories)
        let engineering = Course(
            semesterID: semester.id, name: "Statics", code: "ENES 102", professor: "Dr. Chen",
            credits: 3, room: "Engineering 1202",
            meetings: [
                MeetingTime(weekday: 2, startMinute: 13 * 60, endMinute: 14 * 60 + 15),
                MeetingTime(weekday: 4, startMinute: 13 * 60, endMinute: 14 * 60 + 15),
            ],
            targetGrade: 85, color: .orange, icon: "gearshape.2"
        )
        db.courses = [physics, calculus, engineering]

        func graded(_ earned: Double, _ possible: Double, _ offset: Int) -> Grade {
            Grade(pointsEarned: earned, pointsPossible: possible, recordedAt: day(offset, 12, 0))
        }

        db.assignments = [
            // Physics
            Assignment(courseID: physics.id, title: "Problem Set 3", type: .homework, dueDate: day(-21), status: .completed,
                       categoryID: pHomework.id, pointsPossible: 20, grade: graded(19, 20, -18)),
            Assignment(courseID: physics.id, title: "Problem Set 4", type: .homework, dueDate: day(-14), status: .completed,
                       categoryID: pHomework.id, pointsPossible: 20, grade: graded(18, 20, -11)),
            Assignment(courseID: physics.id, title: "Lab 3: Electric Field Mapping", type: .lab, dueDate: day(-10), status: .completed,
                       categoryID: pLabs.id, pointsPossible: 50, grade: graded(46, 50, -6)),
            Assignment(courseID: physics.id, title: "Quiz 2", type: .quiz, dueDate: day(-8, 9, 0), status: .completed,
                       categoryID: pQuizzes.id, pointsPossible: 10, grade: graded(8.5, 10, -7)),
            Assignment(courseID: physics.id, title: "Problem Set 5", type: .homework, dueDate: day(0, 17, 0), priority: .high,
                       status: .inProgress, categoryID: pHomework.id, pointsPossible: 20, estimatedMinutes: 120),
            Assignment(courseID: physics.id, title: "Lab 4: Capacitors", type: .lab, dueDate: day(2, 14, 0), priority: .normal,
                       categoryID: pLabs.id, pointsPossible: 50, estimatedMinutes: 90),
            // Calculus
            Assignment(courseID: calculus.id, title: "Section 14.3 Homework", type: .homework, dueDate: day(-12), status: .completed,
                       categoryID: cHomework.id, pointsPossible: 30, grade: graded(28, 30, -10)),
            Assignment(courseID: calculus.id, title: "Quiz 3", type: .quiz, dueDate: day(-5, 11, 0), status: .completed,
                       categoryID: cQuizzes.id, pointsPossible: 20, grade: graded(17, 20, -4)),
            Assignment(courseID: calculus.id, title: "Section 15.1 Homework", type: .homework, dueDate: day(0), priority: .normal,
                       categoryID: cHomework.id, pointsPossible: 30, estimatedMinutes: 60),
            Assignment(courseID: calculus.id, title: "Section 15.2 Homework", type: .homework, dueDate: day(4),
                       categoryID: cHomework.id, pointsPossible: 30),
            // Engineering
            Assignment(courseID: engineering.id, title: "Truss Analysis Report", type: .project, dueDate: day(-9), status: .completed,
                       pointsPossible: 100, grade: graded(88, 100, -3)),
            Assignment(courseID: engineering.id, title: "Homework 6", type: .homework, dueDate: day(-2), status: .completed,
                       pointsPossible: 40, grade: graded(37, 40, -1)),
            Assignment(courseID: engineering.id, title: "Design Project Proposal", type: .paper, dueDate: day(6, 23, 59),
                       priority: .critical, pointsPossible: 50, estimatedMinutes: 180),
        ]

        db.exams = [
            Exam(courseID: physics.id, title: "Exam 1", date: day(-20, 18, 0), location: "Physics 1410",
                 topics: ["Coulomb's Law", "Electric Fields"], preparation: 1, categoryID: pExams.id,
                 grade: graded(92, 100, -15)),
            Exam(courseID: physics.id, title: "Exam 2", date: day(13, 18, 0), durationMinutes: 90, location: "Physics 1410",
                 topics: ["Electric Potential", "Capacitors", "Current"], preparation: 0.35, studyGoalMinutes: 600,
                 categoryID: pExams.id),
            Exam(courseID: calculus.id, title: "Midterm 2", date: day(9, 11, 0), durationMinutes: 75, location: "Math 0103",
                 topics: ["Double Integrals", "Polar Coordinates", "Triple Integrals"], preparation: 0.2,
                 studyGoalMinutes: 480, categoryID: cExams.id),
        ]

        func session(_ course: Course, _ topic: String, _ offset: Int, _ hour: Int, _ minutes: Int) -> StudySession {
            let start = day(offset, hour, 0)
            return StudySession(courseID: course.id, topic: topic, startedAt: start,
                                endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                durationSeconds: TimeInterval(minutes * 60))
        }
        db.studySessions = [
            session(physics, "Electric Fields", -1, 19, 47),
            session(physics, "Electric Potential", -2, 20, 65),
            session(calculus, "Double Integrals", -1, 16, 50),
            session(engineering, "Truss Method of Joints", -3, 15, 40),
            session(physics, "Coulomb's Law", -8, 19, 55),
            session(calculus, "Partial Derivatives", -9, 18, 45),
        ]
        return db
    }
}
