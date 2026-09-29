#if canImport(SwiftUI) && canImport(UIKit)
import Foundation
import SwiftUI
import TI84EmulatorCore

/// User preferences (small, so kept in UserDefaults).
public struct EmulatorSettings: Codable, Equatable {
    /// 1 = real time, 0 = unlimited.
    public var speed: Double = 1
    /// LCD response emulation (0 = crisp).
    public var lcdPersistence: Double = 0.35
    public var haptics = true
    public var showDebugger = false

    static let defaultsKey = "TI84Emulator.settings"

    static func load() -> EmulatorSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(EmulatorSettings.self, from: data) else {
            return EmulatorSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Bridges the emulation thread and SwiftUI. Owns the emulator runner, the
/// persistent storage and the latest LCD frame. It never implements
/// calculator behaviour: key presses go straight to the emulated keypad.
@MainActor
public final class EmulatorViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case needsROM(String)
        case ready
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var frame = LCDFrame()
    @Published public private(set) var status: EmulatorRunner.Status = .paused
    @Published public var message: String?
    @Published public var settings: EmulatorSettings = .load() {
        didSet {
            settings.save()
            applySettings()
        }
    }

    public private(set) var runner: EmulatorRunner? {
        didSet { keypad.runner = runner }
    }
    public private(set) var rom: ROMImage?
    /// Thread-agnostic entry point for key events (usable from any view
    /// callback without hopping actors).
    public let keypad = KeypadSink()
    private var storage: PersistentStorage?
    private var autosaveTimer: Timer?
    private let frameMailbox = FrameMailbox()

    public nonisolated init() {}

    // MARK: - Startup

    /// Loads the bundled ROM (or a previously imported one) and boots.
    public func start() {
        guard runner == nil else { return }
        do {
            if ROMLoader.isBundledROMAvailable {
                try boot(ROMLoader.load(.bundled()))
            } else if let url = importedROMURL, FileManager.default.fileExists(atPath: url.path) {
                try boot(ROMLoader.load(.file(url)))
            } else {
                phase = .needsROM("No ROM was found in the app bundle. Import a TI-84 Plus ROM dump you legally own.")
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Imports a ROM chosen by the user (copied into Application Support).
    public func importROM(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let image = try ROMImage(data: data)
            if let destination = importedROMURL {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            shutdown()
            try boot(image)
        } catch {
            phase = .needsROM(String(describing: error))
        }
    }

    private var importedROMURL: URL? {
        try? PersistentStorage.defaultDirectory().appendingPathComponent("imported.rom")
    }

    private func boot(_ image: ROMImage) throws {
        var configuration = EmulatorConfiguration()
        configuration.lcdPersistence = settings.lcdPersistence
        let emulator = Emulator(rom: image, configuration: configuration)
        let storage = PersistentStorage(directory: try PersistentStorage.defaultDirectory())
        do {
            try storage.restoreAutosave(into: emulator)
        } catch {
            message = "Could not restore the previous session: \(error)"
        }

        let runner = EmulatorRunner(emulator: emulator)
        runner.speedMultiplier = settings.speed
        let mailbox = frameMailbox
        runner.onFrame = { [weak self] frame in
            mailbox.post(frame) { latest in
                Task { @MainActor in self?.frame = latest }
            }
        }
        runner.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        self.rom = image
        self.storage = storage
        self.runner = runner
        self.frame = emulator.frame
        phase = .ready
        runner.start(running: true)
        status = .running

        // Periodic autosave so a crash or force-quit loses little.
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosave() }
        }
    }

    private func shutdown() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        runner?.stop()
        runner = nil
    }

    private func applySettings() {
        guard let runner else { return }
        runner.speedMultiplier = settings.speed
        let persistence = settings.lcdPersistence
        runner.send { $0.configuration.lcdPersistence = persistence }
    }

    // MARK: - Keypad

    public func press(_ key: Key) { keypad.press(key) }
    public func release(_ key: Key) { keypad.release(key) }

    // MARK: - Lifecycle

    public func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if status == .paused && !settings.showDebugger { runner?.resume() }
        case .inactive, .background:
            autosave()
            if phase == .background { runner?.pause() }
        @unknown default:
            break
        }
    }

    /// Saves the full machine state (RAM, Flash archive, CPU and hardware).
    public func autosave() {
        guard let runner, let storage else { return }
        do {
            try runner.sync { emulator in Result { try storage.autosave(emulator) } }.get()
        } catch {
            message = "Autosave failed: \(error)"
        }
    }

    // MARK: - Memory management commands

    public func saveState(slot: Int = 1) {
        perform("State saved") { emulator, storage in
            try storage.writeState(emulator.saveState(), to: storage.slotURL(slot, for: emulator.rom))
        }
    }

    public func loadState(slot: Int = 1) {
        perform("State loaded") { emulator, storage in
            guard let state = try storage.readState(from: storage.slotURL(slot, for: emulator.rom)) else {
                throw EmulatorStateError.corrupt("no saved state in slot \(slot)")
            }
            try emulator.loadState(state)
        }
    }

    public func saveRAM() {
        perform("RAM saved") { emulator, storage in try storage.saveRAM(emulator) }
    }

    public func loadRAM() {
        perform("RAM loaded") { emulator, storage in
            guard try storage.loadRAM(into: emulator) else {
                throw EmulatorStateError.corrupt("no saved RAM image")
            }
        }
    }

    public func resetRAM() {
        perform("RAM cleared") { emulator, storage in try storage.resetRAM(emulator) }
    }

    public func resetArchive() {
        perform("Archive erased") { emulator, storage in
            try storage.resetFlash(emulator)
            emulator.reset()
        }
    }

    /// Hardware reset (like reinserting the batteries); memory is kept.
    public func resetCalculator() {
        perform("Calculator reset") { emulator, _ in emulator.reset() }
    }

    private func perform(_ success: String, _ work: @escaping (Emulator, PersistentStorage) throws -> Void) {
        guard let runner, let storage else { return }
        let result = runner.sync { emulator in Result { try work(emulator, storage) } }
        switch result {
        case .success: message = success
        case let .failure(error): message = String(describing: error)
        }
    }

    // MARK: - Debugger

    public func pause() {
        runner?.pause()
        status = .paused
    }

    public func resume() {
        runner?.resume()
        status = .running
    }

    public func step() {
        runner?.stepInstruction()
    }

    public func snapshot() -> DebugSnapshot? {
        runner?.sync { $0.debugSnapshot(upcomingCount: 16) }
    }

    public func memoryDump(at address: UInt16, rows: Int = 16) -> [(address: UInt16, bytes: [UInt8])] {
        runner?.sync { $0.memoryDump(from: address, rows: rows) } ?? []
    }

    public var breakpoints: [UInt16] {
        (runner?.sync { Array($0.debugger.breakpoints) } ?? []).sorted()
    }

    public func toggleBreakpoint(_ address: UInt16) {
        runner?.sync { $0.debugger.toggleBreakpoint(address) }
        objectWillChange.send()
    }

    public func clearBreakpoints() {
        runner?.sync { $0.debugger.clearBreakpoints() }
        objectWillChange.send()
    }
}

/// Forwards key presses to the emulated keypad matrix of the running
/// emulator. Nonisolated so SwiftUI gesture callbacks can use it directly.
public final class KeypadSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _runner: EmulatorRunner?

    var runner: EmulatorRunner? {
        get { lock.lock(); defer { lock.unlock() }; return _runner }
        set { lock.lock(); _runner = newValue; lock.unlock() }
    }

    public func press(_ key: Key) { runner?.setKey(key, pressed: true) }
    public func release(_ key: Key) { runner?.setKey(key, pressed: false) }
}

/// Coalesces frames from the emulation thread so the main thread receives
/// at most one pending update at a time (never a backlog).
final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: LCDFrame?
    private var deliveryScheduled = false

    func post(_ frame: LCDFrame, deliver: @escaping (LCDFrame) -> Void) {
        lock.lock()
        latest = frame
        if deliveryScheduled {
            lock.unlock()
            return
        }
        deliveryScheduled = true
        lock.unlock()
        DispatchQueue.main.async { [self] in
            lock.lock()
            let frame = latest
            latest = nil
            deliveryScheduled = false
            lock.unlock()
            if let frame { deliver(frame) }
        }
    }
}
#endif
