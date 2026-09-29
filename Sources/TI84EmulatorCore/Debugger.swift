/// Breakpoints, execution history and state inspection for developers.
public final class Debugger {
    public private(set) var breakpoints: Set<UInt16> = []
    private var breakpointMap = [Bool](repeating: false, count: 0x10000)

    /// Record the PCs of recently executed instructions.
    public var historyEnabled = false {
        didSet { if !historyEnabled { history.removeAll(keepingCapacity: true) } }
    }
    public let historyCapacity = 64
    private var history: [UInt16] = []
    private var historyNext = 0

    /// Set from any thread-confined caller to stop `Emulator.run` early.
    public var pauseRequested = false
    /// Resuming from a breakpoint must not immediately re-trigger it.
    var skipBreakpointOnce: UInt16?

    public init() {}

    /// The emulator uses its slower instruction-by-instruction loop only
    /// while something needs it.
    var isActive: Bool { !breakpoints.isEmpty || historyEnabled }

    public func addBreakpoint(_ address: UInt16) {
        breakpoints.insert(address)
        breakpointMap[Int(address)] = true
    }

    public func removeBreakpoint(_ address: UInt16) {
        breakpoints.remove(address)
        breakpointMap[Int(address)] = false
    }

    public func toggleBreakpoint(_ address: UInt16) {
        if breakpoints.contains(address) { removeBreakpoint(address) } else { addBreakpoint(address) }
    }

    public func clearBreakpoints() {
        for address in breakpoints { breakpointMap[Int(address)] = false }
        breakpoints.removeAll()
    }

    @inline(__always)
    func shouldBreak(at pc: UInt16) -> Bool {
        guard breakpointMap[Int(pc)] else {
            skipBreakpointOnce = nil
            return false
        }
        if skipBreakpointOnce == pc {
            skipBreakpointOnce = nil
            return false
        }
        skipBreakpointOnce = pc
        return true
    }

    @inline(__always)
    func recordStep(pc: UInt16) {
        guard historyEnabled else { return }
        if history.count < historyCapacity {
            history.append(pc)
        } else {
            history[historyNext] = pc
        }
        historyNext = (historyNext + 1) % historyCapacity
    }

    /// Recently executed instruction addresses, oldest first.
    public var recentPCs: [UInt16] {
        history.count < historyCapacity ? history : Array(history[historyNext...] + history[..<historyNext])
    }
}

/// A point-in-time view of the machine for debugging UIs and logs.
public struct DebugSnapshot: Equatable, Sendable {
    public var registers: Registers
    public var cycles: UInt64
    public var iff1: Bool
    public var iff2: Bool
    public var interruptMode: UInt8
    public var halted: Bool
    public var irqLine: Bool
    public var currentInstruction: DisassembledInstruction
    public var upcoming: [DisassembledInstruction]
    public var stack: [UInt16]
    public var banks: [PhysicalPage]
    public var memoryMode: Int
    public var interruptMask: UInt8
    public var pendingInterrupts: InterruptSource
    public var cpuSpeed: EmulatorClock.Speed
    public var flashUnlocked: Bool
    public var keyGroupMask: UInt8
    public var pressedKeys: [Key]
    public var lcdOn: Bool
    public var lcdCursor: (row: Int, column: Int)
    public var lcdContrast: UInt8
    public var lcdEightBit: Bool
    public var portsRead: [UInt8]
    public var portsWritten: [UInt8]
    public var emulatedSeconds: Double

    public static func == (a: DebugSnapshot, b: DebugSnapshot) -> Bool {
        a.registers == b.registers && a.cycles == b.cycles
    }

    /// Multi-line register dump.
    public var summary: String {
        let r = registers
        return """
        PC=\(hex(r.pc)) SP=\(hex(r.sp)) AF=\(hex(r.af)) BC=\(hex(r.bc)) DE=\(hex(r.de)) HL=\(hex(r.hl))
        IX=\(hex(r.ix)) IY=\(hex(r.iy)) AF'=\(hex(r.altAF)) BC'=\(hex(r.altBC)) DE'=\(hex(r.altDE)) HL'=\(hex(r.altHL))
        I=\(hex(r.i)) R=\(hex(r.r)) Flags=\(r.flagString) IFF1=\(iff1 ? 1 : 0) IM=\(interruptMode)\(halted ? " HALT" : "")
        Opcode: \(currentInstruction.hexBytes)  \(currentInstruction.text)
        Cycles=\(cycles) Banks=\(banks.map(\.description).joined(separator: " | "))
        """
    }
}

extension Emulator {
    /// Captures the machine state for inspection.
    public func debugSnapshot(upcomingCount: Int = 12) -> DebugSnapshot {
        let read: (UInt16) -> UInt8 = { [memory] in memory.peek($0) }
        let listing = Disassembler.disassemble(from: cpu.registers.pc, count: max(1, upcomingCount), read: read)
        var stack: [UInt16] = []
        for i in 0..<8 { stack.append(memory.read16Peek(cpu.registers.sp &+ UInt16(i * 2))) }
        return DebugSnapshot(
            registers: cpu.registers, cycles: cpu.cycles, iff1: cpu.iff1, iff2: cpu.iff2,
            interruptMode: cpu.interruptMode, halted: cpu.halted, irqLine: cpu.irqLine,
            currentInstruction: listing[0], upcoming: listing, stack: stack,
            banks: mapper.banks, memoryMode: Int(mapper.port04 & 1),
            interruptMask: interrupts.enableMask, pendingInterrupts: interrupts.pending,
            cpuSpeed: clock.speed, flashUnlocked: flash.unlocked,
            keyGroupMask: keyboard.groupMask, pressedKeys: keyboard.pressedKeys,
            lcdOn: lcd.displayOn, lcdCursor: (lcd.row, lcd.column), lcdContrast: lcd.contrast,
            lcdEightBit: lcd.eightBitMode,
            portsRead: io.lastRead, portsWritten: io.lastWritten,
            emulatedSeconds: emulatedSeconds)
    }

    /// Side-effect-free hex dump of logical memory.
    public func memoryDump(from address: UInt16, rows: Int = 16) -> [(address: UInt16, bytes: [UInt8])] {
        (0..<rows).map { row in
            let base = address &+ UInt16(truncatingIfNeeded: row * 16)
            return (base, (0..<16).map { memory.peek(base &+ UInt16($0)) })
        }
    }
}

extension MemoryBus {
    func read16Peek(_ address: UInt16) -> UInt16 {
        UInt16(peek(address)) | UInt16(peek(address &+ 1)) << 8
    }
}
