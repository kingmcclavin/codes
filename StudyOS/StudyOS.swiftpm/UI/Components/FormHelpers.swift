import SwiftUI

extension Binding where Value == Int {
    /// Presents "minutes after midnight" as a Date for time pickers.
    func asTimeOfDay(calendar: Calendar = .current) -> Binding<Date> {
        Binding<Date>(
            get: {
                calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(wrappedValue * 60))
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// A course picker that includes "None".
struct CoursePicker: View {
    let title: String
    let courses: [Course]
    @Binding var selection: UUID?
    var noneTitle = "None"

    var body: some View {
        Picker(title, selection: $selection) {
            Text(noneTitle).tag(UUID?.none)
            ForEach(courses) { course in
                Text(course.code.isEmpty ? course.name : "\(course.code) · \(course.name)")
                    .tag(UUID?.some(course.id))
            }
        }
    }
}

/// Picks a grade category from a course; hidden when the course has none.
struct CategoryPicker: View {
    let course: Course?
    @Binding var selection: UUID?

    var body: some View {
        if let course, !course.categories.isEmpty {
            Picker("Grade Category", selection: $selection) {
                Text("None").tag(UUID?.none)
                ForEach(course.categories) { category in
                    Text("\(category.name) (\(PercentFormat.points(category.weight))%)")
                        .tag(UUID?.some(category.id))
                }
            }
        }
    }
}

/// Earned / possible entry for a score.
struct ScoreFields: View {
    @Binding var earned: Double?
    @Binding var possible: Double?

    var body: some View {
        HStack {
            TextField("Earned", value: $earned, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text("/")
                .foregroundStyle(.secondary)
            TextField("Possible", value: $possible, format: .number)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
            Spacer()
            if let earned, let possible, possible > 0 {
                Text(PercentFormat.string(earned / possible * 100))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
