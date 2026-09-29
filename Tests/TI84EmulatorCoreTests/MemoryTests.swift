import XCTest
@testable import TI84EmulatorCore

final class MemoryTests: XCTestCase {

    /// An emulator whose boot code just halts, with a recognisable byte at
    /// the start of every Flash page.
    private func makeEmulator(model: CalculatorModel = .ti84Plus, boot: ((inout Asm) -> Void)? = nil) throws -> Emulator {
        var rom = SyntheticROM(model: model)
        for page in 0..<rom.profile.flashPages { rom.bytes[page * 0x4000] = UInt8(page) }
        rom.place(page: rom.profile.bootPage, logicalBank: 2, boot ?? { a in a.di(); a.halt() })
        return Emulator(rom: try rom.image())
    }

    // MARK: Bus

    func testFlatBusReadWrite() {
        let (bus, ram) = MemoryBus.flatRAM()
        bus.write(0x1234, value: 0xAB)
        bus.write(0xFFFF, value: 0xCD)
        XCTAssertEqual(bus.read(0x1234), 0xAB)
        XCTAssertEqual(ram[physical: 0xFFFF], 0xCD)
        XCTAssertEqual(bus.read16(0x1234), 0x00AB)
    }

    func testReadOnlyBankIgnoresWrites() {
        let bus = MemoryBus()
        let rom = RAM(pageCount: 1, fill: 0x3C)
        bus.map(bank: 0, read: rom.pagePointer(0), write: nil, device: nil)
        bus.write(0x0010, value: 0x00)
        XCTAssertEqual(bus.read(0x0010), 0x3C)
    }

    // MARK: ROM loading

    func testROMValidation() throws {
        XCTAssertThrowsError(try ROMImage(data: Data(count: 1234))) { error in
            XCTAssertEqual(error as? ROMError, .invalidSize(1234))
        }
        XCTAssertThrowsError(try ROMImage(data: Data(repeating: 0xFF, count: 0x400000))) { error in
            guard case .unsupportedModel = error as? ROMError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try ROMImage(data: Data(repeating: 0xFF, count: 0x100000))) { error in
            XCTAssertEqual(error as? ROMError, .missingBootCode)
        }
        var rom = SyntheticROM()
        rom.place([0x76], page: 0x3F)
        let image = try rom.image()
        XCTAssertEqual(image.model, .ti84Plus)
        XCTAssertEqual(image.profile.bootPage, 0x3F)
        XCTAssertFalse(image.warnings.isEmpty, "blank OS page should warn")
        XCTAssertEqual(image.sha256.count, 64)

        var se = SyntheticROM(model: .ti84PlusSE)
        se.place([0x76], page: 0x7F)
        XCTAssertEqual(try se.image().model, .ti84PlusSE)
    }

