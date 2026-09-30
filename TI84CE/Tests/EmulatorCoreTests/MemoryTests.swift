import XCTest
@testable import EmulatorCore

final class MemoryTests: XCTestCase {

    func testRAMReadWriteAndMirroring() {
        let emu = Emulator()
        emu.bus.write(0xD00000, value: 0x12)
        emu.bus.write(0xD657FF, value: 0x34)
        XCTAssertEqual(emu.bus.read(0xD00000), 0x12)
        XCTAssertEqual(emu.bus.read(0xD657FF), 0x34)
        // RAM repeats every 512 KiB inside D00000-DFFFFF.
        XCTAssertEqual(emu.bus.read(0xD80000), 0x12)
        // The gap after the 0x65800-byte RAM is unmapped.
        emu.bus.write(0xD70000, value: 0x99)
        XCTAssertEqual(emu.bus.read(0xD70000), 0x00)
    }

    func testUnmappedSpaceReadsZero() {
        let emu = Emulator()
        emu.bus.write(0x500000, value: 0x77)
        XCTAssertEqual(emu.bus.read(0x500000), 0)
        XCTAssertEqual(emu.bus.read(0xEA0000), 0)
    }

    func testFlashIsWriteProtectedAgainstPlainStores() throws {
        let rom = try syntheticROM(program: [0x00])
        let emu = Emulator(rom: rom)
        let before = emu.bus.read(0x100000)
        emu.bus.write(0x100000, value: 0x00)
        XCTAssertEqual(emu.bus.read(0x100000), before, "a store is only a command cycle")
        XCTAssertEqual(emu.flash.mode, .read)
    }

    func testFlashProgramSequenceOnlyClearsBits() throws {
        let emu = Emulator(rom: try syntheticROM(program: [0x00]))
        func program(_ a: UInt32, _ v: UInt8) {
            emu.bus.write(0xAAA, value: 0xAA)
            emu.bus.write(0x555, value: 0x55)
            emu.bus.write(0xAAA, value: 0xA0)
            emu.bus.write(a, value: v)
        }
        program(0x300000, 0xA5)
        XCTAssertEqual(emu.bus.read(0x300000), 0xA5)
        program(0x300000, 0x5A)                  // cannot set bits back to 1
        XCTAssertEqual(emu.bus.read(0x300000), 0x00)
        XCTAssertTrue(emu.flash.dirty)
    }

    func testFlashSectorEraseAndStatusPolling() throws {
        let emu = Emulator(rom: try syntheticROM(program: [0x00]))
        emu.flash.bytes[0x310000] = 0x00
        emu.flash.bytes[0x31FFFF] = 0x00
        emu.flash.bytes[0x320000] = 0x00
        for (a, v) in [(0xAAA, 0xAA), (0x555, 0x55), (0xAAA, 0x80), (0xAAA, 0xAA), (0x555, 0x55)] as [(UInt32, UInt8)] {
            emu.bus.write(a, value: v)
        }
        emu.bus.write(0x315555, value: 0x30)     // erase the 64 KiB sector
        // Embedded-erase status: DQ7 = 1 (done), DQ3 = 0, DQ6 steady.
        XCTAssertEqual(emu.bus.read(0x310000), 0x80)
        XCTAssertEqual(emu.bus.read(0x310000), 0x80)
        XCTAssertEqual(emu.bus.read(0x310000), 0x80)
        XCTAssertEqual(emu.bus.read(0x310000), 0xFF, "back to array reads")
        XCTAssertEqual(emu.bus.read(0x31FFFF), 0xFF)
        XCTAssertEqual(emu.bus.read(0x320000), 0x00, "neighbouring sector untouched")
    }

    func testBootSectorsCannotBeErased() throws {
        let emu = Emulator(rom: try syntheticROM(program: [0x00]))
        for (a, v) in [(0xAAA, 0xAA), (0x555, 0x55), (0xAAA, 0x80), (0xAAA, 0xAA), (0x555, 0x55), (0x000, 0x30)] as [(UInt32, UInt8)] {
            emu.bus.write(a, value: v)
        }
        for _ in 0..<3 { _ = emu.bus.read(0) }
        XCTAssertEqual(emu.bus.read(0), 0xF3, "boot code survives")
    }

    func testFlashAutoselectAndReset() throws {
        let emu = Emulator(rom: try syntheticROM(program: [0x00]))
        emu.bus.write(0xAAA, value: 0xAA)
        emu.bus.write(0x555, value: 0x55)
        emu.bus.write(0xAAA, value: 0x90)
        XCTAssertEqual(emu.bus.read(0x000), 0xC2)
        emu.bus.write(0x000, value: 0xF0)
        XCTAssertEqual(emu.bus.read(0x000), 0xF3)
    }

    func testMemoryMapperDecodesMMIOToPorts() {
        let m = MemoryMapper()
        XCTAssertEqual(m.decode(0x123456), .flash(offset: 0x123456))
        XCTAssertEqual(m.decode(0xD40000), .ram(offset: 0x40000))
        XCTAssertEqual(m.decode(0xE30018), .io(port: 0x4018))   // LCD control
        XCTAssertEqual(m.decode(0xF00004), .io(port: 0x5004))   // interrupt enable
        XCTAssertEqual(m.decode(0xF50010), .io(port: 0xA010))   // keypad data
        XCTAssertEqual(m.decode(0xF80018), .io(port: 0xD018))   // SPI data
        XCTAssertEqual(m.decode(0xE50000), .unmapped)
    }

    func testMMIOAndPortIOReachTheSameRegister() {
        let emu = Emulator()
        emu.bus.write(0xF00004, value: 0x19)                    // interrupt enable via MMIO
        XCTAssertEqual(emu.io.read(0x5004), 0x19)               // ... read back via port
    }

    func testROMImageValidation() {
        XCTAssertThrowsError(try ROMImage(data: [UInt8](repeating: 0, count: 100)))
        XCTAssertThrowsError(try ROMImage(data: [UInt8](repeating: 0, count: ROMImage.flashSize)), "not eZ80 boot code")
        var small = [UInt8](repeating: 0xFF, count: 0x40000)
        small[0] = 0xF3
        let rom = try? ROMImage(data: small)
        XCTAssertEqual(rom?.data.count, ROMImage.flashSize, "short dumps are padded with erased flash")
    }

    func testSHA256Digest() {
        XCTAssertEqual(SHA256.hexDigest(Array("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
