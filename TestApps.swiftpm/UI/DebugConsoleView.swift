import SwiftUI
import UIKit

/// The in-app development console. Shows launch events, runtime errors,
/// termination, compatibility warnings, file-system and loading errors, etc.
struct DebugConsoleView: View {
    @EnvironmentObject var logger: DiagnosticLogger
    @Environment(\.dismiss) private var dismiss

    @State private var filter: DiagnosticLogger.Category?
    @State private var showCopied = false
    @State private var shareURL: URL?
    @State private var showShare = false

    private var entries: [DiagnosticLogger.Entry] {
        let base = logger.entries
        guard let filter else { return base }
        return base.filter { $0.category == filter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(entries) { entry in
                                row(entry).id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: logger.entries.count) { _ in
                        if let last = entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                    .onAppear {
                        if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = logger.exportText()
                        showCopied = true
                    } label: { Image(systemName: "doc.on.doc") }
                    Button {
                        if let url = writeLogFile() { shareURL = url; showShare = true }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { logger.clear() } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopied {
                    Text("Copied diagnostic log")
                        .font(.caption).padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .task { try? await Task.sleep(nanoseconds: 1_500_000_000); showCopied = false }
                }
            }
            .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", active: filter == nil) { filter = nil }
                ForEach(DiagnosticLogger.Category.allCases, id: \.self) { cat in
                    chip(title: cat.rawValue, active: filter == cat, symbol: cat.symbol) { filter = cat }
                }
            }
            .padding(8)
        }
    }

    private func chip(title: String, active: Bool, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? Color.blue : Color.secondary.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: DiagnosticLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timeString)
                .foregroundStyle(.secondary)
            Image(systemName: entry.category.symbol)
                .foregroundStyle(color(for: entry.category))
                .frame(width: 16)
            Text(entry.message)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func color(for c: DiagnosticLogger.Category) -> Color {
        switch c {
        case .crash, .termination: return .red
        case .compat: return .orange
        case .launch, .runtime: return .blue
        case .importer, .loading: return .green
        case .fileSystem: return .purple
        }
    }

    private func writeLogFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TestApps-console.txt")
        try? logger.exportText().data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
