import Foundation
import Combine

/// In-app development console backing store. Thread-safe, observable, capped.
final class DiagnosticLogger: ObservableObject {
    static let shared = DiagnosticLogger()

    enum Category: String, Codable, CaseIterable {
        case launch      = "LAUNCH"
        case runtime     = "RUNTIME"
        case termination = "TERM"
        case compat      = "COMPAT"
        case fileSystem  = "FS"
        case loading     = "LOAD"
        case crash       = "CRASH"
        case importer    = "IMPORT"

        var symbol: String {
            switch self {
            case .launch:      return "play.circle"
            case .runtime:     return "gearshape.2"
            case .termination: return "stop.circle"
            case .compat:      return "checklist"
            case .fileSystem:  return "folder"
            case .loading:     return "arrow.down.circle"
            case .crash:       return "exclamationmark.octagon"
            case .importer:    return "square.and.arrow.down"
            }
        }
    }

    struct Entry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let category: Category
        let message: String

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
        }
    }

    @Published private(set) var entries: [Entry] = []
    private let maxEntries = 2000
    private let lock = NSLock()

    private init() {
        log(.runtime, "Diagnostic logger initialized")
    }

    func log(_ category: Category, _ message: String) {
        let entry = Entry(id: UUID(), timestamp: Date(), category: category, message: message)
        lock.lock()
        var next = entries
        next.append(entry)
        if next.count > maxEntries { next.removeFirst(next.count - maxEntries) }
        lock.unlock()
        // Publish on main for SwiftUI.
        if Thread.isMainThread {
            entries = next
        } else {
            DispatchQueue.main.async { self.entries = next }
        }
    }

    func clear() {
        lock.lock(); entries = []; lock.unlock()
        log(.runtime, "Log cleared")
    }

    /// Produce a copyable plain-text dump of the whole log.
    func exportText() -> String {
        entries.map { "\($0.timeString)  [\($0.category.rawValue)]  \($0.message)" }
               .joined(separator: "\n")
    }
}
