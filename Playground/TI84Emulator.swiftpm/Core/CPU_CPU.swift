/// Cycle-counted Zilog Z80 core (the TI-84 Plus runs a Z80-compatible core
/// inside its ASIC at 6 MHz or 15 MHz).
///
/// The implementation covers the full documented and undocumented instruction
/// set: all prefixes (CB, ED, DD, FD, DDCB, FDCB), IXH/IXL/IYH/IYL register
/// halves, SLL, the undocumented DDCB register copies, the ED mirrors of NEG,
/// RETN and IM, and the undocumented X/Y flags including MEMPTR (WZ)
/// behaviour.
///
/// Memory goes through `MemoryBus` and port I/O through `IOBus`; the CPU has no
/// knowledge of TI-84 specific hardware.
public final class CPU {
    public var registers = Registers()
    public let memory: MemoryBus
    public let io: IOBus

    public var halted = false
    public var iff1 = false
    public var iff2 = false
    public var interruptMode: UInt8 = 0

    /// Total T-states executed since power-on. Never wraps in practice.
    public var cycles: UInt64 = 0

    /// Level-triggered maskable interrupt line, driven by the interrupt controller.
    public var irqLine = false
    /// Edge-triggered non-maskable interrupt request.
    public var nmiPending = false
    /// Value the hardware places on the data bus during interrupt acknowledge.
    /// Nothing drives the bus on the TI-84, so it floats high.
    public var interruptDataBus: UInt8 = 0xFF

    /// EI (and prefix bytes) delay interrupt acceptance by one instruction.
    var interruptInhibit = false

    /// Cycle count at which the current `run(until:)` returns.
    private var runLimit: UInt64 = 0

    /// Receives reports about unusual situations (undefined ED opcodes etc.).
    public var diagnosticHandler: ((CPUDiagnostic) -> Void)?

    /// Opcode currently executing (first byte, prefix included), for debugging.
    public internal(set) var lastOpcodePC: UInt16 = 0

    // Flag lookup tables (sign, zero, X/Y and parity) shared by all CPUs.
    let sz53 = UnsafePointer(FlagTables.shared.sz53)
    let sz53p = UnsafePointer(FlagTables.shared.sz53p)
    let parity = UnsafePointer(FlagTables.shared.parity)

    public init(memory: MemoryBus, io: IOBus) {
        self.memory = memory
        self.io = io
        reset()
    }

    /// Hardware reset. The Z80 only defines PC, I, R, IFFs and IM; the other
    /// registers come up as FFFFh on real silicon.
    public func reset() {
        registers = Registers()
        halted = false
        iff1 = false
        iff2 = false
        interruptMode = 0
        interruptInhibit = false
        nmiPending = false
    }

    // MARK: - Execution

    /// Executes one instruction (or services one pending interrupt, or burns
    /// one HALT cycle). Returns the number of T-states consumed.
    @discardableResult
    public func step() -> Int {
        let start = cycles
        if nmiPending {
            nmiPending = false
            acceptNMI()
        } else if irqLine && iff1 && !interruptInhibit {
            acceptInterrupt()
        } else if halted {
            // The CPU keeps executing NOPs internally while halted.
            incrementR()
            cycles &+= 4
            interruptInhibit = false
        } else {
            interruptInhibit = false
            executeInstruction()
        }
        return Int(cycles &- start)
    }

    /// Runs until at least `cycles` T-states have elapsed.
    public func run(cycles count: Int) {
        run(until: cycles &+ UInt64(max(0, count)))
    }

    /// Runs until the cycle counter reaches `target` (or an earlier limit set
    /// through `limitRun(toCycle:)` while running). While halted with no
    /// pending interrupt, time skips forward in one step instead of spinning.
    public func run(until target: UInt64) {
        runLimit = target
        while cycles < runLimit {
            if halted && !nmiPending && !(irqLine && iff1) {
                // Jump straight to the limit, keeping R and the 4-cycle
                // granularity of the internal NOPs.
                let nops = (runLimit - cycles + 3) / 4
                registers.r = (registers.r & 0x80) | UInt8(truncatingIfNeeded: (UInt64(registers.r) &+ nops) & 0x7F)
                cycles &+= nops &* 4
                interruptInhibit = false
                break
            }
            step()
        }
        runLimit = 0
    }

    /// Lowers the target of the `run(until:)` call in progress, e.g. when an
    /// I/O write schedules a hardware event sooner, or to pause execution
    /// after the current instruction (`limitRun(toCycle: 0)`).
    public func limitRun(toCycle cycle: UInt64) {
        if cycle < runLimit { runLimit = cycle }
    }

    /// Whether `run(until:)` would do nothing but idle in HALT.
    public var isIdleHalted: Bool {
        halted && !nmiPending && !(irqLine && iff1)
    }

    // MARK: - Interrupts

    func acceptInterrupt() {
        leaveHalt()
        iff1 = false
        iff2 = false
        incrementR()
        switch interruptMode {
        case 2:
            push(registers.pc)
            let vector = UInt16(registers.i) << 8 | UInt16(interruptDataBus)
            registers.pc = read16(vector)
            registers.wz = registers.pc
            cycles &+= 19
        case 1:
            push(registers.pc)
            registers.pc = 0x0038
            registers.wz = 0x0038
            cycles &+= 13
        default:
            // IM 0: the data bus byte is executed as an instruction. Only RST
            // opcodes are meaningful here; anything else (including the
            // floating FFh bus of the TI-84, which is RST 38h) is treated as
            // its RST equivalent when it is one, otherwise as RST 38h.
            let op = interruptDataBus
            let target: UInt16 = (op & 0xC7) == 0xC7 ? UInt16(op & 0x38) : 0x0038
            push(registers.pc)
            registers.pc = target
            registers.wz = target
            cycles &+= 13
        }
    }

