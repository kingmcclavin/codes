import XCTest
@testable import EmulatorCore
@testable import Platform

final class PlatformTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ti84ce-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testPersistentStoreRoundTrip() throws {
        let store = PersistentStore(root: tempDir())
        let rom = try syntheticROM(program: [0x21, 0x00, 0x00, 0xD0, 0x34, 0x18, 0xFD])
        let emu = Emulator(rom: rom)
        emu.run(cycles: 10_000)
        try store.write(emu.saveState(), to: store.autosaveURL)
        XCTAssertTrue(store.exists(store.autosaveURL))

        let restored = Emulator(rom: rom)
        try restored.loadState(store.read(from: store.autosaveURL))
        XCTAssertEqual(restored.bus.peek(0xD00000), emu.bus.peek(0xD00000))
        XCTAssertEqual(restored.cpu.registers, emu.cpu.registers)
        store.delete(store.autosaveURL)
        XCTAssertFalse(store.exists(store.autosaveURL))
    }

    func testROMImportValidatesAndKeepsPrivateCopy() throws {
        let dir = tempDir()
        let library = ROMLibrary(storageDirectory: dir)
        XCTAssertNil(library.locate(bundle: Bundle(for: PlatformTests.self)))

        let bad = dir.appendingPathComponent("bad.rom")
        try Data(repeating: 0, count: 10).write(to: bad)
        XCTAssertThrowsError(try library.importROM(from: bad))

        let good = dir.appendingPathComponent("good.rom")
        try Data(try syntheticROM(program: [0x00]).data).write(to: good)
        try library.importROM(from: good)
        XCTAssertEqual(library.locate(bundle: .main), .imported(library.importedROMURL))
    }

    func testRunnerRunsOnItsOwnThreadAndHoldsShortTaps() throws {
        let rom = try syntheticROM(program: [0x21, 0x00, 0x00, 0xD0, 0x34, 0x18, 0xFD])
        let runner = EmulatorRunner(emulator: Emulator(rom: rom))
        runner.minimumKeyHold = 0.5
        runner.start()
        runner.resume()
        Thread.sleep(forTimeInterval: 0.2)

        // A tap shorter than the minimum hold is still seen as held.
        runner.press(.enter)
        runner.release(.enter)
        let heldNow = runner.sync { $0.keypad.isPressed(CalculatorKey.enter.position) }
        XCTAssertTrue(heldNow)
        Thread.sleep(forTimeInterval: 0.8)
        let heldLater = runner.sync { $0.keypad.isPressed(CalculatorKey.enter.position) }
        XCTAssertFalse(heldLater)

        runner.pause()
        let cycles = runner.sync { $0.scheduler.cycles }
        XCTAssertGreaterThan(cycles, 0, "emulation advanced in the background")
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(runner.sync { $0.scheduler.cycles }, cycles, "paused")
        runner.stop()
    }

    func testDebugSnapshotReportsState() throws {
        let emu = Emulator(rom: try syntheticROM(program: [0x00]))
        emu.run(cycles: 100)
        let s = emu.debugSnapshot(memoryAddress: 0x000100, ioPort: 0x5000)
        XCTAssertTrue(s.adl)
        XCTAssertEqual(s.memory.count, 256)
        XCTAssertEqual(s.disassembly.count, 12)
        XCTAssertTrue(s.disassembly[0].isCurrent)
    }
}
