import Foundation

/// Zilog eZ80 CPU core as used in the TI-84 Plus CE.
///
/// The eZ80 runs in either Z80 mode (ADL = 0: 16-bit registers and addresses, with
/// MBASE supplying address bits 23..16) or ADL mode (ADL = 1: 24-bit). Individual
/// instructions can override the data width (L) and immediate width (IL) with the
/// .SIS/.LIS/.SIL/.LIL suffix bytes (0x40/0x49/0x52/0x5B).
///
/// Instruction decoding lives in `Instructions.swift`.
public final class CPU {
    /// The register file (`registers` is the public name; `r` is used internally).
    var r = Registers()
    public var registers: Registers {
        get { r }
        set { r = newValue }
    }

    unowned let bus: MemoryBus
    unowned let scheduler: Scheduler

    public var halted = false
    public var adl = false
    public var madl = false
    public var ief1 = false
    public var ief2 = false
    public var im: UInt8 = 0
    /// Set by EI: interrupts are not accepted until one more instruction executes.
    var iefWait = false

    /// Maskable interrupt request line, driven by the interrupt controller.
    public var irq = false
    /// Non-maskable interrupt request (edge; cleared when serviced).
    public var nmi = false

    // Per-instruction decode state.
    var L = false          // data/register width is 24-bit
    var IL = false         // immediate / jump width is 24-bit
    var suffixed = false
    var prefix = 0         // 0 = HL, 2 = IX (DD), 3 = IY (FD)
    /// Address of the first byte of the instruction being executed.
    public private(set) var instructionPC: UInt32 = 0

    // Debugging.
    public var breakpoints = Set<UInt32>() { didSet { hasBreakpoints = !breakpoints.isEmpty } }
    private var hasBreakpoints = false
    /// Suppresses the breakpoint check for exactly one instruction (resume from a hit).
    public var ignoreBreakpointOnce = false
    public private(set) var breakpointHit = false
    public private(set) var lastUnsupported: String?
    public var unsupportedCount = 0
    public var onUnsupported: ((String) -> Void)?
    /// Called before each instruction when set (slow; tracing only).
    public var traceHook: ((CPU) -> Void)?

    public init(bus: MemoryBus, scheduler: Scheduler) {
        self.bus = bus
        self.scheduler = scheduler
    }

    /// Stops execution before the next instruction, as if a breakpoint was hit
    /// (callable from `traceHook`).
    public func triggerBreak() {
        breakpointHit = true
    }

    public func reset() {
        r = Registers()
        halted = false
        adl = false
        madl = false
        ief1 = false
        ief2 = false
        iefWait = false
        im = 0
        nmi = false
        L = false; IL = false; suffixed = false; prefix = 0
        instructionPC = 0
        breakpointHit = false
        lastUnsupported = nil
        unsupportedCount = 0
    }

    // MARK: - Execution

    /// Executes instructions until the scheduler's stop point, a breakpoint, or HALT.
    public func execute() {
        breakpointHit = false
        while scheduler.cycles < scheduler.stopCycles {
            let blockIRQ = iefWait
            iefWait = false
            if nmi {
                nmi = false
                serviceNMI()
            } else if irq && ief1 && !blockIRQ {
                serviceIRQ()
            }
            if halted {
                // Nothing to do until an interrupt: fast-forward to the next event.
                scheduler.cycles = scheduler.stopCycles
                return
            }
            if hasBreakpoints {
                if !ignoreBreakpointOnce && breakpoints.contains(r.pc) {
                    breakpointHit = true
                    return
                }
                ignoreBreakpointOnce = false
            }
            if let hook = traceHook {
                hook(self)
                if breakpointHit { return }
            }
            step()
        }
    }

    /// Runs the CPU alone for approximately `cycles` cycles (no peripheral events are
    /// processed; use `Emulator.run` for full-system execution).
    public func run(cycles: Int) {
        let target = scheduler.cycles + Int64(cycles)
        scheduler.runLimit = target
        scheduler.stopCycles = target
        while scheduler.cycles < target && !breakpointHit {
            execute()
            if halted { break }
        }
    }

    /// Executes exactly one instruction (servicing a pending interrupt first).
    public func step() {
        instructionPC = r.pc
        L = adl; IL = adl; suffixed = false; prefix = 0
        scheduler.cycles &+= 1
        var op = fetchOpcode()
        while true {
            switch op {
            case 0xDD: prefix = 2; op = fetchOpcode(); continue
            case 0xFD: prefix = 3; op = fetchOpcode(); continue
            case 0x40 where prefix == 0: setSuffix(l: false, il: false); op = fetchOpcode(); continue
            case 0x49 where prefix == 0: setSuffix(l: true, il: false); op = fetchOpcode(); continue
            case 0x52 where prefix == 0: setSuffix(l: false, il: true); op = fetchOpcode(); continue
            case 0x5B where prefix == 0: setSuffix(l: true, il: true); op = fetchOpcode(); continue
            default: break
            }
            break
        }
        executeMain(op)
    }

