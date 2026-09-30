import SwiftUI

/// Colors offered for documents, folders and the app accent.
enum LibraryPalette {
    static let colors: [RGBAColor] = [
        RGBAColor(hex: 0x1F6FEB), // blue
        RGBAColor(hex: 0x5E5CE6), // indigo
        RGBAColor(hex: 0x9B51E0), // purple
        RGBAColor(hex: 0xE84393), // pink
        RGBAColor(hex: 0xE5484D), // red
        RGBAColor(hex: 0xF76B15), // orange
        RGBAColor(hex: 0xD4A017), // gold
        RGBAColor(hex: 0x30A46C), // green
        RGBAColor(hex: 0x12A594), // teal
        RGBAColor(hex: 0x0891B2), // cyan
        RGBAColor(hex: 0x8D6E63), // brown
        RGBAColor(hex: 0x5F6B7A), // graphite
    ]

    /// SF Symbols offered as document / folder icons, grouped loosely by subject.
    static let icons: [String] = [
        "doc.text", "book.closed", "books.vertical", "graduationcap", "pencil.and.ruler", "ruler",
        "function", "sum", "x.squareroot", "percent", "chart.xyaxis.line", "chart.bar",
        "atom", "flask", "testtube.2", "leaf", "brain", "heart",
        "cpu", "gearshape", "hammer", "wrench.and.screwdriver", "bolt", "lightbulb",
        "globe.americas", "building.columns", "briefcase", "dollarsign.circle", "person.2", "calendar",
        "music.note", "paintpalette", "camera", "star", "flag", "bookmark",
        "house", "airplane", "car", "tag", "folder", "archivebox",
    ]
}

/// Notebook-style thumbnail: a colored cover with an icon.
struct DocumentTile: View {
    var color: RGBAColor?
    var icon: String?
    var width: CGFloat = 38

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                .fill(color.map { AnyShapeStyle($0.color.gradient) } ?? AnyShapeStyle(.tint))
            // Binding strip, like a notebook spine.
            Rectangle()
                .fill(.black.opacity(0.14))
                .frame(width: width * 0.14)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.14, bottomLeadingRadius: width * 0.14))
            Image(systemName: icon ?? "doc.text")
                .font(.system(size: width * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.leading, width * 0.12)
        }
        .frame(width: width, height: width * 1.28)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }
}

/// Folder thumbnail: a colored folder with an optional icon inside.
struct FolderTile: View {
    var color: RGBAColor?
    var icon: String?
    var width: CGFloat = 38

    var body: some View {
        ZStack {
            Image(systemName: "folder.fill")
                .font(.system(size: width * 0.9))
                .foregroundStyle(color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.tint))
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: width * 0.34, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: width * 0.06)
            }
        }
        .frame(width: width, height: width * 1.1)
    }
}

/// Color + icon picker for a document or folder.
struct CustomizeItemView: View {
    let item: LibraryItem
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var color: RGBAColor?
    @State private var icon: String?
    @State private var loaded = false

    private var isFolder: Bool { if case .folder = item { return true }; return false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        if isFolder {
                            FolderTile(color: color, icon: icon, width: 90)
                        } else {
                            DocumentTile(color: color, icon: icon, width: 80)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Color") {
                    ColorSwatchGrid(selection: $color, allowsDefault: true)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        if isFolder {
                            iconCell(nil, symbol: "circle.slash")
                        }
                        ForEach(LibraryPalette.icons, id: \.self) { name in
                            iconCell(name, symbol: name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setAppearance(item, color: color, icon: icon)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let current = store.appearance(of: item)
                color = current.color
                icon = current.icon
            }
        }
    }

    private func accent(_ opacity: Double = 1) -> AnyShapeStyle {
        if let color { return AnyShapeStyle(color.color.opacity(opacity)) }
        return AnyShapeStyle(.tint.opacity(opacity))
    }

    private func iconCell(_ name: String?, symbol: String) -> some View {
        let selected = icon == name || (name == "doc.text" && icon == nil && !isFolder)
        return Button {
            icon = name
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? accent(0.2) : AnyShapeStyle(Color.secondary.opacity(0.08))))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? accent() : AnyShapeStyle(Color.clear), lineWidth: 2))
                .foregroundStyle(selected ? accent() : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name ?? "No Icon")
    }
}

/// Grid of palette colors plus a custom color picker.
struct ColorSwatchGrid: View {
    @Binding var selection: RGBAColor?
    /// Shows a "Default" swatch that sets the selection to nil.
    var allowsDefault = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
            if allowsDefault {
                swatch(nil)
            }
            ForEach(Array(LibraryPalette.colors.enumerated()), id: \.offset) { _, c in swatch(c) }
            ColorPicker("Custom", selection: Binding(get: { (selection ?? LibraryPalette.colors[0]).color },
                                                     set: { selection = RGBAColor($0).withAlpha(1) }),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36, height: 36)
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ c: RGBAColor?) -> some View {
        let selected: Bool = {
            switch (c, selection) {
            case (nil, nil): return true
            case let (a?, b?): return a.isClose(to: b)
            default: return false
            }
        }()
        return Button {
            selection = c
        } label: {
            ZStack {
                Circle().fill(c.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.tint))
                if c == nil {
                    Text("A").font(.caption.bold()).foregroundStyle(.white)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(selected ? Color.primary.opacity(0.5) : .clear, lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c == nil ? "Default" : "Color")
    }
}

/// App-wide appearance settings.
struct AppearanceSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorSwatchGrid(selection: $preferences.accentColor)
                    if preferences.accentColor != nil {
                        Button("Use Default Blue", systemImage: "arrow.uturn.backward") { preferences.accentColor = nil }
                    }
                } header: {
                    Text("Accent Color")
                } footer: {
                    Text("Used for buttons, selected tools, selections on the page and default document colors.")
                }

                Section("Preview") {
                    HStack(spacing: 18) {
                        DocumentTile(width: 44)
                        FolderTile(width: 44)
                        Button("Button") {}
                            .buttonStyle(.borderedProminent)
                        Toggle("", isOn: .constant(true)).labelsHidden()
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
