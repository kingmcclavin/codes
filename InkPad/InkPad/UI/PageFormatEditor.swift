import SwiftUI

enum BackgroundChoice: String, CaseIterable, Identifiable {
    case white, offWhite, darkGray, black, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .white: return "White"
        case .offWhite: return "Off-white"
        case .darkGray: return "Dark Grey"
        case .black: return "Black"
        case .custom: return "Custom"
        }
    }
    var color: RGBAColor? {
        switch self {
        case .white: return .white
        case .offWhite: return .offWhite
        case .darkGray: return .paperDarkGray
        case .black: return .paperBlack
        case .custom: return nil
        }
    }
}

/// Editable page size + background description used by "New Document" and "Page Settings".
struct PageFormat: Equatable {
    /// nil means custom size.
    var paperID: String? = PaperSize.letter.id {
        // Whiteboards and long scrolls are meant to keep growing.
        didSet {
            if paperID == PaperSize.whiteboard.id || paperID == PaperSize.longScroll.id, oldValue != paperID { autoExtends = true }
        }
    }
    var orientation: PageOrientation = .portrait
    var customWidth: Double = 8.5
    var customHeight: Double = 11
    var unit: LengthUnit = .inches
    var backgroundChoice: BackgroundChoice = .white
    var customColor = RGBAColor(r: 0.98, g: 0.95, b: 0.86)
    var template: PageTemplate = .blank
    var spacing: Double = Double(PageTemplate.blank.defaultSpacing)
    /// The page grows downwards while you write near its bottom edge.
    var autoExtends = false

    init() {}

    init(size: CGSize, background: PageBackground) {
        if let match = PaperSize.matching(size) {
            paperID = match.paper.id
            orientation = match.orientation
        } else {
            paperID = nil
            unit = .points
            customWidth = Double(size.width)
            customHeight = Double(size.height)
            orientation = size.width > size.height ? .landscape : .portrait
        }
        if background.color.isClose(to: .white) { backgroundChoice = .white }
        else if background.color.isClose(to: .offWhite) { backgroundChoice = .offWhite }
        else if background.color.isClose(to: .paperDarkGray) { backgroundChoice = .darkGray }
        else if background.color.isClose(to: .paperBlack) { backgroundChoice = .black }
        else { backgroundChoice = .custom; customColor = background.color }
        template = background.template
        spacing = Double(background.spacing)
        autoExtends = background.autoExtends ?? false
    }

    var size: CGSize {
        if let paper = PaperSize.find(paperID) { return paper.size(for: orientation) }
        let w = unit.toPoints(CGFloat(customWidth)).clamped(36, 14_400)
        let h = unit.toPoints(CGFloat(customHeight)).clamped(36, 14_400)
        return CGSize(width: w, height: h)
    }

    var background: PageBackground {
        var bg = PageBackground(color: backgroundChoice.color ?? customColor, template: template, spacing: CGFloat(spacing))
        bg.autoExtends = autoExtends ? true : nil
        return bg
    }

    var isSquare: Bool {
        let s = size
        return abs(s.width - s.height) < 0.5
    }
}

struct PageFormatEditor: View {
    @Binding var format: PageFormat
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var savingSize = false
    @State private var sizeName = ""

