import SwiftUI

/// App-wide search: notebooks, typed text and calculations in notes,
/// formulas, data tables, history and tools.
struct SearchView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var tabs: TabsModel
    @EnvironmentObject private var calc: CalculatorStore
    @Environment(\.basisNavigate) private var navigate
    @State private var query = ""
    @State private var pages: [DocumentStore.SearchablePage] = []
    @State private var indexing = false

    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                if q.isEmpty {
                    Section {
                        Label("Search notebook titles, typed text, calculation cards, formulas, tables, history and tools.",
                              systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Handwriting isn't searched — only typed text and calculations.")
                    }
                } else {
                    results
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search everything")
            .navigationTitle("Search")
            .toolbar {
                if indexing { ToolbarItem(placement: .primaryAction) { ProgressView() } }
            }
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case let .formula(id):
                    if let f = calc.formula(id: id) { FormulaRunView(formula: f) }
                case let .table(id):
                    TableEditorView(tableID: id)
                case let .record(r):
                    if let f = calc.formula(id: r.formulaID) {
                        FormulaRunView(formula: f, initialInputs: Dictionary(r.inputs.map { ($0.name, NumberFormatting.plain($0.value)) },
                                                                             uniquingKeysWith: { a, _ in a }))
                    }
                case let .tool(tool):
                    tool.destination
                }
            }
            .task { await reindex() }
        }
    }

    private func reindex() async {
        tabs.flushAll()
        indexing = true
        let store = self.store
        pages = await Task.detached(priority: .userInitiated) { store.searchablePages() }.value
        indexing = false
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let notebooks = store.summaries.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let notePages = pages.filter { $0.text.localizedCaseInsensitiveContains(q) }
        let formulas = calc.allFormulas.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.expression.localizedCaseInsensitiveContains(q)
                || $0.category.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q)
        }
        let tables = calc.tables.filter { t in
            t.name.localizedCaseInsensitiveContains(q) || t.columns.contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
        let history = calc.history.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.expression.localizedCaseInsensitiveContains(q)
        }.prefix(20)
        let tools = SearchTool.allCases.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.keywords.contains { $0.hasPrefix(q.lowercased()) } }

        if notebooks.isEmpty && notePages.isEmpty && formulas.isEmpty && tables.isEmpty && history.isEmpty && tools.isEmpty {
            if indexing {
                Text("Searching…").foregroundStyle(.secondary)
            } else {
                ContentUnavailableView.search(text: q)
            }
        }
        if !notebooks.isEmpty {
            Section("Notebooks") {
                ForEach(notebooks) { d in
                    Button { tabs.open(d.id) } label: {
                        Label(d.title.isEmpty ? "Untitled" : d.title, systemImage: d.icon ?? "book.closed")
                    }
                }
            }
        }
        if !notePages.isEmpty {
            Section("In Notes") {
                ForEach(Array(notePages.prefix(50).enumerated()), id: \.offset) { _, p in
                    Button { tabs.open(p.documentID, page: p.pageIndex) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(p.title.isEmpty ? "Untitled" : p.title) · page \(p.pageIndex + 1)\(p.section.map { " · \($0)" } ?? "")")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(Self.snippet(p.text, around: q))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        if !formulas.isEmpty {
            Section("Formulas") {
                ForEach(formulas) { f in
                    NavigationLink(value: SearchRoute.formula(f.id)) { FormulaRow(formula: f) }
                }
            }
        }
        if !tables.isEmpty {
            Section("Tables") {
                ForEach(tables) { t in
                    NavigationLink(value: SearchRoute.table(t.id)) {
                        Label(t.name, systemImage: "tablecells")
                    }
                }
            }
        }
        if !tools.isEmpty {
            Section("Tools") {
                ForEach(tools) { t in
                    NavigationLink(value: SearchRoute.tool(t)) { Label(t.title, systemImage: t.icon) }
                }
            }
        }
        if !history.isEmpty {
            Section("History") {
                ForEach(Array(history)) { r in
                    if r.formulaID != nil, calc.formula(id: r.formulaID) != nil {
                        NavigationLink(value: SearchRoute.record(r)) { historyRow(r) }
                    } else {
                        Button {
                            calc.draftExpression = r.expression
                            navigate(.calculator)
                        } label: { historyRow(r) }
                    }
                }
            }
        }
    }

    private func historyRow(_ r: CalculationRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.title).foregroundStyle(.primary)
            Text(r.results.map { "\($0.name == "=" ? "" : "\($0.name) = ")\($0.formatted)" }.joined(separator: "   "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    /// A short excerpt of `text` around the first match.
    static func snippet(_ text: String, around query: String, radius: Int = 50) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "  ")
        guard let r = flat.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(radius * 2))
        }
        let start = flat.index(r.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}

enum SearchRoute: Hashable {
    case formula(UUID)
    case table(UUID)
    case record(CalculationRecord)
    case tool(SearchTool)
}

/// Built-in tools reachable from search.
enum SearchTool: String, CaseIterable, Identifiable, Hashable {
    case converter, grapher, solver, matrices, vectors, bases, sections, beams
    var id: String { rawValue }

    var title: String {
        switch self {
        case .converter: return "Unit Converter"
        case .grapher: return "Function Grapher"
        case .solver: return "Equation Solver"
        case .matrices: return "Matrices"
        case .vectors: return "Vectors"
        case .bases: return "Number Bases"
        case .sections: return "Section Properties"
        case .beams: return "Beam Calculator"
        }
    }

    var icon: String {
        switch self {
        case .converter: return "arrow.left.arrow.right"
        case .grapher: return "function"
        case .solver: return "equal.square"
        case .matrices: return "square.grid.3x3"
        case .vectors: return "arrow.up.right.and.arrow.down.left"
        case .bases: return "number"
        case .sections: return "square.on.square.dashed"
        case .beams: return "ruler"
        }
    }

    var keywords: [String] {
        switch self {
        case .converter: return ["unit", "convert", "metric", "imperial", "temperature"]
        case .grapher: return ["graph", "plot", "function", "curve"]
        case .solver: return ["solve", "equation", "root", "zero"]
        case .matrices: return ["matrix", "determinant", "inverse", "linear", "system"]
        case .vectors: return ["vector", "dot", "cross", "angle"]
        case .bases: return ["binary", "hex", "octal", "base", "bits"]
        case .sections: return ["section", "inertia", "moment of inertia", "centroid", "area"]
        case .beams: return ["beam", "deflection", "moment", "shear", "cantilever"]
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .converter: UnitConverterView()
        case .grapher: FunctionGraphView()
        case .solver: EquationSolverView()
        case .matrices: MatrixCalculatorView()
        case .vectors: VectorCalculatorView()
        case .bases: NumberBaseView()
        case .sections: SectionPropertiesView()
        case .beams: BeamCalculatorView()
        }
    }
}
