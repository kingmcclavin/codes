import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
        } detail: {
            NavigationStack {
                SectionView(section: navigation.section ?? .dashboard)
            }
            // A fresh navigation stack for each section.
            .id(navigation.section ?? .dashboard)
        }
        .alert("Data Recovered", isPresented: Binding(
            get: { store.startupMessage != nil },
            set: { if !$0 { store.startupMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.startupMessage ?? "")
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        List(selection: $navigation.section) {
            Section {
                ForEach(AppSection.planning) { row($0) }
            }
            Section("Learn") {
                ForEach(AppSection.learning) { row($0) }
            }
            Section {
                row(.more)
            }
        }
        .navigationTitle("StudyOS")
        .safeAreaInset(edge: .bottom) {
            if store.db.activeTimer != nil {
                ActiveTimerChip()
                    .padding()
            }
        }
    }

    private func row(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.symbol)
        }
    }
}

/// Keeps a running study timer visible from anywhere in the app.
private struct ActiveTimerChip: View {
    @EnvironmentObject private var store: AcademicStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        if let timer = store.db.activeTimer {
            Button {
                navigation.section = .study
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: timer.isPaused ? "pause.circle.fill" : "timer")
                        .font(.title3)
                        .foregroundStyle(timer.isPaused ? Color.secondary : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.db.course(withID: timer.courseID)?.name ?? "Studying")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(DurationFormat.clock(timer.elapsed(at: context.date)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Study timer running. Open Study.")
        }
    }
}

private struct SectionView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .dashboard: DashboardView()
        case .courses: CoursesView()
        case .assignments: AssignmentsView()
        case .calendar:
            ComingSoonView(section: .calendar, phase: 2,
                           description: "Month, week and day views of classes, assignments, exams and study sessions.")
        case .grades: GradesView()
        case .study: StudyView()
        case .materials:
            ComingSoonView(section: .materials, phase: 5,
                           description: "Import PDFs, images and documents, organized by course, topic and tag.")
        case .more: MoreView()
        }
    }
}

/// Honest placeholder for sections scheduled for a later build phase.
struct ComingSoonView: View {
    let section: AppSection
    let phase: Int
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text(description + "\nPlanned for phase \(phase) of StudyOS.")
        }
        .navigationTitle(section.title)
    }
}
