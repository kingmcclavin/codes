import Charts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Home

/// The Data section: function grapher and data tables.
struct DataHomeView: View {
    @EnvironmentObject private var calc: CalculatorStore
    @State private var path = NavigationPath()
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Graphs") {
                    NavigationLink(value: DataRoute.grapher) {
                        Label("Function Grapher", systemImage: "function")
                    }
                }
                Section("Tables") {
                    if calc.tables.isEmpty {
                        Text("No tables yet. Create one to record measurements, compute columns, get statistics and plot your data.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(calc.tables) { t in
                        NavigationLink(value: DataRoute.table(t.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.body.weight(.medium))
                                Text("\(t.columns.count) columns · \(t.usedRowCount) rows · \(t.modified.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") { calc.duplicate(t) }
                            Button("Delete", systemImage: "trash", role: .destructive) { calc.delete(t) }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { calc.delete(t) }
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .navigationDestination(for: DataRoute.self) { route in
                switch route {
                case .grapher: FunctionGraphView()
                case let .table(id): TableEditorView(tableID: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Table", systemImage: "tablecells.badge.ellipsis") {
                            let t = DataTable.blank()
                            calc.save(t)
                            path.append(DataRoute.table(t.id))
                        }
                        Button("Import CSV…", systemImage: "square.and.arrow.down") { importing = true }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                      let table = DataTable.fromCSV(text, name: url.deletingPathExtension().lastPathComponent) else {
                    importError = "The file doesn't look like a CSV table."
                    return
                }
                calc.save(table)
                path.append(DataRoute.table(table.id))
            }
            .alert("Couldn't Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
        }
    }
}

enum DataRoute: Hashable {
    case grapher
    case table(UUID)
}

// MARK: - Table editor

struct TableEditorView: View {
    let tableID: UUID
    @EnvironmentObject private var calc: CalculatorStore
    @State private var table: DataTable?
    @State private var editingColumn: Int?
    @State private var showChart = false
    @State private var showStats = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var shareURL: URL?
    @State private var saveTask: Task<Void, Never>?

    private let cellWidth: CGFloat = 120
    private let rowHeaderWidth: CGFloat = 44

    var body: some View {
        Group {
            if let table {
                let ev = table.evaluate(engine: calc.engine)
                grid(table, ev)
                    .safeAreaInset(edge: .bottom) { summaryBar(table, ev) }
            } else {
                ContentUnavailableView("Table Deleted", systemImage: "tablecells")
            }
        }
        .navigationTitle(table?.name ?? "Table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear { if table == nil { table = calc.table(id: tableID) } }
        .onDisappear { commit() }
        .onChange(of: table) { _, _ in scheduleSave() }
        .sheet(isPresented: Binding(get: { editingColumn != nil }, set: { if !$0 { editingColumn = nil } })) {
            if let i = editingColumn, let t = table, t.columns.indices.contains(i) {
                ColumnEditorView(table: Binding(get: { self.table ?? t }, set: { self.table = $0 }), index: i)
            }
        }
        .sheet(isPresented: $showChart) {
            if let table { NavigationStack { DataChartView(table: table) } }
        }
        .sheet(isPresented: $showStats) {
            if let table { NavigationStack { StatisticsView(table: table) } }
        }
        .sheet(item: Binding(get: { shareURL.map(SharedTableFile.init) }, set: { shareURL = $0?.url })) { f in
            ShareSheet(items: [f.url])
        }
        .alert("Rename Table", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if !newName.isEmpty { table?.name = newName } }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Statistics", systemImage: "sum") { commit(); showStats = true }
            Button("Chart", systemImage: "chart.xyaxis.line") { commit(); showChart = true }
            Menu {
                Button("Add Row", systemImage: "plus") { table?.addRow() }
                Button("Add 10 Rows", systemImage: "plus.rectangle.on.rectangle") {
                    table?.rowCount += 10; table?.normalize()
                }
                Button("Add Data Column", systemImage: "rectangle.split.3x1") {
                    table?.addColumn(); editingColumn = (table?.columns.count ?? 1) - 1
                }
                Button("Add Computed Column", systemImage: "function") {
                    table?.addColumn(formula: table?.columns.first.map { "2*\($0.name)" } ?? "1")
                    editingColumn = (table?.columns.count ?? 1) - 1
                }
                Divider()
                Button("Rename…", systemImage: "pencil") { newName = table?.name ?? ""; renaming = true }
                Button("Export CSV", systemImage: "square.and.arrow.up") { exportCSV() }
                if let table {
                    InsertIntoNotebookMenu(item: { tableImage(table) }) {
                        Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Grid

    private func grid(_ t: DataTable, _ ev: DataTable.Evaluated) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(0..<t.rowCount, id: \.self) { row in
                        HStack(spacing: 0) {
                            Text("\(row + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: rowHeaderWidth, height: 36)
                                .contextMenu {
                                    Button("Insert Row Above", systemImage: "arrow.up.to.line") { insertRow(at: row) }
                                    Button("Delete Row", systemImage: "trash", role: .destructive) { table?.removeRow(row) }
                                }
                            ForEach(Array(t.columns.enumerated()), id: \.element.id) { c, col in
                                cell(t, ev, column: c, row: row)
                            }
                        }
                        .background(row % 2 == 1 ? Color(uiColor: .secondarySystemBackground).opacity(0.5) : .clear)
                    }
                    Button {
                        table?.addRow()
                    } label: {
                        Label("Add Row", systemImage: "plus").font(.callout)
                    }
                    .padding(.leading, rowHeaderWidth + 8)
                    .padding(.vertical, 10)
                } header: {
                    header(t, ev)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ t: DataTable, _ ev: DataTable.Evaluated) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: rowHeaderWidth, height: 44)
            ForEach(Array(t.columns.enumerated()), id: \.element.id) { c, col in
                Button { editingColumn = c } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            if col.isComputed { Image(systemName: "function").font(.caption2) }
                            Text(col.name).font(.subheadline.monospaced().weight(.semibold))
                        }
                        Text(ev.columnErrors[col.id] != nil ? "error" : (col.unit.isEmpty ? (col.isComputed ? col.formula : " ") : col.unit))
                            .font(.caption2)
                            .foregroundStyle(ev.columnErrors[col.id] != nil ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: cellWidth, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) { Divider() }
            }
            Button { table?.addColumn(); editingColumn = t.columns.count } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add Column")
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func cell(_ t: DataTable, _ ev: DataTable.Evaluated, column c: Int, row: Int) -> some View {
        let col = t.columns[c]
        Group {
            if col.isComputed {
                Text(ev.values[col.id]?[row].map { NumberFormatting.format($0, digits: 8) } ?? "")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                TextField("", text: Binding(
                    get: { (table?.columns.indices.contains(c) == true && row < (table?.rowCount ?? 0)) ? table!.columns[c].cells[row] : "" },
                    set: { v in
                        guard var tt = table, tt.columns.indices.contains(c), row < tt.rowCount else { return }
                        tt.columns[c].cells[row] = v
                        table = tt
                    }))
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(ev.cellErrors["\(col.id)/\(row)"] != nil ? Color.red : Color.primary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: cellWidth, height: 36)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func summaryBar(_ t: DataTable, _ ev: DataTable.Evaluated) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text("x̄").font(.caption.weight(.semibold)).frame(width: rowHeaderWidth)
                ForEach(t.columns) { col in
                    let s = Statistics(ev.numbers(col.id))
                    Text(s.map { "\(NumberFormatting.format($0.mean, digits: 5)) ± \(NumberFormatting.format($0.stdDev, digits: 3))" } ?? "—")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: cellWidth)
                }
            }
            .frame(height: 30)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Actions

    private func insertRow(at row: Int) {
        guard var t = table else { return }
        for i in t.columns.indices { t.columns[i].cells.insert("", at: min(row, t.columns[i].cells.count)) }
        t.rowCount += 1
        table = t
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        saveTask?.cancel()
        guard let table, table != calc.table(id: tableID) else { return }
        calc.save(table)
    }

    private func exportCSV() {
        guard let table else { return }
        commit()
        let name = table.name.isEmpty ? "Table" : table.name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).csv")
        if (try? table.csv(engine: calc.engine).write(to: url, atomically: true, encoding: .utf8)) != nil { shareURL = url }
    }

    private func tableImage(_ table: DataTable) -> NoteInsertion? {
        let ev = table.evaluate(engine: calc.engine)
        let rows = min(table.usedRowCount, 30)
        let width = CGFloat(table.columns.count) * 110 + 36
        let height = CGFloat(rows + 2) * 26 + 40
        return renderForNote(TableSnapshotView(table: table, evaluated: ev, rows: rows), size: CGSize(width: width, height: height))
            .map(NoteInsertion.image)
    }
}

private struct SharedTableFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A static rendering of a table for notes.
struct TableSnapshotView: View {
    let table: DataTable
    let evaluated: DataTable.Evaluated
    let rows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(table.name).font(.headline)
            Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.columns) { col in
                        Text(col.unit.isEmpty ? col.name : "\(col.name) (\(col.unit))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(width: 110, height: 26, alignment: .trailing)
                    }
                }
                Divider()
                ForEach(0..<rows, id: \.self) { r in
                    GridRow {
                        ForEach(table.columns) { col in
                            Text(evaluated.values[col.id]?[r].map { NumberFormatting.format($0, digits: 6) } ?? "")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 110, height: 26, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.trailing, 8)
        }
        .padding(14)
        .foregroundStyle(.black)
    }
}

// MARK: - Column editor

struct ColumnEditorView: View {
    @Binding var table: DataTable
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calc: CalculatorStore
    @State private var column = DataColumn(name: "")
    @State private var computed = false
    @State private var loaded = false

    private var otherNames: [String] {
        table.columns.enumerated().filter { $0.offset != index }.map(\.element.name)
    }

    private var nameProblem: String? {
        let n = column.name
        if n.isEmpty { return "Enter a name" }
        if CSV.identifier(from: n, fallback: "") != n { return "Use letters, digits and _ only (start with a letter)" }
        if otherNames.contains(n) { return "Another column has this name" }
        return nil
    }

    private var formulaProblem: String? {
        guard computed else { return nil }
        var t = table
        if t.columns.indices.contains(index) { t.columns[index] = column; t.columns[index].formula = column.formula }
        let ev = t.evaluate(engine: calc.engine)
        if column.formula.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a formula" }
        return ev.columnErrors[column.id]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (used in formulas)", text: $column.name)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Unit (optional, e.g. m/s)", text: $column.unit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(UnitLibrary.parse(column.unit) == nil ? Color.red : Color.primary)
                } footer: {
                    if let nameProblem { Text(nameProblem).foregroundStyle(.red) }
                }
                Section {
                    Picker("Type", selection: $computed) {
                        Text("Data").tag(false)
                        Text("Computed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if computed {
                        TextField("Formula, e.g. m*a or sqrt(x^2 + y^2)", text: $column.formula)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    if let formulaProblem {
                        Text(formulaProblem).foregroundStyle(.red)
                    } else if computed {
                        Text("Use other columns by name: \(otherNames.joined(separator: ", ")). Calculator variables and constants work too.")
                    } else {
                        Text("Cells accept numbers or expressions such as 1/3 or 2.5e-3.")
                    }
                }
                Section {
                    HStack {
                        Button("Move Left", systemImage: "arrow.left") { move(-1) }.disabled(index == 0)
                        Spacer()
                        Button("Move Right", systemImage: "arrow.right") { move(1) }.disabled(index >= table.columns.count - 1)
                    }
                    .buttonStyle(.borderless)
                    Button("Delete Column", systemImage: "trash", role: .destructive) {
                        if table.columns.indices.contains(index) { table.columns.remove(at: index) }
                        dismiss()
                    }
                    .disabled(table.columns.count <= 1)
                }
            }
            .navigationTitle("Column")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(); dismiss() }
                        .bold()
                        .disabled(nameProblem != nil || formulaProblem != nil)
                }
            }
            .onAppear {
                guard !loaded, table.columns.indices.contains(index) else { return }
                loaded = true
                column = table.columns[index]
                computed = column.isComputed
            }
        }
    }

    private func apply() {
        guard table.columns.indices.contains(index) else { return }
        var c = column
        if !computed { c.formula = "" }
        let oldName = table.columns[index].name
        table.columns[index] = c
        // Keep computed columns working after a rename.
        if oldName != c.name {
            for i in table.columns.indices where table.columns[i].isComputed {
                table.columns[i].formula = Self.rename(oldName, to: c.name, in: table.columns[i].formula)
            }
        }
        table.normalize()
    }

    private func move(_ delta: Int) {
        apply()
        let j = index + delta
        guard table.columns.indices.contains(j) else { return }
        table.columns.swapAt(index, j)
        dismiss()
    }

    /// Replaces whole-word occurrences of a name in a formula.
    static func rename(_ old: String, to new: String, in formula: String) -> String {
        var out = "", word = ""
        func flush() { out += word == old ? new : word; word = "" }
        for ch in formula {
            if ch.isLetter || ch.isNumber || ch == "_" { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    let table: DataTable
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ev = table.evaluate(engine: calc.engine)
        List {
            ForEach(table.columns) { col in
                Section(col.unit.isEmpty ? col.name : "\(col.name) (\(col.unit))") {
                    if let s = Statistics(ev.numbers(col.id)) {
                        statRow("Count", Double(s.count), digits: 10)
                        statRow("Mean", s.mean)
                        statRow("Median", s.median)
                        statRow("Std. deviation (sample)", s.stdDev)
                        statRow("Std. deviation (population)", s.populationStdDev)
                        statRow("Variance (sample)", s.variance)
                        statRow("Minimum", s.min)
                        statRow("Maximum", s.max)
                        statRow("Range", s.range)
                        statRow("Q1 / Q3", nil, text: "\(NumberFormatting.format(s.q1, digits: 6)) / \(NumberFormatting.format(s.q3, digits: 6))")
                        statRow("Sum", s.sum)
                    } else {
                        Text("No numeric values").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func statRow(_ label: String, _ value: Double?, digits: Int = 6, text: String? = nil) -> some View {
        LabeledContent(label) {
            Text(text ?? value.map { NumberFormatting.format($0, digits: digits) } ?? "—")
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - Data chart

struct DataChartView: View {
    let table: DataTable
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.dismiss) private var dismiss
    @State private var xID: UUID?
    @State private var yIDs: [UUID] = []
    @State private var style: Style = .points
    @State private var fitModel: FitModel?
    @State private var loaded = false

    enum Style: String, CaseIterable, Identifiable {
        case points = "Points", lines = "Lines", both = "Both"
        var id: String { rawValue }
    }

    var body: some View {
        let ev = table.evaluate(engine: calc.engine)
        let series = seriesData(ev)
        let fit = fitResult(series)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                legend(series)
                DataChart(series: series, style: style, fit: fit, xLabel: axisLabel(xID))
                if let fit {
                    HStack {
                        Text(fit.equation).font(.callout.monospaced())
                        Text("R² = \(NumberFormatting.format(fit.r2, digits: 5))").font(.callout.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = fit.expression }
                            .labelStyle(.iconOnly)
                    }
                } else if fitModel != nil {
                    Text("This fit needs more points (or positive values for exponential/power).").font(.caption).foregroundStyle(.orange)
                }
                if let first = series.first, let r = correlation(first.points.map(\.x), first.points.map(\.y)) {
                    Text("Correlation r = \(NumberFormatting.format(r, digits: 4))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            Divider()
            Form {
                Picker("X axis", selection: $xID) {
                    ForEach(table.columns) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("Y series") {
                    ForEach(table.columns.filter { $0.id != xID }) { col in
                        Toggle(isOn: Binding(
                            get: { yIDs.contains(col.id) },
                            set: { on in if on { yIDs.append(col.id) } else { yIDs.removeAll { $0 == col.id } } })) {
                            HStack {
                                RoundedRectangle(cornerRadius: 1).fill(ChartPalette.color(slot(col.id))).frame(width: 14, height: 3)
                                Text(col.name).font(.body.monospaced())
                            }
                        }
                    }
                }
                Picker("Style", selection: $style) {
                    ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Trend line (first series)", selection: $fitModel) {
                    Text("None").tag(FitModel?.none)
                    ForEach(FitModel.allCases) { Text("\($0.rawValue): \($0.form)").tag(Optional($0)) }
                }
            }
            .frame(height: 320)
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                InsertIntoNotebookMenu(item: { image(series, fit) }) {
                    Label("Insert into Notebook", systemImage: "note.text.badge.plus")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            xID = table.columns.first?.id
            yIDs = table.columns.dropFirst().prefix(1).map(\.id)
        }
    }

    /// Color slot follows the column, not its rank among selected series.
    private func slot(_ id: UUID) -> Int {
        (table.columns.firstIndex { $0.id == id } ?? 0) % ChartPalette.count
    }

    private func axisLabel(_ id: UUID?) -> String {
        guard let col = table.columns.first(where: { $0.id == id }) else { return "" }
        return col.unit.isEmpty ? col.name : "\(col.name) (\(col.unit))"
    }

    private func seriesData(_ ev: DataTable.Evaluated) -> [DataChart.Series] {
        guard let xID, let xs = ev.values[xID] else { return [] }
        return table.columns.filter { yIDs.contains($0.id) && $0.id != xID }.map { col in
            let ys = ev.values[col.id] ?? []
            let pts = zip(xs, ys).compactMap { x, y -> FunctionSampler.Point? in
                guard let x, let y else { return nil }
                return FunctionSampler.Point(x: x, y: y)
            }
            return DataChart.Series(id: col.id, name: axisLabel(col.id), slot: slot(col.id), points: pts)
        }
    }

    private func fitResult(_ series: [DataChart.Series]) -> Fit? {
        guard let model = fitModel, let first = series.first else { return nil }
        return Fit.fit(model, x: first.points.map(\.x), y: first.points.map(\.y))
    }

    private func legend(_ series: [DataChart.Series]) -> some View {
        HStack(spacing: 16) {
            ForEach(series) { s in
                HStack(spacing: 6) {
                    Circle().fill(ChartPalette.color(s.slot)).frame(width: 8, height: 8)
                    Text(s.name).font(.caption.monospaced())
                }
            }
        }
    }

    private func image(_ series: [DataChart.Series], _ fit: Fit?) -> NoteInsertion? {
        let view = VStack(alignment: .leading, spacing: 8) {
            Text(table.name).font(.headline)
            HStack(spacing: 16) {
                ForEach(series) { s in
                    HStack(spacing: 6) {
                        Circle().fill(ChartPalette.paperColor(s.slot)).frame(width: 8, height: 8)
                        Text(s.name).font(.caption.monospaced())
                    }
                }
            }
            DataChart(series: series, style: style, fit: fit, xLabel: axisLabel(xID), forPaper: true)
            if let fit {
                Text("\(fit.equation)    R² = \(NumberFormatting.format(fit.r2, digits: 5))").font(.caption.monospaced())
            }
        }
        .padding(18)
        .foregroundStyle(.black)
        return renderForNote(view, size: CGSize(width: 640, height: 440)).map(NoteInsertion.image)
    }
}

/// Scatter/line chart of table columns, with an optional trend line.
struct DataChart: View {
    struct Series: Identifiable {
        var id: UUID
        var name: String
        var slot: Int
        var points: [FunctionSampler.Point]
    }

    let series: [Series]
    let style: DataChartView.Style
    let fit: Fit?
    var xLabel: String = ""
    var forPaper = false
    @State private var selectedX: Double?

    private func color(_ slot: Int) -> Color { forPaper ? ChartPalette.paperColor(slot) : ChartPalette.color(slot) }

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                    if style != .points {
                        LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("series", s.id.uuidString))
                            .foregroundStyle(color(s.slot))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if style != .lines {
                        PointMark(x: .value("x", p.x), y: .value("y", p.y))
                            .foregroundStyle(color(s.slot))
                            .symbolSize(64)
                    }
                }
            }
            if let fit, let first = series.first, let lo = first.points.map(\.x).min(), let hi = first.points.map(\.x).max(), hi > lo {
                ForEach(0..<81, id: \.self) { i in
                    let x = lo + (hi - lo) * Double(i) / 80
                    let y = fit.predict(x)
                    if y.isFinite {
                        LineMark(x: .value("x", x), y: .value("y", y), series: .value("series", "fit"))
                            .foregroundStyle(color(first.slot).opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
            }
            if let selectedX, let s = series.first, let p = nearest(selectedX, in: s.points) {
                RuleMark(x: .value("x", p.x))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text("(\(NumberFormatting.format(p.x, digits: 5)), \(NumberFormatting.format(p.y, digits: 5)))")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXAxisLabel(xLabel, alignment: .center)
        .chartXSelection(value: $selectedX)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
    }

    private func nearest(_ x: Double, in points: [FunctionSampler.Point]) -> FunctionSampler.Point? {
        points.min { abs($0.x - x) < abs($1.x - x) }
    }
}
