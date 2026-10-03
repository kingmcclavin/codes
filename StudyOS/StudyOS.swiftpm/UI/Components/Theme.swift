import SwiftUI
import UIKit

extension Color {
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

extension CourseColor {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .teal: return .teal
        case .green: return .green
        case .olive: return Color(red: 0.47, green: 0.55, blue: 0.27)
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .graphite: return .gray
        }
    }
}

extension Priority {
    var tint: Color {
        switch self {
        case .low: return .secondary
        case .normal: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

/// A titled card used throughout StudyOS.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                accessory()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// Small rounded icon in a course's color.
struct CourseBadge: View {
    let course: Course?
    var size: CGFloat = 28

    var body: some View {
        let tint = course?.color.color ?? .gray
        Image(systemName: course?.icon ?? "tray")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A large number with a caption, used in overview cards.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if caption != nil || tag != nil {
                HStack(spacing: 6) {
                    if let tag { SourceTag(text: tag) }
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Labels numbers as ACTUAL / PROJECTED / MANUAL so they're never confused.
struct SourceTag: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

/// Text shown inside a card when it has nothing to list.
struct CardEmptyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}
