import SwiftUI

/// Plain page list: navigate, add, duplicate, delete, reorder.
struct PageManagerView: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(editor.document.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        editor.goToPage(index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: page.background.template.symbol)
                                .frame(width: 28)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Page \(index + 1)").foregroundStyle(.primary)
                                Text("\(PaperSize.describe(page.size)) · \(page.background.template.displayName) · \(page.count) item\(page.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == editor.currentPageIndex {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Insert Page After", systemImage: "plus") { editor.addPage(after: index); revision += 1 }
                        Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicatePage(at: index); revision += 1 }
                        Button("Delete", systemImage: "trash", role: .destructive) { editor.deletePage(at: index); revision += 1 }
                            .disabled(editor.pageCount <= 1)
                    }
                    .swipeActions {
                        if editor.pageCount > 1 {
                            Button("Delete", systemImage: "trash", role: .destructive) { editor.deletePage(at: index); revision += 1 }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicatePage(at: index); revision += 1 }
                            .tint(.indigo)
                    }
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    // List's destination is "before index `to`" in the original array.
                    let dest = to > f ? to - 1 : to
                    editor.movePage(from: f, to: dest)
                    revision += 1
                }
            }
            .id(revision)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Page", systemImage: "plus") {
                        editor.addPage(after: editor.pageCount - 1)
                        revision += 1
                    }
                }
            }
        }
    }
}

/// Size / background / template for the current page (or all pages).
struct PageSettingsView: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var format = PageFormat()
    @State private var applyToAll = false

    var body: some View {
        NavigationStack {
            Form {
                PageFormatEditor(format: $format)
                Section {
                    Toggle("Apply to All Pages", isOn: $applyToAll)
                }
            }
            .navigationTitle("Page \(editor.currentPageIndex + 1) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        editor.applyPageSettings(size: format.size, background: format.background, toAllPages: applyToAll)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                format = PageFormat(size: editor.currentPageSize, background: editor.currentPageBackground)
            }
        }
    }
}
