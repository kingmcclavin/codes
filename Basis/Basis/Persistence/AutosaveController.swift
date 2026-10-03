import Foundation

/// Saves the document in the background shortly after edits.
///
/// A snapshot of the dirty pages is taken on the main thread (cheap: page data
/// are copy-on-write values) and encoded/written on a serial utility queue, so
/// saving never interrupts handwriting.
@MainActor
final class AutosaveController {
    private let document: DocumentModel
    private let packageURL: URL
    private let queue = DispatchQueue(label: "Basis.autosave", qos: .utility)
    private var scheduled: DispatchWorkItem?
    private let delay: TimeInterval

    init(document: DocumentModel, packageURL: URL, delay: TimeInterval = 1.5) {
        self.document = document
        self.packageURL = packageURL
        self.delay = delay
    }

    func scheduleSave() {
        scheduled?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        scheduled = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// - Parameter wait: block until the data is on disk (app backgrounding / closing).
    func saveNow(wait: Bool = false) {
        scheduled?.cancel()
        scheduled = nil
        guard let snapshot = document.takeSnapshot() else {
            if wait { queue.sync {} }
            return
        }
        let url = packageURL
        let document = self.document
        let work = {
            do {
                try DocumentStore.write(snapshot, to: url)
            } catch {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { document.restoreDirty(snapshot) }
                }
            }
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }
}
