import Foundation

/// Routes CPU memory accesses to flash, RAM or memory-mapped peripherals and
/// accounts for the access cost (wait states) in the scheduler's cycle counter.
public final class MemoryBus {
    public let flash: Flash
    public let ram: RAM
    public let io: IOBus
    public var mapper = MemoryMapper()
    unowned let scheduler: Scheduler

    private let flashPtr: UnsafeMutablePointer<UInt8>
    private let ramPtr: UnsafeMutablePointer<UInt8>

    /// Cycles per flash byte read. Programmed through flash controller port 0x1005.
    public var flashReadCycles: Int64 = 10
    public var ramReadCycles: Int64 = 3
    public var ramWriteCycles: Int64 = 2
    public var mmioCycles: Int64 = 4

    /// Value returned for reads from unmapped space.
    public var unmappedValue: UInt8 = 0x00

    /// Debug hook: CPU stores that reach flash (command cycles), (address, value).
    public var flashWriteTrace: ((UInt32, UInt8) -> Void)?

    public init(flash: Flash, ram: RAM, io: IOBus, scheduler: Scheduler) {
        self.flash = flash
        self.ram = ram
        self.io = io
        self.scheduler = scheduler
        flashPtr = flash.bytes
        ramPtr = ram.bytes
    }

    @inline(__always) public func read(_ address: UInt32) -> UInt8 {
        let a = address & 0xFF_FFFF
        if a < mapper.flashSize {
            scheduler.cycles &+= flashReadCycles
            return flash.isReadMode ? flashPtr[Int(a)] : flash.read(a)
        }
        if a >= mapper.ramBase && a < 0xE00000 {
            scheduler.cycles &+= ramReadCycles
            let o = (a &- mapper.ramBase) & (mapper.ramWindow &- 1)
            return o < mapper.ramSize ? ramPtr[Int(o)] : unmappedValue
        }
        return slowRead(a)
    }

    @inline(__always) public func write(_ address: UInt32, value: UInt8) {
        let a = address & 0xFF_FFFF
        if a >= mapper.ramBase && a < 0xE00000 {
            scheduler.cycles &+= ramWriteCycles
            let o = (a &- mapper.ramBase) & (mapper.ramWindow &- 1)
            if o < mapper.ramSize { ramPtr[Int(o)] = value }
            return
        }
        slowWrite(a, value)
    }

    private func slowRead(_ a: UInt32) -> UInt8 {
        switch mapper.decode(a) {
        case .io(let port):
            scheduler.cycles &+= mmioCycles
            return io.read(port)
        default:
            scheduler.cycles &+= 1
            return unmappedValue
        }
    }

    private func slowWrite(_ a: UInt32, _ value: UInt8) {
        switch mapper.decode(a) {
        case .flash(let o):
            // Direct stores never modify flash; they feed the chip's command decoder.
            scheduler.cycles &+= flashReadCycles
            flashWriteTrace?(o, value)
            flash.write(o, value: value)
        case .io(let port):
            scheduler.cycles &+= mmioCycles
            io.write(port, value: value)
        default:
            scheduler.cycles &+= 1
        }
    }

    /// Debugger read: no wait states and no peripheral side effects.
    public func peek(_ address: UInt32) -> UInt8 {
        switch mapper.decode(address) {
        case .flash(let o): return flash.read(o)
        case .ram(let o): return ramPtr[Int(o)]
        case .io(let port): return io.peek(port)
        case .unmapped: return unmappedValue
        }
    }

    /// Debugger write to RAM (flash and I/O are left untouched).
    public func poke(_ address: UInt32, value: UInt8) {
        if case .ram(let o) = mapper.decode(address) { ramPtr[Int(o)] = value }
    }
}