    /// Single-step used by the debugger: services an interrupt if one is due,
    /// otherwise executes one instruction.
    public func debugStep() {
        let blockIRQ = iefWait
        iefWait = false
        if nmi { nmi = false; serviceNMI(); return }
        if irq && ief1 && !blockIRQ { serviceIRQ(); return }
        if halted { return }
        step()
    }

    @inline(__always) private func setSuffix(l: Bool, il: Bool) {
        L = l; IL = il; suffixed = true
    }

    // MARK: - Interrupts

    func serviceIRQ() {
        halted = false
        ief1 = false
        ief2 = false
        scheduler.cycles &+= 2
        let vector: UInt32
        if im == 2 {
            // Vector table at {I, bus byte}; the CE bus floats high.
            L = adl || madl
            let tableAddr = (UInt32(r.i) << 8) | 0xFF
            vector = readWordAt(tableAddr)
        } else {
            vector = 0x38                       // IM 0 (RST 38h on the bus) and IM 1
        }
        interruptCall(vector)
    }

    func serviceNMI() {
        halted = false
        ief2 = ief1
        ief1 = false
        scheduler.cycles &+= 2
        interruptCall(0x66)
    }

    private func interruptCall(_ vector: UInt32) {
        suffixed = false; prefix = 0
        if madl {
            // Mixed-memory mode: behaves like CALL.IL, saving the ADL mode byte.
            L = true; IL = true
            mixedCall(vector)
        } else {
            L = adl; IL = adl
            push(r.pc)
            r.pc = mask(vector, adl)
        }
    }

    // MARK: - Width helpers

    @inline(__always) func mask(_ v: UInt32, _ wide: Bool) -> UInt32 {
        wide ? v & 0xFF_FFFF : v & 0xFFFF
    }

    /// Forms a 24-bit bus address from a register value in the given mode.
    @inline(__always) func address(_ v: UInt32, _ wide: Bool) -> UInt32 {
        wide ? v & 0xFF_FFFF : (UInt32(r.mbase) << 16) | (v & 0xFFFF)
    }

    /// Writes `v` into a multi-byte register honoring the current data width.
    /// 16-bit writes (Z80 mode or .S suffix) zero the upper byte; the TI-84 Plus CE
    /// OS relies on this (e.g. `ld.sis de,(nn)` followed by 24-bit arithmetic).
    @inline(__always) func put(_ reg: inout UInt32, _ v: UInt32) {
        reg = L ? v & 0xFF_FFFF : v & 0xFFFF
    }

    // MARK: - Fetch

    @inline(__always) func fetch() -> UInt8 {
        let v = bus.read(address(r.pc, adl))
        r.pc = mask(r.pc &+ 1, adl)
        return v
    }

    @inline(__always) func fetchOpcode() -> UInt8 {
        r.r = (r.r & 0x80) | ((r.r &+ 1) & 0x7F)
        return fetch()
    }

    /// Fetches a 16- or 24-bit immediate according to IL.
    @inline(__always) func fetchWord() -> UInt32 {
        var v = UInt32(fetch())
        v |= UInt32(fetch()) << 8
        if IL { v |= UInt32(fetch()) << 16 }
        return v
    }

    /// Fetches a signed displacement, sign-extended to 32 bits.
    @inline(__always) func fetchDisplacement() -> UInt32 {
        UInt32(bitPattern: Int32(Int8(bitPattern: fetch())))
    }

    // MARK: - Data memory (addressed with width L)

    @inline(__always) func readByte(_ a: UInt32) -> UInt8 {
        bus.read(address(a, L))
    }

    @inline(__always) func writeByte(_ a: UInt32, _ v: UInt8) {
        bus.write(address(a, L), value: v)
    }

    /// Reads a 16/24-bit little-endian word (width L).
    func readWordAt(_ a: UInt32) -> UInt32 {
        var v = UInt32(readByte(a))
        v |= UInt32(readByte(a &+ 1)) << 8
        if L { v |= UInt32(readByte(a &+ 2)) << 16 }
        return v
    }

    func writeWordAt(_ a: UInt32, _ v: UInt32) {
        writeByte(a, UInt8(truncatingIfNeeded: v))
        writeByte(a &+ 1, UInt8(truncatingIfNeeded: v >> 8))
        if L { writeByte(a &+ 2, UInt8(truncatingIfNeeded: v >> 16)) }
    }

