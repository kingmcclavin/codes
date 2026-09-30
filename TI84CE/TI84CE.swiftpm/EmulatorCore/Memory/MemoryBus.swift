import Foundation

/// The memory bus state touched on every CPU access, kept in raw memory so the CPU
/// can reach it without reference counting or exclusivity bookkeeping (which
/// dominate the cost of unoptimized builds such as Swift Playgrounds' debug runs).
/// The decoding logic itself stays in `MemoryBus`.
public struct BusFastState {
    public var flash: UnsafeMutablePointer<UInt8>
    public var ram: UnsafeMutablePointer<UInt8>
    /// True while the flash chip is in array-read mode (maintained by `Flash`).
    public var flashReadMode: UnsafeMutablePointer<Bool>
    /// The scheduler's CPU cycle counter.
    public var clock: UnsafeMutablePointer<Int64>
    public var flashSize: UInt32
    public var ramBase: UInt32
    public var ramMask: UInt32
    public var ramSize: UInt32
    public var flashReadCycles: Int64
    public var ramReadCycles: Int64
    public var ramWriteCycles: Int64
    /// RAM writes at or above this offset mark the framebuffer dirty.
    public var vramWatch: UInt32
    public var vramDirty: Bool
    /// Back-reference for the slow path (MMIO, flash commands, unmapped space).
    var owner: Unmanaged<MemoryBus>?
}

/// Routes CPU memory accesses to flash, RAM or memory-mapped peripherals and
/// accounts for the access cost (wait states) in the scheduler's cycle counter.
public final class MemoryBus {
    public let flash: Flash
    public let ram: RAM
    public let io: IOBus
    unowned(unsafe) let scheduler: Scheduler
    public let fast: UnsafeMutablePointer<BusFastState>

    public var mapper = MemoryMapper() {
        didSet { syncMapper() }
    }

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
        fast = .allocate(capacity: 1)
        fast.initialize(to: BusFastState(
            flash: flash.bytes, ram: ram.bytes, flashReadMode: flash.readModeFlag, clock: scheduler.clock,
            flashSize: 0, ramBase: 0, ramMask: 0, ramSize: 0,
            flashReadCycles: 10, ramReadCycles: 3, ramWriteCycles: 2,
            vramWatch: 0, vramDirty: true, owner: nil))
        fast.pointee.owner = Unmanaged.passUnretained(self)
        syncMapper()
    }

    deinit { fast.deallocate() }

    private func syncMapper() {
        fast.pointee.flashSize = mapper.flashSize
        fast.pointee.ramBase = mapper.ramBase
        fast.pointee.ramMask = mapper.ramWindow &- 1
        fast.pointee.ramSize = mapper.ramSize
    }

    /// Cycles per flash byte read. Programmed through flash controller port 0x1005.
    public var flashReadCycles: Int64 {
        get { fast.pointee.flashReadCycles }
        set { fast.pointee.flashReadCycles = newValue }
    }
    public var ramReadCycles: Int64 {
        get { fast.pointee.ramReadCycles }
        set { fast.pointee.ramReadCycles = newValue }
    }
    public var ramWriteCycles: Int64 {
        get { fast.pointee.ramWriteCycles }
        set { fast.pointee.ramWriteCycles = newValue }
    }
    /// RAM writes at or above this offset mark the framebuffer dirty (set by the LCD
    /// controller to its current base address), so unchanged frames are not re-streamed.
    public var vramWatch: UInt32 {
        get { fast.pointee.vramWatch }
        set { fast.pointee.vramWatch = newValue }
    }
    public var vramDirty: Bool {
        get { fast.pointee.vramDirty }
        set { fast.pointee.vramDirty = newValue }
    }

    // MARK: CPU access

    /// CPU read with wait states. Flash (array mode) and RAM are served directly
    /// from the shared state; everything else takes the slow path.
    @inline(__always)
    public static func read(_ f: UnsafeMutablePointer<BusFastState>, _ address: UInt32) -> UInt8 {
        let a = address & 0xFF_FFFF
        if a < f.pointee.flashSize {
            if f.pointee.flashReadMode.pointee {
                f.pointee.clock.pointee &+= f.pointee.flashReadCycles
                return f.pointee.flash[Int(truncatingIfNeeded: a)]
            }
        } else if a >= f.pointee.ramBase && a < 0xE00000 {
            f.pointee.clock.pointee &+= f.pointee.ramReadCycles
            let o = (a &- f.pointee.ramBase) & f.pointee.ramMask
            return o < f.pointee.ramSize ? f.pointee.ram[Int(truncatingIfNeeded: o)] : 0
        }
        return f.pointee.owner!.takeUnretainedValue().slowRead(a)
    }

    /// CPU write with wait states; RAM is served directly, flash stores go to the
    /// chip's command decoder, I/O to the peripherals.
    @inline(__always)
    public static func write(_ f: UnsafeMutablePointer<BusFastState>, _ address: UInt32, _ value: UInt8) {
        let a = address & 0xFF_FFFF
        if a >= f.pointee.ramBase && a < 0xE00000 {
            f.pointee.clock.pointee &+= f.pointee.ramWriteCycles
            let o = (a &- f.pointee.ramBase) & f.pointee.ramMask
            if o < f.pointee.ramSize {
                f.pointee.ram[Int(truncatingIfNeeded: o)] = value
                if o >= f.pointee.vramWatch { f.pointee.vramDirty = true }
            }
            return
        }
        f.pointee.owner!.takeUnretainedValue().slowWrite(a, value)
    }

    public func read(_ address: UInt32) -> UInt8 { MemoryBus.read(fast, address) }
    public func write(_ address: UInt32, value: UInt8) { MemoryBus.write(fast, address, value) }

    func slowRead(_ a: UInt32) -> UInt8 {
        switch mapper.decode(a) {
        case .flash(let o):
            scheduler.cycles &+= flashReadCycles
            return flash.read(o)
        case .ram(let o):
            scheduler.cycles &+= ramReadCycles
            return ram.bytes[Int(o)]
        case .io(let port):
            scheduler.cycles &+= mmioCycles
            return io.read(port)
        case .unmapped:
            scheduler.cycles &+= 1
            return unmappedValue
        }
    }

    func slowWrite(_ a: UInt32, _ value: UInt8) {
        switch mapper.decode(a) {
        case .flash(let o):
            // Direct stores never modify flash; they feed the chip's command decoder.
            scheduler.cycles &+= flashReadCycles
            flashWriteTrace?(o, value)
            flash.write(o, value: value)
        case .ram(let o):
            scheduler.cycles &+= ramWriteCycles
            ram.bytes[Int(o)] = value
            vramDirty = true
        case .io(let port):
            scheduler.cycles &+= mmioCycles
            io.write(port, value: value)
        case .unmapped:
            scheduler.cycles &+= 1
        }
    }

    // MARK: Debugger access

    /// Debugger read: no wait states and no peripheral side effects.
    public func peek(_ address: UInt32) -> UInt8 {
        switch mapper.decode(address) {
        case .flash(let o): return flash.read(o)
        case .ram(let o): return ram.bytes[Int(o)]
        case .io(let port): return io.peek(port)
        case .unmapped: return unmappedValue
        }
    }

    /// Debugger write to RAM (flash and I/O are left untouched).
    public func poke(_ address: UInt32, value: UInt8) {
        if case .ram(let o) = mapper.decode(address) {
            ram.bytes[Int(o)] = value
            vramDirty = true
        }
    }
}