    func acceptNMI() {
        leaveHalt()
        iff2 = iff1
        iff1 = false
        incrementR()
        push(registers.pc)
        registers.pc = 0x0066
        registers.wz = 0x0066
        cycles &+= 11
    }

    @inline(__always)
    func leaveHalt() {
        if halted {
            halted = false
        }
    }

    // MARK: - Bus helpers

    @inline(__always)
    func incrementR() {
        registers.r = (registers.r & 0x80) | ((registers.r &+ 1) & 0x7F)
    }

    @inline(__always)
    func fetchOpcode() -> UInt8 {
        let op = memory.fetchOpcode(registers.pc)
        registers.pc &+= 1
        incrementR()
        return op
    }

    @inline(__always)
    func fetch8() -> UInt8 {
        let v = memory.read(registers.pc)
        registers.pc &+= 1
        return v
    }

    @inline(__always)
    func fetch16() -> UInt16 {
        let lo = fetch8()
        let hi = fetch8()
        return UInt16(hi) << 8 | UInt16(lo)
    }

    @inline(__always)
    func read8(_ address: UInt16) -> UInt8 {
        memory.read(address)
    }

    @inline(__always)
    func write8(_ address: UInt16, _ value: UInt8) {
        memory.write(address, value: value)
    }

    @inline(__always)
    func read16(_ address: UInt16) -> UInt16 {
        let lo = memory.read(address)
        let hi = memory.read(address &+ 1)
        return UInt16(hi) << 8 | UInt16(lo)
    }

    @inline(__always)
    func write16(_ address: UInt16, _ value: UInt16) {
        memory.write(address, value: UInt8(truncatingIfNeeded: value))
        memory.write(address &+ 1, value: UInt8(truncatingIfNeeded: value >> 8))
    }

    @inline(__always)
    func push(_ value: UInt16) {
        registers.sp &-= 1
        memory.write(registers.sp, value: UInt8(truncatingIfNeeded: value >> 8))
        registers.sp &-= 1
        memory.write(registers.sp, value: UInt8(truncatingIfNeeded: value))
    }

    @inline(__always)
    func pop() -> UInt16 {
        let lo = memory.read(registers.sp)
        registers.sp &+= 1
        let hi = memory.read(registers.sp)
        registers.sp &+= 1
        return UInt16(hi) << 8 | UInt16(lo)
    }

    @inline(__always)
    func portIn(_ port: UInt16) -> UInt8 {
        io.read(busAddress: port)
    }

    @inline(__always)
    func portOut(_ port: UInt16, _ value: UInt8) {
        io.write(busAddress: port, value: value)
    }

    func report(_ diagnostic: CPUDiagnostic) {
        diagnosticHandler?(diagnostic)
    }

    // MARK: - State

    public var state: CPUState {
        get {
            CPUState(registers: registers, iff1: iff1, iff2: iff2, interruptMode: interruptMode,
                     halted: halted, interruptInhibit: interruptInhibit, cycles: cycles)
        }
        set {
            registers = newValue.registers
            iff1 = newValue.iff1
            iff2 = newValue.iff2
            interruptMode = newValue.interruptMode
            halted = newValue.halted
            interruptInhibit = newValue.interruptInhibit
            cycles = newValue.cycles
        }
    }
}

/// Serializable snapshot of the CPU.
public struct CPUState: Codable, Equatable, Sendable {
    public var registers: Registers
    public var iff1: Bool
    public var iff2: Bool
    public var interruptMode: UInt8
    public var halted: Bool
    public var interruptInhibit: Bool
    public var cycles: UInt64
}

/// Unusual events the CPU reports instead of silently ignoring.
public enum CPUDiagnostic: Equatable, CustomStringConvertible, Sendable {
    /// An ED-prefixed opcode with no defined function. Real Z80 silicon
    /// executes these as an 8 T-state NOP, which is what the core does.
    case undefinedEDOpcode(opcode: UInt8, pc: UInt16)

    public var description: String {
        switch self {
        case let .undefinedEDOpcode(opcode, pc):
            return "Undefined opcode: 0xED 0x\(hex(opcode)) PC: 0x\(hex(pc)) (executed as NOP, as on Z80 hardware)"
        }
    }
}

/// Precomputed flag tables.
final class FlagTables: @unchecked Sendable {
    static let shared = FlagTables()

    let sz53: UnsafeMutablePointer<UInt8>
    let sz53p: UnsafeMutablePointer<UInt8>
    let parity: UnsafeMutablePointer<UInt8>

    private init() {
        sz53 = .allocate(capacity: 256)
        sz53p = .allocate(capacity: 256)
        parity = .allocate(capacity: 256)
        for i in 0..<256 {
            let v = UInt8(i)
            var s53 = v & (Flag.s | Flag.xy)
            if v == 0 { s53 |= Flag.z }
            let p: UInt8 = v.nonzeroBitCount % 2 == 0 ? Flag.pv : 0
            sz53[i] = s53
            parity[i] = p
            sz53p[i] = s53 | p
        }
    }
}
