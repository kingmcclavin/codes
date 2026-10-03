import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation

    @State private var courseID: UUID?
    @State private var topic = ""
    @State private var finishing = false
    @State private var confirmingDiscard = false

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let timer = store.db.activeTimer {
                    RunningTimerCard(timer: timer, finish: {
                        store.pauseTimer()
                        finishing = true
                    }, discard: { confirmingDiscard = true })
                } else {
                    setupCard
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    WeekSummaryCard()
                    RecentSessionsCard()
                }
            }
            .padding(20)
            .animation(.snappy, value: store.db.activeTimer == nil)
        }
        .background(Color.appBackground)
        .navigationTitle("Study")
        .onAppear(perform: applyPendingCourse)
        .onChange(of: navigation.pendingStudyCourseID) { _, _ in applyPendingCourse() }
        .sheet(isPresented: $finishing) {
            FinishSessionSheet()
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Session", role: .destructive) { store.discardTimer() }
        } message: {
            Text("The time won't be recorded.")
        }
    }

    private func applyPendingCourse() {
        if let pending = navigation.pendingStudyCourseID {
            courseID = pending
            navigation.pendingStudyCourseID = nil
        }
    }

    private var setupCard: some View {
        Card("New Study Session", systemImage: "timer") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Course").foregroundStyle(.secondary)
                    Spacer()
                    CoursePicker(title: "Course", courses: store.db.currentCourses, selection: $courseID, noneTitle: "No Course")
                        .labelsHidden()
                }
                HStack {
                    TextField("Topic (optional)", text: $topic, prompt: Text("Electric Fields"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(start)
                    let suggestions = recentTopics
                    if !suggestions.isEmpty {
                        Menu {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { topic = suggestion }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("Recent topics")
                    }
                }
                Button(action: start) {
                    Label("Start Studying", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: 640)
    }

    /// Recent distinct topics for the selected course.
    private var recentTopics: [String] {
        var seen = Set<String>()
        return store.db.studySessions
            .filter { courseID == nil || $0.courseID == courseID }
            .sorted { $0.startedAt > $1.startedAt }
            .map(\.topic)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    private func start() {
        store.startTimer(courseID: courseID, topic: topic)
        topic = ""
    }
}

private struct RunningTimerCard: View {
    @EnvironmentObject private var store: AcademicStore
    let timer: ActiveStudyTimer
    let finish: () -> Void
    let discard: () -> Void

    var body: some View {
        let course = store.db.course(withID: timer.courseID)
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                CourseBadge(course: course, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(course?.name ?? "General Study")
                        .font(.headline)
                    if !timer.topic.isEmpty {
                        Text(timer.topic)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if timer.isPaused {
                    SourceTag(text: "Paused")
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(DurationFormat.clock(timer.elapsed(at: context.date)))
                    .font(.system(size: 84, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Elapsed time \(DurationFormat.short(timer.elapsed(at: context.date)))")
            }

            Text("Started \(timer.startedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if timer.isPaused {
                    Button {
                        store.resumeTimer()
                    } label: {
                        Label("Resume", systemImage: "play.fill").frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                } else {
                    Button {
                        store.pauseTimer()
                    } label: {
                        Label("Pause", systemImage: "pause.fill").frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [])
                }
                Button(action: finish) {
                    Label("Finish", systemImage: "checkmark").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Menu {
                    Button("Discard Session", systemImage: "trash", role: .destructive, action: discard)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
                .accessibilityLabel("More options")
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 640)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FinishSessionSheet: View {
    @EnvironmentObject private var store: AcademicStore
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var courseID: UUID?
    @State private var topic = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if let timer = store.db.activeTimer {
                    Section {
                        LabeledContent("Duration", value: DurationFormat.short(timer.elapsed(at: Date())))
                        CoursePicker(title: "Course", courses: store.db.currentCourses, selection: $courseID, noneTitle: "No Course")
                        TextField("Topic", text: $topic)
                    }
                    Section("Notes") {
                        TextField("What did you cover? Anything to revisit?", text: $notes, axis: .vertical)
                            .lineLimit(4...12)
                    }
                }
            }
            .navigationTitle("Finish Session")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded, let timer = store.db.activeTimer else { return }
                courseID = timer.courseID
                topic = timer.topic
                loaded = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Studying") {
                        store.resumeTimer()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateTimer(courseID: courseID, topic: topic.trimmingCharacters(in: .whitespaces))
                        store.finishTimer(notes: notes)
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct WeekSummaryCard: View {
    @EnvironmentObject private var store: AcademicStore

    var body: some View {
        let now = Date()
        let week = StudyStatistics.week(containing: now)
        let total = StudyStatistics.totalSeconds(store.db.studySessions, in: week)
        let today = StudyStatistics.totalSeconds(store.db.studySessions, in: StudyStatistics.day(containing: now))
        let byCourse = StudyStatistics.byCourse(store.db.studySessions, in: week)
        let maxSeconds = byCourse.first?.seconds ?? 1

        Card("This Week", systemImage: "chart.bar") {
            HStack(spacing: 24) {
                StatTile(title: "This Week", value: DurationFormat.short(total))
                StatTile(title: "Today", value: DurationFormat.short(today))
            }
            if byCourse.isEmpty {
                CardEmptyText("No study sessions this week yet.")
            } else {
                VStack(spacing: 10) {
                    ForEach(byCourse) { entry in
                        let course = store.db.course(withID: entry.courseID)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(course?.name ?? "General")
                                Spacer()
                                Text(DurationFormat.short(entry.seconds))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(course?.color.color ?? .gray)
                                    .frame(width: max(6, proxy.size.width * entry.seconds / maxSeconds))
                            }
                            .frame(height: 6)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct RecentSessionsCard: View {
    @EnvironmentObject private var store: AcademicStore
    @State private var showingAll = false

    var body: some View {
        let sessions = store.db.studySessions.sorted { $0.startedAt > $1.startedAt }
        Card("Recent Sessions", systemImage: "clock.arrow.circlepath") {
            if sessions.isEmpty {
                CardEmptyText("Finished sessions appear here.")
            } else {
                ForEach(sessions.prefix(showingAll ? 50 : 8)) { session in
                    SessionRow(session: session)
                    if session.id != sessions.prefix(showingAll ? 50 : 8).last?.id { Divider() }
                }
                if sessions.count > 8 {
                    Button(showingAll ? "Show Less" : "Show More") { showingAll.toggle() }
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct SessionRow: View {
    @EnvironmentObject private var store: AcademicStore
    let session: StudySession
    @State private var confirmingDelete = false

    var body: some View {
        let course = store.db.course(withID: session.courseID)
        HStack(alignment: .top, spacing: 10) {
            CourseBadge(course: course, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(course?.name ?? "General Study")
                    .font(.subheadline.weight(.medium))
                if !session.topic.isEmpty {
                    Text(session.topic).font(.caption).foregroundStyle(.secondary)
                }
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormat.short(session.durationSeconds))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Delete Session", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete this study session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteStudySession(session.id) }
        }
    }
}