    var body: some View {
        Section("Page Size") {
            Picker("Size", selection: $format.paperID) {
                ForEach([PaperSize.Category.paper, .other, .screen], id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(PaperSize.all.filter { $0.category == category }) { p in
                            Text("\(p.name)  ·  \(p.subtitle)").tag(Optional(p.id))
                        }
                    }
                }
                if !prefs.savedPageSizes.isEmpty {
                    Section(PaperSize.Category.saved.rawValue) {
                        ForEach(prefs.savedPageSizes) { saved in
                            let p = saved.paperSize
                            Text("\(p.name)  ·  \(p.subtitle)").tag(Optional(p.id))
                        }
                    }
                }
                Text("Custom").tag(String?.none)
            }
            .pickerStyle(.menu)

            if let id = format.paperID, let saved = prefs.savedPageSizes.first(where: { $0.paperSize.id == id }) {
                Button("Delete Saved Size “\(saved.name)”", systemImage: "trash", role: .destructive) {
                    let size = format.size
                    prefs.savedPageSizes.removeAll { $0.id == saved.id }
                    format.paperID = nil
                    format.unit = .points
                    format.customWidth = Double(size.width)
                    format.customHeight = Double(size.height)
                }
            }

            if format.paperID == nil {
                HStack {
                    Text("Width")
                    TextField("Width", value: $format.customWidth, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("Height")
                    TextField("Height", value: $format.customHeight, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Units", selection: Binding(get: { format.unit }, set: { convertUnit(to: $0) })) {
                    ForEach(LengthUnit.allCases) { Text($0.displayName).tag($0) }
                }
                Button("Save This Size…", systemImage: "star") {
                    let s = format.size
                    sizeName = String(format: "%.0f × %.0f", s.width, s.height)
                    savingSize = true
                }
            }

            Picker("Orientation", selection: Binding(get: { format.orientation }, set: { setOrientation($0) })) {
                Label("Portrait", systemImage: "rectangle.portrait").tag(PageOrientation.portrait)
                Label("Landscape", systemImage: "rectangle").tag(PageOrientation.landscape)
            }
            .pickerStyle(.segmented)
            .disabled(format.isSquare)

            LabeledContent("Dimensions") {
                let s = format.size
                Text(String(format: "%.0f × %.0f pt  (%.2f × %.2f in)", s.width, s.height, s.width / 72, s.height / 72))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .alert("Save Page Size", isPresented: $savingSize) {
            TextField("Name", text: $sizeName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveCurrentSize() }
        } message: {
            Text("Saved sizes appear under “My Sizes” when creating notebooks and in Page Settings.")
        }

        Section("Background") {
            HStack(spacing: 14) {
                ForEach(BackgroundChoice.allCases) { choice in
                    Button {
                        format.backgroundChoice = choice
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill((choice.color ?? format.customColor).color)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.appAccent, lineWidth: format.backgroundChoice == choice ? 3 : 0))
                                .frame(width: 44, height: 56)
                            Text(choice.title).font(.caption).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if format.backgroundChoice == .custom {
                    ColorPicker("Custom", selection: Binding(get: { format.customColor.color },
                                                             set: { format.customColor = RGBAColor($0).withAlpha(1) }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .padding(.vertical, 4)

            Picker("Template", selection: Binding(get: { format.template }, set: { t in
                format.template = t
                format.spacing = Double(t.defaultSpacing)
            })) {
                ForEach(PageTemplate.allCases) { t in
                    Label(t.displayName, systemImage: t.symbol).tag(t)
                }
            }

            if format.template != .blank {
                let isEngineering = format.template == .engineering
                VStack(alignment: .leading) {
                    Text(isEngineering ? "Major grid: \(Int(format.spacing)) pt (\(String(format: "%.2f", format.spacing / 72)) in, 5 subdivisions)"
                                       : "Spacing: \(Int(format.spacing)) pt (\(String(format: "%.1f", format.spacing / 72 * 25.4)) mm)")
                        .font(.subheadline)
                    Slider(value: $format.spacing, in: isEngineering ? 36...144 : 8...48, step: isEngineering ? 9 : 1)
                }
            }

            Toggle(isOn: $format.autoExtends) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Endless Page")
                    Text("The page grows as you write near its bottom or right edge — great with Whiteboard.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveCurrentSize() {
        let size = format.size
        let name = sizeName.trimmingCharacters(in: .whitespaces)
        let saved = SavedPageSize(name: name.isEmpty ? "My Size" : name, width: size.width, height: size.height)
        prefs.savedPageSizes.append(saved)
        format.orientation = size.width > size.height ? .landscape : .portrait
        format.paperID = saved.paperSize.id
    }

    private func convertUnit(to unit: LengthUnit) {
        let s = format.size
        format.unit = unit
        let digits: Double = unit == .points || unit == .pixels ? 1 : 100
        format.customWidth = (Double(unit.fromPoints(s.width)) * digits).rounded() / digits
        format.customHeight = (Double(unit.fromPoints(s.height)) * digits).rounded() / digits
    }

    private func setOrientation(_ o: PageOrientation) {
        guard o != format.orientation else { return }
        format.orientation = o
        if format.paperID == nil {
            let w = format.customWidth, h = format.customHeight
            if (o == .landscape) == (w < h) { format.customWidth = h; format.customHeight = w }
        }
    }
}

struct NewDocumentView: View {
    /// Folder the new document goes into (nil = top level).
    var folderID: UUID? = nil
    let onCreate: (UUID) -> Void
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var format = PageFormat()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Untitled", text: $title)
                        .font(.title3)
                }
                PageFormatEditor(format: $format)
            }
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.bold()
                }
            }
            .alert("Couldn't Create Document", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
        var settings = ToolSettings()
        if format.background.isDark {
            // Light ink on dark paper.
            settings.pen.color = RGBAColor(hex: 0xF2F2F2)
            settings.shape.strokeColor = RGBAColor(hex: 0xF2F2F2)
            settings.text.color = RGBAColor(hex: 0xF2F2F2)
        }
        do {
            let id = try store.create(title: name, pageSize: format.size, background: format.background, settings: settings,
                                      folderID: folderID)
            onCreate(id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