    // MARK: - Stack

    @inline(__always) func pushByte(_ v: UInt8, long: Bool) {
        if long {
            r.spl = (r.spl &- 1) & 0xFF_FFFF
            bus.write(r.spl, value: v)
        } else {
            r.sps = (r.sps &- 1) & 0xFFFF
            bus.write(UInt32(r.mbase) << 16 | r.sps, value: v)
        }
    }

    @inline(__always) func popByte(long: Bool) -> UInt8 {
        if long {
            let v = bus.read(r.spl)
            r.spl = (r.spl &+ 1) & 0xFF_FFFF
            return v
        } else {
            let v = bus.read(UInt32(r.mbase) << 16 | r.sps)
            r.sps = (r.sps &+ 1) & 0xFFFF
            return v
        }
    }

    func push(_ v: UInt32) {
        if L { pushByte(UInt8(truncatingIfNeeded: v >> 16), long: true) }
        pushByte(UInt8(truncatingIfNeeded: v >> 8), long: L)
        pushByte(UInt8(truncatingIfNeeded: v), long: L)
    }

    func pop() -> UInt32 {
        var v = UInt32(popByte(long: L))
        v |= UInt32(popByte(long: L)) << 8
        if L { v |= UInt32(popByte(long: L)) << 16 }
        return v
    }

    var sp: UInt32 {
        get { L ? r.spl : r.sps }
        set { if L { r.spl = newValue & 0xFF_FFFF } else { r.sps = newValue & 0xFFFF } }
    }

    // MARK: - Control flow

    /// Transfers control; `wide` becomes the new ADL mode.
    @inline(__always) func jump(_ target: UInt32, wide: Bool) {
        adl = wide
        r.pc = mask(target, wide)
    }

    /// CALL / RST: pushes the return address (mixed-mode frame when suffixed).
    func call(_ target: UInt32) {
        if suffixed {
            mixedCall(target)
        } else {
            push(r.pc)
            jump(target, wide: IL)
        }
    }

    /// eZ80 mixed-memory-mode call: PC goes to SPL or SPS depending on the target
    /// mode and a mode byte ((MADL << 1) | ADL) is pushed on SPL.
    func mixedCall(_ target: UInt32) {
        let pc = r.pc
        let longStack = IL || (L && !adl)
        if adl { pushByte(UInt8(truncatingIfNeeded: pc >> 16), long: true) }
        pushByte(UInt8(truncatingIfNeeded: pc >> 8), long: longStack)
        pushByte(UInt8(truncatingIfNeeded: pc), long: longStack)
        pushByte((madl ? 2 : 0) | (adl ? 1 : 0), long: true)
        jump(target, wide: IL)
    }

    func ret() {
        if suffixed {
            let wasADL = popByte(long: true) & 1 != 0
            var target: UInt32
            if adl {
                target = UInt32(popByte(long: true))
                target |= UInt32(popByte(long: true)) << 8
                if wasADL { target |= UInt32(popByte(long: true)) << 16 }
            } else {
                target = UInt32(popByte(long: false))
                target |= UInt32(popByte(long: false)) << 8
                if wasADL { target |= UInt32(popByte(long: true)) << 16 }
            }
            jump(target, wide: wasADL)
        } else {
            jump(pop(), wide: adl)
        }
    }

    // MARK: - I/O

    @inline(__always) func portIn(_ port: UInt32) -> UInt8 {
        scheduler.cycles &+= 2
        return bus.io.read(UInt16(truncatingIfNeeded: port))
    }

    @inline(__always) func portOut(_ port: UInt32, _ v: UInt8) {
        scheduler.cycles &+= 2
        bus.io.write(UInt16(truncatingIfNeeded: port), value: v)
    }

    // MARK: - Diagnostics

    func unsupported(_ bytes: [UInt8]) {
        let hex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        let msg = String(format: "Unsupported opcode: %@\nPC: 0x%06X (ADL=%d)", hex, instructionPC, adl ? 1 : 0)
        lastUnsupported = msg
        unsupportedCount += 1
        onUnsupported?(msg)
    }

    // MARK: - State

    public struct State: Codable, Equatable {
        public var registers: Registers
        public var adl, madl, ief1, ief2, halted, iefWait: Bool
        public var im: UInt8
    }

    public var state: State {
        get { State(registers: r, adl: adl, madl: madl, ief1: ief1, ief2: ief2, halted: halted, iefWait: iefWait, im: im) }
        set {
            r = newValue.registers; adl = newValue.adl; madl = newValue.madl
            ief1 = newValue.ief1; ief2 = newValue.ief2; halted = newValue.halted
            iefWait = newValue.iefWait; im = newValue.im
        }
    }
}
