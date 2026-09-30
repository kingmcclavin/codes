import XCTest
@testable import EmulatorCore

/// Boots the real TI-84 Plus CE ROM. Skipped when no ROM is available (ROMs are
/// not distributed with the project); set TI84CE_ROM or place the dump at
/// TI84CE.swiftpm/Resources/ti84ce.rom.
final class ROMBootTests: XCTestCase {
    private func realROM() throws -> ROMImage {
        guard let url = locateRealROM() else { throw XCTSkip("No TI-84 Plus CE ROM available") }
        return try ROMImage(contentsOf: url)
    }

    private func press(_ emu: Emulator, _ keys: [CalculatorKey]) {
        for k in keys {
            emu.setKey(k, pressed: true)
            emu.run(seconds: 0.2)
            emu.setKey(k, pressed: false)
            emu.run(seconds: 0.3)
        }
    }

    private func ramContains(_ emu: Emulator, _ pattern: [UInt8]) -> Bool {
        let ram = emu.ram.contents
        for o in 0...(ram.count - pattern.count) where ram[o] == pattern[0] && Array(ram[o..<o + pattern.count]) == pattern {
            return true
        }
        return false
    }

    func testBootReachesOperatingSystem() throws {
        let rom = try realROM()
        XCTAssertEqual(rom.data.count, 0x400000)
        let emu = Emulator(rom: rom)
        XCTAssertEqual(emu.cpu.registers.pc, 0, "reset vector")
        XCTAssertFalse(emu.cpu.adl, "the eZ80 resets into Z80 mode")

        emu.run(seconds: 9)

        XCTAssertEqual(emu.cpu.unsupportedCount, 0, emu.cpu.lastUnsupported ?? "")
        XCTAssertTrue(emu.cpu.adl, "OS runs in ADL mode")
        XCTAssertTrue(emu.cpu.ief1, "interrupts enabled")
        XCTAssertEqual(emu.scheduler.cpuHz, 48_000_000, "OS selects 48 MHz")
        XCTAssertEqual(emu.lcd.control, 0x92D, "16 bpp 5:6:5 BGR, powered")
        XCTAssertEqual(emu.lcd.upbase, 0xD40000)
        XCTAssertTrue(emu.panel.displayVisible)

        // The OS drew its screen: the dark status bar (rows 0-27) is clearly darker
        // than the body of the home screen.
        let f = emu.lcd.frame
        func brightness(_ rows: Range<Int>) -> Double {
            var sum = 0
            for y in rows { for x in 0..<320 { let i = (y * 320 + x) * 4; sum += Int(f.pixels[i]) + Int(f.pixels[i + 1]) + Int(f.pixels[i + 2]) } }
            return Double(sum) / Double(rows.count * 320 * 3)
        }
        XCTAssertLessThan(brightness(0..<28), 150)
        XCTAssertGreaterThan(brightness(120..<200), 200)
        print("Boot state:", emu.debugDescription)
    }

    func testKeypadDrivenCalculation() throws {
        let emu = Emulator(rom: try realROM())
        emu.run(seconds: 9)
        let fortyTwo: [UInt8] = [0x00, 0x81, 0x42, 0x00, 0x00, 0x00, 0x00, 0x00]  // TI float 42
        XCTAssertFalse(ramContains(emu, fortyTwo))
        press(emu, [.clear, .k7, .multiply, .k6, .enter])
        emu.run(seconds: 1)
        XCTAssertTrue(ramContains(emu, fortyTwo), "the ROM computed 7*6 = 42")
        XCTAssertEqual(emu.cpu.unsupportedCount, 0)
    }

    func testSaveStateResumesDeterministically() throws {
        let rom = try realROM()
        let a = Emulator(rom: rom)
        a.run(seconds: 9)
        let snapshot = try Emulator.decode(Emulator.encode(a.saveState()))

        let b = Emulator(rom: rom)
        try b.loadState(snapshot)
        XCTAssertEqual(b.cpu.registers, a.cpu.registers)

        a.run(seconds: 1)
        b.run(seconds: 1)
        XCTAssertEqual(b.cpu.registers, a.cpu.registers, "both machines follow the same path")
        XCTAssertEqual(b.scheduler.cycles, a.scheduler.cycles)
        XCTAssertEqual(b.lcd.frame.pixels, a.lcd.frame.pixels)
    }
}

/// Save states and system behaviour that do not need the real ROM.
final class EmulatorStateTests: XCTestCase {
    func testSaveAndRestoreSyntheticMachine() throws {
        // Program: increment a RAM counter forever.
        let program: [UInt8] = [0x21, 0x00, 0x00, 0xD0,   // ld hl,$D00000
                                0x34,                     // loop: inc (hl)
                                0x18, 0xFD]               // jr loop
        let rom = try syntheticROM(program: program)
        let emu = Emulator(rom: rom)
        emu.run(cycles: 5_000)
        let saved = try emu.saveState()
        let counter = emu.bus.peek(0xD00000)
        XCTAssertNotEqual(counter, 0)

        emu.run(cycles: 5_000)
        XCTAssertNotEqual(emu.bus.peek(0xD00000), counter)

        try emu.loadState(saved)
        XCTAssertEqual(emu.bus.peek(0xD00000), counter, "RAM restored")
        XCTAssertEqual(emu.cpu.state, saved.cpu)
    }

    func testStateRejectsDifferentROM() throws {
        let a = Emulator(rom: try syntheticROM(program: [0x00]))
        let b = Emulator(rom: try syntheticROM(program: [0x76]))
        XCTAssertThrowsError(try b.loadState(a.saveState()))
    }

    func testFlashChangesArePersistedInState() throws {
        let rom = try syntheticROM(program: [0x00])
        let emu = Emulator(rom: rom)
        for (a, v) in [(0xAAA, 0xAA), (0x555, 0x55), (0xAAA, 0xA0), (0x3F0000, 0x12)] as [(UInt32, UInt8)] {
            emu.bus.write(a, value: v)
        }
        let state = try Emulator.decode(Emulator.encode(emu.saveState()))
        XCTAssertEqual(state.memory.flashDiff.count, 1)
        let fresh = Emulator(rom: rom)
        try fresh.loadState(state)
        XCTAssertEqual(fresh.bus.peek(0x3F0000), 0x12)
    }
}
