import SwiftUI
import UIKit

/// Bridges the SwiftUI app and the emulator core: locates the ROM, owns the
/// emulation runner, persists calculator memory and forwards key presses.
///
/// Note: no calculator behaviour lives here. Key presses go to the emulated keypad
/// matrix and the ROM does the rest.
@MainActor
final class EmulatorController: ObservableObject {
    enum Phase: Equatable {
        case needsROM
        case running
        case failed(String)
    }

    enum SpeedSetting: Double, CaseIterable, Identifiable {
        case half = 0.5, normal = 1, double = 2, quadruple = 4, unlimited = 0
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .half: return "50%"
            case .normal: return "100% (real)"
            case .double: return "200%"
            case .quadruple: return "400%"
            case .unlimited: return "Unlimited"
            }
        }
    }

    @Published private(set) var phase: Phase = .needsROM
    @Published private(set) var isPaused = false
    @Published private(set) var romDescription = ""
    @Published private(set) var romSourceLabel = ""
    @Published private(set) var speedPercent = 0
    @Published private(set) var breakpointAddress: UInt32?
    @Published var notice: String?

    @Published var speed: SpeedSetting {
        didSet { runner?.speed = speed.rawValue; defaults.set(speed.rawValue, forKey: "speed") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "haptics") }
    }
    @Published var debuggerEnabled: Bool {
        didSet { defaults.set(debuggerEnabled, forKey: "debugger") }
    }
    @Published var showPixelGrid: Bool {
        didSet { defaults.set(showPixelGrid, forKey: "pixelGrid") }
    }
    @Published var batteryLevel: Int {
        didSet {
            defaults.set(batteryLevel, forKey: "battery")
            let level = batteryLevel
            runner?.perform { $0.control.batteryLevel = level }
        }
    }

    let store = PersistentStore()
    private(set) var runner: EmulatorRunner?
    private var rom: ROMImage?
    private var userPaused = false
    private var statsTimer: Timer?
    private var autosaveTimer: Timer?
    private let defaults = UserDefaults.standard
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let saveQueue = DispatchQueue(label: "TI84CE.save", qos: .utility)

    static let snapshotSlots = [1, 2, 3]

    init() {
        speed = SpeedSetting(rawValue: defaults.object(forKey: "speed") as? Double ?? 1) ?? .normal
        hapticsEnabled = defaults.object(forKey: "haptics") as? Bool ?? true
        debuggerEnabled = defaults.bool(forKey: "debugger")
        showPixelGrid = defaults.bool(forKey: "pixelGrid")
        batteryLevel = defaults.object(forKey: "battery") as? Int ?? 4
        boot()
    }

    // MARK: ROM and power-on

    /// Finds the ROM (imported copy or bundled resource) and starts the calculator,
    /// resuming the autosaved state when it belongs to the same ROM.
    func boot() {
        guard let source = store.romLibrary.locate() else {
            phase = .needsROM
            return
        }
        do {
            let rom = try ROMImage(contentsOf: source.url)
            start(rom: rom, sourceLabel: source.label)
        } catch {
            phase = .failed("\(error)")
        }
    }

    func importROM(from url: URL) {
        do {
            try store.romLibrary.importROM(from: url)
            store.delete(store.autosaveURL)
            boot()
        } catch {
            phase = .failed("Could not import the ROM: \(error)")
        }
    }

    private func start(rom: ROMImage, sourceLabel: String) {
        runner?.stop()
        let emulator = Emulator(rom: rom)
        emulator.control.batteryLevel = batteryLevel
        if store.exists(store.autosaveURL) {
            do {
                try emulator.loadState(store.read(from: store.autosaveURL))
            } catch {
                notice = "Saved calculator memory could not be restored (\(error)); starting fresh."
                emulator.powerOn(clearRAM: true)
            }
        }
        let runner = EmulatorRunner(emulator: emulator)
        runner.speed = speed.rawValue
        runner.onStateChange = { [weak self] state in self?.runStateChanged(state) }
        runner.onDiagnostic = { [weak self] message in self?.notice = message }
        runner.start()
        self.runner = runner
        self.rom = rom
        romDescription = rom.summary
        romSourceLabel = sourceLabel
        phase = .running
        userPaused = false
        runner.resume()
        startTimers()
    }

    private func startTimers() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let runner = self.runner else { return }
                self.speedPercent = Int((runner.currentSpeed * 100).rounded())
            }
        }
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosaveInBackground() }
        }
    }

    // MARK: Keys

    func press(_ key: CalculatorKey) {
        if hapticsEnabled { haptic.impactOccurred(intensity: 0.6) }
        runner?.press(key)
    }

    func release(_ key: CalculatorKey) {
        runner?.release(key)
    }

    // MARK: Run control

    func togglePause() {
        guard let runner else { return }
        if isPaused {
            resumeExecution()
        } else {
            userPaused = true
            runner.pause()
        }
    }

    func resumeExecution() {
        guard let runner else { return }
        userPaused = false
        breakpointAddress = nil
        runner.perform { $0.cpu.ignoreBreakpointOnce = true }
        runner.resume()
    }

    private func runStateChanged(_ state: EmulatorRunner.RunState) {
        switch state {
        case .running:
            isPaused = false
            breakpointAddress = nil
        case .paused:
            isPaused = true
        case .breakpoint(let pc):
            isPaused = true
            userPaused = true
            breakpointAddress = pc
        }
    }

    /// Presses the calculator's reset: the ROM restarts, RAM contents are kept
    /// (the OS decides whether they are still valid).
    func resetCalculator() {
        runner?.perform { $0.powerOn(clearRAM: false) }
        notice = "Calculator reset."
    }

    /// Clears RAM and restarts, like removing the batteries. The archive (flash)
    /// is kept.
    func resetRAM() {
        runner?.perform { $0.powerOn(clearRAM: true) }
        store.delete(store.autosaveURL)
        notice = "RAM cleared."
    }

    /// Restores flash to the pristine ROM image (erasing the archive) and clears RAM.
    func eraseEverything() {
        guard let rom else { return }
        runner?.perform { $0.load(rom: rom) }
        store.delete(store.autosaveURL)
        notice = "Archive and RAM erased."
    }

    // MARK: Snapshots ("Save RAM" / "Load RAM")

    func saveSnapshot(slot: Int) {
        guard let runner else { return }
        let url = store.slotURL(slot)
        let store = self.store
        runner.query({ try? $0.saveState() }) { [weak self] state in
            guard let self, let state else { return }
            self.saveQueue.async {
                let message: String
                do {
                    try store.write(state, to: url)
                    message = "Saved to slot \(slot)."
                } catch {
                    message = "Save failed: \(error)"
                }
                Task { @MainActor [weak self] in self?.notice = message }
            }
        }
    }

    func loadSnapshot(slot: Int) {
        guard let runner else { return }
        let url = store.slotURL(slot)
        guard store.exists(url) else { notice = "Slot \(slot) is empty."; return }
        do {
            let state = try store.read(from: url)
            runner.perform { [weak self] emu in
                let message: String
                do {
                    try emu.loadState(state)
                    message = "Restored slot \(slot)."
                } catch {
                    message = "Restore failed: \(error)"
                }
                Task { @MainActor in self?.notice = message }
            }
        } catch {
            notice = "Restore failed: \(error)"
        }
    }

    func snapshotDate(slot: Int) -> Date? {
        store.modificationDate(store.slotURL(slot))
    }

    // MARK: Lifecycle / persistence

    func enterBackground() {
        guard let runner, phase == .running else { return }
        runner.pause()
        // Capture synchronously: the app may be suspended right after this returns.
        if let state = runner.sync({ try? $0.saveState() }) {
            try? store.write(state, to: store.autosaveURL)
        }
    }

    func enterForeground() {
        guard let runner, phase == .running, !userPaused else { return }
        runner.resume()
    }

    private func autosaveInBackground() {
        guard let runner, phase == .running else { return }
        let url = store.autosaveURL
        let store = self.store
        runner.query({ try? $0.saveState() }) { [weak self] state in
            guard let self, let state else { return }
            self.saveQueue.async { try? store.write(state, to: url) }
        }
    }
}
