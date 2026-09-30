import XCTest
@testable import EmulatorCore

/// A bare machine for instruction-level tests: programs are placed in RAM and the
/// CPU is started in ADL mode (or Z80 mode) at the program's address.
final class TestMachine {
    let emu = Emulator()
    var cpu: CPU { emu.cpu }
    static let origin: UInt32 = 0xD00100

    init(_ program: [UInt8], adl: Bool = true, at origin: UInt32 = TestMachine.origin) {
        load(program, at: origin)
        cpu.adl = adl
        var r = cpu.registers
        r.pc = adl ? origin : origin & 0xFFFF
        r.mbase = UInt8(origin >> 16)
        r.spl = 0xD1_0000
        r.sps = 0xF000
        cpu.registers = r
        emu.scheduler.setCPUClock(hz: 48_000_000)
    }

    func load(_ bytes: [UInt8], at address: UInt32) {
        for (i, b) in bytes.enumerated() { emu.bus.poke(address + UInt32(i), value: b) }
    }

    /// Executes `count` instructions.
    func step(_ count: Int = 1) {
        for _ in 0..<count { emu.step() }
    }

    /// Steps until PC reaches `address` (or a limit is hit).
    func run(until address: UInt32, limit: Int = 10_000) {
        var n = 0
        while cpu.registers.pc != address && n < limit { emu.step(); n += 1 }
        XCTAssertEqual(cpu.registers.pc, address, "did not reach target PC")
    }

    var r: Registers {
        get { cpu.registers }
        set { cpu.registers = newValue }
    }

    func peek(_ a: UInt32) -> UInt8 { emu.bus.peek(a) }
}

/// Builds a synthetic 4 MiB flash image whose boot code runs `program`.
/// Byte 0 is DI (the ROM validator expects eZ80 boot code); the program follows
/// a `JP.LIL` to 0x000100 so it executes in ADL mode.
func syntheticROM(program: [UInt8]) throws -> ROMImage {
    var image = [UInt8](repeating: 0xFF, count: ROMImage.flashSize)
    let boot: [UInt8] = [0xF3, 0x5B, 0xC3, 0x00, 0x01, 0x00]      // di / jp.lil $000100
    image.replaceSubrange(0..<boot.count, with: boot)
    image.replaceSubrange(0x100..<(0x100 + program.count), with: program)
    return try ROMImage(data: image)
}

/// Locates the real TI-84 Plus CE ROM for boot tests, if one is available locally.
/// Set TI84CE_ROM to a path, or place the dump at TI84CE.swiftpm/Resources/ti84ce.rom.
func locateRealROM() -> URL? {
    if let env = ProcessInfo.processInfo.environment["TI84CE_ROM"] {
        return URL(fileURLWithPath: env)
    }
    let here = URL(fileURLWithPath: #filePath)
    let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidate = root.appendingPathComponent("TI84CE.swiftpm/Resources/ti84ce.rom")
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
}
