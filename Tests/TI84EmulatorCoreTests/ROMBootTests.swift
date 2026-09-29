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

        // After a reset the boot code validates the OS and hands over; TI-OS
        // then initialises RAM and powers down, waiting for ON (as a real
        // calculator does after its batteries are inserted).
        emu.run(seconds: 3)
        XCTAssertTrue(events.contains("Flash unlocked"), "boot code should use the privileged unlock sequence")
        XCTAssertEqual(emu.cpu.interruptMode, 1, "TI-OS runs in interrupt mode 1")
        XCTAssertTrue(emu.cpu.iff1)

        func tap(_ key: Key) {
            emu.setKey(key, pressed: true)
            emu.run(seconds: 0.1)
            emu.setKey(key, pressed: false)
            emu.run(seconds: 0.2)
        }

        tap(.on)
        let booted = emu.run(seconds: 3) { emu.lcd.displayOn && emu.frame.pixels.contains { $0 > 0 } }
        print(emu.frame.asciiArt)
        XCTAssertTrue(booted, "ON should turn the calculator on and the OS should draw")

        // Clear the home screen, then compute 2+3*4 and check the OS drew
        // "14" right-aligned on the result line.
        tap(.clear)
        tap(.clear)
        for key: Key in [.two, .add, .three, .multiply, .four, .enter] { tap(key) }
        emu.run(seconds: 0.5)
        print(emu.frame.asciiArt)
        print(emu.debugSnapshot().summary)
        XCTAssertEqual(glyphs(in: emu.frame, textRow: 1, columns: 14...15), glyphs14,
                       "TI-OS should display 14 as the result of 2+3*4")
    }

    /// Pixels of the 6×8 character cells at (textRow, columns) on the home
    /// screen (glyphs occupy rows 1–7 of each cell).
    private func glyphs(in frame: LCDFrame, textRow: Int, columns: ClosedRange<Int>) -> [Bool] {
        var out: [Bool] = []
        for y in (textRow * 8 + 1)...(textRow * 8 + 7) {
            for column in columns {
                for x in (column * 6)..<(column * 6 + 6) where x < LCDFrame.width {
                    out.append(frame.isOn(x: x, y: y))
                }
            }
        }
        return out
    }

    /// "14" as TI-OS draws it right-aligned in the large font (x 84–95).
    private let glyphs14: [Bool] = [
        ".#......#...",
        "##.....##...",
        ".#....#.#...",
        ".#...#..#...",
        ".#...#####..",
        ".#......#...",
        "###.....#...",
    ].flatMap { $0.map { $0 == "#" } }
}
