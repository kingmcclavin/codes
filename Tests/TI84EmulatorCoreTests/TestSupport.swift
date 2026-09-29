import Foundation
@testable import TI84EmulatorCore

/// Minimal Z80 assembler for test programs: raw bytes plus labels for
/// jumps/calls, so tests stay readable without an external toolchain.
struct Asm {
    let origin: UInt16
    private(set) var bytes: [UInt8] = []
    private var labels: [String: UInt16] = [:]
    private var fixups: [(position: Int, label: String, relative: Bool)] = []

    init(origin: UInt16) { self.origin = origin }

    var pc: UInt16 { origin &+ UInt16(bytes.count) }

    mutating func db(_ values: UInt8...) { bytes += values }
    mutating func db(_ values: [UInt8]) { bytes += values }
    mutating func dw(_ value: UInt16) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }

    mutating func label(_ name: String) { labels[name] = pc }

    private mutating func abs16(_ label: String) {
        fixups.append((bytes.count, label, false))
        bytes += [0, 0]
    }

    private mutating func rel8(_ label: String) {
        fixups.append((bytes.count, label, true))
        bytes.append(0)
    }

    mutating func jp(_ l: String) { db(0xC3); abs16(l) }
    mutating func jpZ(_ l: String) { db(0xCA); abs16(l) }
    mutating func jpNZ(_ l: String) { db(0xC2); abs16(l) }
    mutating func call(_ l: String) { db(0xCD); abs16(l) }
    mutating func jr(_ l: String) { db(0x18); rel8(l) }
    mutating func jrNZ(_ l: String) { db(0x20); rel8(l) }
    mutating func jrZ(_ l: String) { db(0x28); rel8(l) }
    mutating func jrNC(_ l: String) { db(0x30); rel8(l) }
    mutating func jrC(_ l: String) { db(0x38); rel8(l) }
    mutating func djnz(_ l: String) { db(0x10); rel8(l) }
    mutating func ldHL(_ l: String) { db(0x21); abs16(l) }

    // Common instructions
    mutating func ldA(_ n: UInt8) { db(0x3E, n) }
    mutating func ldB(_ n: UInt8) { db(0x06, n) }
    mutating func ldC(_ n: UInt8) { db(0x0E, n) }
    mutating func ldHL(_ nn: UInt16) { db(0x21); dw(nn) }
    mutating func ldDE(_ nn: UInt16) { db(0x11); dw(nn) }
    mutating func ldBC(_ nn: UInt16) { db(0x01); dw(nn) }
    mutating func ldSP(_ nn: UInt16) { db(0x31); dw(nn) }
    mutating func out(_ port: UInt8) { db(0xD3, port) }      // OUT (n),A
    mutating func inA(_ port: UInt8) { db(0xDB, port) }      // IN A,(n)
    mutating func ldMemA(_ nn: UInt16) { db(0x32); dw(nn) }  // LD (nn),A
    mutating func ldAMem(_ nn: UInt16) { db(0x3A); dw(nn) }  // LD A,(nn)
    mutating func halt() { db(0x76) }
    mutating func ei() { db(0xFB) }
    mutating func di() { db(0xF3) }
    mutating func im1() { db(0xED, 0x56) }
    mutating func ret() { db(0xC9) }
    mutating func nop() { db(0x00) }

    func assembled() -> [UInt8] {
        var out = bytes
        for fixup in fixups {
            guard let target = labels[fixup.label] else { fatalError("undefined label \(fixup.label)") }
            if fixup.relative {
                let next = Int(origin) + fixup.position + 1
                let delta = Int(target) - next
                precondition((-128...127).contains(delta), "jump out of range to \(fixup.label)")
                out[fixup.position] = UInt8(bitPattern: Int8(delta))
            } else {
                out[fixup.position] = UInt8(target & 0xFF)
                out[fixup.position + 1] = UInt8(target >> 8)
            }
        }
        return out
    }
}

/// A CPU on 64 KB of flat RAM with a recording I/O device on every port.
final class TestMachine {
    let cpu: CPU
    let memory: MemoryBus
    let io: IOBus
    let ports = RecordingPorts()

    init(program: [UInt8], at origin: UInt16 = 0x0000) {
        let (bus, _) = MemoryBus.flatRAM()
        memory = bus
        io = IOBus()
        io.map(0...255, to: ports)
        cpu = CPU(memory: bus, io: io)
        memory.load(program, at: origin)
        cpu.registers.pc = origin
        cpu.registers.sp = 0xFF00
    }

    convenience init(_ build: (inout Asm) -> Void) {
        var asm = Asm(origin: 0)
        build(&asm)
        self.init(program: asm.assembled())
    }

    /// Steps until a HALT is reached (or the step budget runs out).
    @discardableResult
    func runUntilHalt(maxSteps: Int = 100_000) -> Int {
        var steps = 0
        while !cpu.halted && steps < maxSteps {
            cpu.step()
            steps += 1
        }
        return steps
    }

    var r: Registers { cpu.registers }
}

final class RecordingPorts: IODevice {
    var inputs = [UInt8](repeating: 0xFF, count: 256)
    var writes: [(port: UInt8, value: UInt8)] = []
    var reads: [UInt8] = []

    func read(port: UInt8) -> UInt8 {
        reads.append(port)
        return inputs[Int(port)]
    }

    func write(port: UInt8, value: UInt8) {
        writes.append((port, value))
    }
}

/// Builds synthetic ROM images with test code placed in specific Flash pages.
/// They exercise the real boot path (reset → boot page at 8000h) without
/// needing TI's copyrighted software.
struct SyntheticROM {
    var bytes: [UInt8]
    let profile: HardwareProfile

