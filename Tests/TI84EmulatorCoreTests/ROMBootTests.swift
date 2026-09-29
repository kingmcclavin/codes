import XCTest
@testable import TI84EmulatorCore

final class ROMBootTests: XCTestCase {

    /// Boots the synthetic OS through the real reset path: boot page at
    /// 8000h → page 0 → hardware init → IM 1 interrupts → HALT idle loop.
    func testSyntheticROMBoots() throws {
        let emu = try SyntheticOS.emulator()
        XCTAssertEqual(emu.cpu.registers.pc, 0x8000)
        emu.run(seconds: 0.2)
        XCTAssertEqual(emu.mapper.banks[3], .ram(0))
        XCTAssertTrue(emu.lcd.displayOn)
        XCTAssertEqual(emu.cpu.interruptMode, 1)
        let frame = emu.frame
        XCTAssertTrue((0..<96).allSatisfy { frame.isOn(x: $0, y: 0) }, "top line drawn")
        XCTAssertTrue((0..<96).allSatisfy { frame.isOn(x: $0, y: 63) == ($0 % 2 == 0) })
        XCTAssertFalse(frame.isOn(x: 10, y: 30))
    }

    /// Boot test for the supplied TI-84 Plus ROM. Skipped when no ROM is
    /// available (bundled resource or TI84_ROM_PATH).
    func testSuppliedROMBoots() throws {
        guard ROMLoader.isBundledROMAvailable else {
            throw XCTSkip("No ROM supplied: add Sources/TI84EmulatorCore/Resources/ti84rom.rom or set TI84_ROM_PATH")
        }
        let rom = try ROMLoader.load()
        print("ROM: \(rom.model.rawValue), \(rom.size) bytes, SHA-256 \(rom.sha256)")
        rom.warnings.forEach { print("ROM warning: \($0)") }

        let emu = Emulator(rom: rom)
        var events: [String] = []
        emu.onEvent = { events.append($0) }

        // Give the boot code and OS time to initialise; a fresh RAM makes
        // TI-OS show "RAM cleared" before the home screen.
        let booted = emu.run(seconds: 10) {
            emu.lcd.displayOn && emu.cpu.interruptMode == 1 && emu.frame.pixels.contains { $0 > 0 }
        }
        emu.run(seconds: 1)
        print(emu.debugSnapshot().summary)
        print(emu.frame.asciiArt)
        events.prefix(20).forEach { print("event: \($0)") }

        XCTAssertTrue(booted, "the OS should turn the LCD on and draw something")
        XCTAssertEqual(emu.cpu.interruptMode, 1, "TI-OS runs in interrupt mode 1")
        XCTAssertTrue(emu.lcd.displayOn)
        XCTAssertEqual(emu.mapper.banks[0], .flash(0))

        // The OS should react to keys through its own keyboard scan.
        let before = emu.frame.pixels
        for key: Key in [.two, .add, .three] {
            emu.setKey(key, pressed: true)
            emu.run(seconds: 0.15)
            emu.setKey(key, pressed: false)
            emu.run(seconds: 0.15)
        }
        print(emu.frame.asciiArt)
        XCTAssertNotEqual(emu.frame.pixels, before, "typing should change the screen")
    }
}