    func testROMLoaderFromFileAndData() throws {
        var rom = SyntheticROM()
        rom.place([0x76], page: 0x3F)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).rom")
        try Data(rom.bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ROMLoader.load(.file(url)).size, 0x100000)
        XCTAssertEqual(try ROMLoader.load(.data(Data(rom.bytes))).crc32, CRC32.checksum(rom.bytes))
        XCTAssertThrowsError(try ROMLoader.load(.file(url.appendingPathExtension("missing"))))
    }

    func testChecksums() {
        XCTAssertEqual(SHA256.hexDigest(Array("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testROMImageIsNeverModified() throws {
        let emu = try makeEmulator()
        let original = emu.rom.bytes
        emu.flash.unlocked = true
        emu.flash.write(physical: 0xAAA, value: 0xAA)
        emu.flash.write(physical: 0x555, value: 0x55)
        emu.flash.write(physical: 0xAAA, value: 0xA0)
        emu.flash.write(physical: 0x10, value: 0x00)
        XCTAssertEqual(emu.flash.storage[0x10], 0x00)
        XCTAssertEqual(emu.rom.bytes, original)
    }

    // MARK: Mapping

    func testResetMapping() throws {
        let emu = try makeEmulator()
        XCTAssertEqual(emu.mapper.banks, [.flash(0), .flash(0x3E), .flash(0x3F), .flash(0x3F)])
        XCTAssertEqual(emu.cpu.registers.pc, 0x8000)
        XCTAssertEqual(emu.memory.read(0x0000), 0x00)
        XCTAssertEqual(emu.memory.read(0x4000), 0xFF, "certificate page is read-protected while locked")
    }

    func testBankSwitchingMode0() throws {
        let emu = try makeEmulator()
        emu.io.write(port: 0x04, value: 0x06)            // mode 0
        emu.io.write(port: 0x06, value: 0x05)            // bank A = Flash page 5
        emu.io.write(port: 0x07, value: 0x81)            // bank B = RAM page 1
        emu.io.write(port: 0x05, value: 0x02)            // bank C = RAM page 2
        XCTAssertEqual(emu.mapper.banks, [.flash(0), .flash(5), .ram(1), .ram(2)])
        XCTAssertEqual(emu.memory.read(0x4000), 5)
        emu.memory.write(0x8000, value: 0x11)
        emu.memory.write(0xC000, value: 0x22)
        XCTAssertEqual(emu.ram[physical: 1 * 0x4000], 0x11)
        XCTAssertEqual(emu.ram[physical: 2 * 0x4000], 0x22)
        XCTAssertEqual(emu.io.read(port: 0x06), 0x05)
    }

    func testBankSwitchingMode1() throws {
        let emu = try makeEmulator()
        emu.io.write(port: 0x06, value: 0x0B)
        emu.io.write(port: 0x07, value: 0x80)
        emu.io.write(port: 0x04, value: 0x07)            // mode 1
        XCTAssertEqual(emu.mapper.banks, [.flash(0), .flash(0x0A), .flash(0x0B), .ram(0)])
    }

    func testFlashIsWriteProtectedWhenLocked() throws {
        let emu = try makeEmulator()
        emu.io.write(port: 0x04, value: 0x06)
        emu.io.write(port: 0x06, value: 0x02)
        let before = emu.memory.read(0x4000)
        for (address, value): (UInt16, UInt8) in [(0x4AAA, 0xAA), (0x4555, 0x55), (0x4AAA, 0xA0), (0x4000, 0x00)] {
            emu.memory.write(address, value: value)
        }
        XCTAssertEqual(emu.memory.read(0x4000), before)
        XCTAssertFalse(emu.flash.isDirty)
    }

    func testFlashProgramAndEraseWhenUnlocked() throws {
        let emu = try makeEmulator()
        emu.flash.unlocked = true
        emu.io.write(port: 0x04, value: 0x06)
        emu.io.write(port: 0x06, value: 0x04)             // page 4 = physical 0x10000 (sector 1)
        let program: [(UInt16, UInt8)] = [(0x4AAA, 0xAA), (0x4555, 0x55), (0x4AAA, 0xA0), (0x4100, 0x5A)]
        for (address, value) in program { emu.memory.write(address, value: value) }
        XCTAssertEqual(emu.memory.read(0x4100), 0x5A)
        XCTAssertTrue(emu.flash.isDirty)
        // Programming can only clear bits.
        for (address, value) in program.dropLast() { emu.memory.write(address, value: value) }
        emu.memory.write(0x4100, value: 0xA5)
        XCTAssertEqual(emu.flash.state, .error)
        emu.memory.write(0x4000, value: 0xF0)              // reset
        XCTAssertEqual(emu.memory.read(0x4100), 0x00)
        // Sector erase (the 64 KB sector holding pages 4-7).
        let erase: [(UInt16, UInt8)] = [(0x4AAA, 0xAA), (0x4555, 0x55), (0x4AAA, 0x80),
                                        (0x4AAA, 0xAA), (0x4555, 0x55), (0x4000, 0x30)]
        for (address, value) in erase { emu.memory.write(address, value: value) }
        XCTAssertEqual(emu.memory.read(0x4100), 0xFF)
        XCTAssertEqual(emu.flash.storage[0x0000], 0x00, "sector 0 untouched")
        XCTAssertEqual(emu.flash.storage[0x20000], 0x08, "sector 2 untouched")
    }

    func testProtectedSectorCannotBeErased() throws {
        let emu = try makeEmulator()
        emu.flash.unlocked = true
        let bootPhysical = 0x3F * 0x4000
        let erase: [(Int, UInt8)] = [(0xAAA, 0xAA), (0x555, 0x55), (0xAAA, 0x80),
                                     (0xAAA, 0xAA), (0x555, 0x55), (bootPhysical, 0x30)]
        for (address, value) in erase { emu.flash.write(physical: address, value: value) }
        XCTAssertNotEqual(emu.flash.storage[bootPhysical], 0xFF)
    }

    func testPartialRemapPorts27And28() throws {
        let emu = try makeEmulator()
        emu.io.write(port: 0x04, value: 0x06)
        emu.io.write(port: 0x07, value: 0x05)             // bank B = Flash 5
        emu.io.write(port: 0x05, value: 0x03)             // bank C = RAM 3
        emu.ram[physical: 0 * 0x4000 + 0x3FFF] = 0x99     // RAM page 0, last byte
        emu.ram[physical: 1 * 0x4000] = 0x77              // RAM page 1, first byte
        emu.io.write(port: 0x27, value: 0x01)             // top 64 bytes -> RAM 0
        emu.io.write(port: 0x28, value: 0x01)             // bottom 64 bytes of 8000 -> RAM 1
        XCTAssertEqual(emu.memory.read(0xFFFF), 0x99)
        XCTAssertEqual(emu.memory.read(0x8000), 0x77)
        XCTAssertEqual(emu.memory.read(0x8040), 0xFF)     // past the remap: Flash page 5 data
        emu.memory.write(0xFFC0, value: 0x42)
        XCTAssertEqual(emu.ram[physical: 0x3FC0], 0x42)
    }

    /// Only code running from a privileged page may unlock Flash with the
    /// nop/nop/im 1/di/out (14h),a sequence.
    func testPrivilegedFlashUnlockSequence() throws {
        let emu = try makeEmulator { a in
            a.ldA(0x01)
            a.nop(); a.nop(); a.im1(); a.di(); a.out(0x14)
            a.halt()
        }
        emu.run(seconds: 0.001)
        XCTAssertTrue(emu.flash.unlocked)
        XCTAssertEqual(emu.io.read(port: 0x02) & 0x04, 0x04)
        XCTAssertNotEqual(emu.memory.read(0x4000), 0xFF, "certificate page readable once unlocked")
    }

    func testUnprivilegedFlashUnlockIsIgnored() throws {
        // The boot code jumps to the same sequence placed in RAM.
        let emu = try makeEmulator { a in
            a.ldA(0x06); a.out(0x04)        // memory mode 0: RAM page 0 at C000h
            a.ldHL(0xC000)
            for byte: UInt8 in [0x3E, 0x01, 0x00, 0x00, 0xED, 0x56, 0xF3, 0xD3, 0x14, 0x76] {
                a.db(0x36, byte)            // LD (HL),n
                a.db(0x23)                  // INC HL
            }
            a.db(0xC3); a.dw(0xC000)        // JP C000h
        }
        emu.run(seconds: 0.001)
        XCTAssertFalse(emu.flash.unlocked)
    }
}