    init(model: CalculatorModel = .ti84Plus) {
        profile = HardwareProfile.profile(for: model)
        bytes = [UInt8](repeating: 0xFF, count: profile.flashSize)
    }

    mutating func place(_ code: [UInt8], page: Int, offset: Int = 0) {
        let start = page * 0x4000 + offset
        bytes.replaceSubrange(start..<(start + code.count), with: code)
    }

    /// Places code assembled for the logical address it will run at.
    mutating func place(page: Int, logicalBank: Int, _ build: (inout Asm) -> Void) {
        var asm = Asm(origin: UInt16(logicalBank * 0x4000))
        build(&asm)
        place(asm.assembled(), page: page)
    }

    func image() throws -> ROMImage {
        try ROMImage(data: Data(bytes), model: profile.model)
    }
}

extension Emulator {
    /// Runs until `condition` holds or `seconds` of emulated time elapse.
    @discardableResult
    func run(seconds: Double, until condition: () -> Bool) -> Bool {
        let end = clock.now + UInt64(seconds * Double(EmulatorClock.ticksPerSecond))
        while clock.now < end {
            if condition() { return true }
            run(forTicks: EmulatorClock.ticksPerSecond / 1000)
        }
        return condition()
    }
}

/// A tiny hand-written "operating system" that uses the hardware the way
/// TI-OS does: boot page at 8000h jumps to page 0, which sets memory mode 0,
/// initialises the T6A04, enables the timer and ON interrupts in IM 1, and
/// halts. The ISR counts timer ticks, scans key group 1 and records ON
/// presses.
///
/// RAM variables (RAM page 0 at C000h):
///   C000h/C001h  timer-1 interrupt count (16-bit)
///   C002h        last port 01h read with group 1 selected
///   C003h        set to 1 when an ON-key interrupt is seen
enum SyntheticOS {
    static let counter: UInt16 = 0xC000
    static let keyState: UInt16 = 0xC002
    static let onFlag: UInt16 = 0xC003

    static func rom(model: CalculatorModel = .ti84Plus) -> SyntheticROM {
        var rom = SyntheticROM(model: model)

        // Boot page, running at 8000h after reset.
        rom.place(page: rom.profile.bootPage, logicalBank: 2) { a in
            a.di()
            a.db(0xC3); a.dw(0x0100)                     // JP 0100h (Flash page 0)
        }

        var os = Asm(origin: 0)
        os.db(0xC3); os.dw(0x0100)                       // 0000: JP init
        while os.pc < 0x38 { os.nop() }
        // 0038: interrupt service routine
        os.db(0xF5)                                      // PUSH AF
        os.db(0xE5)                                      // PUSH HL
        os.inA(0x04)
        os.db(0xCB, 0x4F)                                // BIT 1,A (timer 1)
        os.jrZ("notTimer")
        os.db(0x2A); os.dw(counter)                      // LD HL,(counter)
        os.db(0x23)                                      // INC HL
        os.db(0x22); os.dw(counter)                      // LD (counter),HL
        os.label("notTimer")
        os.db(0xCB, 0x47)                                // BIT 0,A (ON key)
        os.jrZ("notOn")
        os.ldA(0x01); os.ldMemA(onFlag)
        os.label("notOn")
        os.ldA(0xFD); os.out(0x01)                       // select key group 1
        os.nop(); os.nop()
        os.inA(0x01)
        os.ldMemA(keyState)
        os.ldA(0xFF); os.out(0x01)
        os.ldA(0x08); os.out(0x03)                       // acknowledge all
        os.ldA(0x0B); os.out(0x03)                       // re-enable ON + timer 1
        os.db(0xE1)                                      // POP HL
        os.db(0xF1)                                      // POP AF
        os.ei()
        os.db(0xED, 0x4D)                                // RETI
        while os.pc < 0x100 { os.nop() }
        // 0100: init
        os.ldA(0x06); os.out(0x04)                       // memory mode 0, slowest timer
        os.ldA(0x00); os.out(0x05)                       // RAM page 0 at C000h
        os.ldA(0x81); os.out(0x07)                       // RAM page 1 at 8000h
        os.ldSP(0xFFF0)
        os.ldHL(0); os.db(0x22); os.dw(counter)
        os.ldA(0xFF); os.ldMemA(keyState)
        os.ldA(0x00); os.ldMemA(onFlag)
        // LCD: 8-bit mode, column auto-increment, display on, contrast 30h.
        for command: UInt8 in [0x01, 0x07, 0x03, 0xF0, 0x40, 0x80, 0x20] {
            os.ldA(command); os.out(0x10)
        }
        // Row 0: 12 bytes of FFh (a full line across the visible 96 pixels).
        os.ldB(12)
        os.label("row0")
        os.ldA(0xFF); os.out(0x11)
        os.djnz("row0")
        // Row 63: alternating pixels.
        os.ldA(0xBF); os.out(0x10)
        os.ldA(0x20); os.out(0x10)
        os.ldB(12)
        os.label("row63")
        os.ldA(0xAA); os.out(0x11)
        os.djnz("row63")
        os.im1()
        os.ldA(0x0B); os.out(0x03)                       // ON + timer 1 interrupts
        os.ei()
        os.label("idle")
        os.halt()
        os.jr("idle")
        rom.place(os.assembled(), page: 0)
        return rom
    }

    static func emulator(configuration: EmulatorConfiguration = EmulatorConfiguration()) throws -> Emulator {
        Emulator(rom: try rom().image(), configuration: configuration)
    }
}
