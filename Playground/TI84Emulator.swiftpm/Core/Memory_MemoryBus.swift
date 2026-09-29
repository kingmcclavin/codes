/// Anything that can sit behind a 16 KB bank of the CPU address space.
public protocol MemoryDevice: AnyObject {
    func read(_ address: UInt16) -> UInt8
    func write(_ address: UInt16, value: UInt8)
    /// Side-effect-free read for debuggers. Defaults to `read`.
    func peek(_ address: UInt16) -> UInt8
}

public extension MemoryDevice {
    func peek(_ address: UInt16) -> UInt8 { read(address) }
}

/// Notified of every opcode (M1) fetch while armed. The TI-84 ASIC uses this
/// to watch for the privileged Flash-unlock instruction sequence.
public protocol OpcodeFetchObserver: AnyObject {
    func opcodeFetched(at address: UInt16, value: UInt8)
}

/// The CPU's 64 KB address space, split into four 16 KB banks.
///
/// A memory mapper decides what each bank points at. For plain RAM/Flash
/// reads the bus keeps a direct pointer so the hot path is a single load;
/// anything with side effects (Flash command sequences, read protection,
/// partial-bank remapping) is routed through a `MemoryDevice`.
public final class MemoryBus {
    public static let bankSize = 0x4000

    private let readBase: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    private let writeBase: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    private let watchFetch: UnsafeMutablePointer<Bool>
    private var devices: [MemoryDevice?] = [nil, nil, nil, nil]
    private var retained: [AnyObject] = []

    /// Receives M1 fetches from banks marked with `watchOpcodeFetches`, or
    /// from every bank while `opcodeObserverArmed` is true.
    public weak var opcodeObserver: OpcodeFetchObserver?
    public var opcodeObserverArmed = false

    public init() {
        readBase = .allocate(capacity: 4)
        writeBase = .allocate(capacity: 4)
        watchFetch = .allocate(capacity: 4)
        readBase.initialize(repeating: nil, count: 4)
        writeBase.initialize(repeating: nil, count: 4)
        watchFetch.initialize(repeating: false, count: 4)
    }

    deinit {
        readBase.deallocate()
        writeBase.deallocate()
        watchFetch.deallocate()
    }

    /// A bus backed by 64 KB of flat RAM (useful for CPU tests and CP/M-style
    /// test programs).
    public static func flatRAM() -> (MemoryBus, RAM) {
        let bus = MemoryBus()
        let ram = RAM(pageCount: 4)
        for bank in 0..<4 {
            let base = ram.pagePointer(bank)
            bus.map(bank: bank, read: base, write: base, device: ram)
        }
        bus.retained.append(ram)
        return (bus, ram)
    }

    /// Maps a 16 KB bank. `read`/`write` are direct pointers to the start of
    /// the 16 KB backing page; pass nil to route that access to `device`
    /// (which receives the full CPU address). A nil write pointer with a nil
    /// device makes the bank read-only.
    public func map(bank: Int,
                    read: UnsafeMutablePointer<UInt8>?,
                    write: UnsafeMutablePointer<UInt8>?,
                    device: MemoryDevice?,
                    watchOpcodeFetches: Bool = false) {
        readBase[bank] = read
        writeBase[bank] = write
        devices[bank] = device
        watchFetch[bank] = watchOpcodeFetches
    }

    @inline(__always)
    public func read(_ address: UInt16) -> UInt8 {
        let bank = Int(address >> 14)
        if let base = readBase[bank] {
            return base[Int(address & 0x3FFF)]
        }
        return devices[bank]?.read(address) ?? 0xFF
    }

    @inline(__always)
    public func write(_ address: UInt16, value: UInt8) {
        let bank = Int(address >> 14)
        if let base = writeBase[bank] {
            base[Int(address & 0x3FFF)] = value
        } else {
            devices[bank]?.write(address, value: value)
        }
    }

    /// Opcode fetch (Z80 M1 cycle).
    @inline(__always)
    public func fetchOpcode(_ address: UInt16) -> UInt8 {
        let value = read(address)
        if opcodeObserverArmed || watchFetch[Int(address >> 14)] {
            opcodeObserver?.opcodeFetched(at: address, value: value)
        }
        return value
    }

    /// Debugger read without side effects.
    public func peek(_ address: UInt16) -> UInt8 {
        let bank = Int(address >> 14)
        if let base = readBase[bank] {
            return base[Int(address & 0x3FFF)]
        }
        return devices[bank]?.peek(address) ?? 0xFF
    }

    public func read16(_ address: UInt16) -> UInt16 {
        UInt16(read(address)) | UInt16(read(address &+ 1)) << 8
    }

    /// Copies bytes into memory through the normal write path.
    public func load(_ bytes: [UInt8], at address: UInt16) {
        for (offset, byte) in bytes.enumerated() {
            write(address &+ UInt16(truncatingIfNeeded: offset), value: byte)
        }
    }
}
