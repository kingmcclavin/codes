/// A peripheral reachable through Z80 `IN`/`OUT` instructions.
public protocol IODevice: AnyObject {
    func read(port: UInt8) -> UInt8
    func write(port: UInt8, value: UInt8)
}

/// One recorded port access, for the debugger's I/O view.
public struct IOAccess: Equatable, Sendable {
    public enum Direction: Sendable { case read, write }
    public var direction: Direction
    public var port: UInt8
    public var value: UInt8
    public var cycle: UInt64
}

/// Routes port accesses to devices. The TI-84 ASIC decodes only the low 8
/// address bits, so ports are 0x00–0xFF regardless of what the upper byte of
/// the Z80 address bus holds.
public final class IOBus {
    private var handlers: [IODevice?] = Array(repeating: nil, count: 256)

    /// Value returned for reads from ports nothing is mapped to.
    public var unmappedReadValue: UInt8 = 0x00

    /// Last value read from / written to each port (debugger view).
    public private(set) var lastRead = [UInt8](repeating: 0, count: 256)
    public private(set) var lastWritten = [UInt8](repeating: 0, count: 256)

    /// Called for accesses to unmapped ports (port, isWrite, value).
    public var unmappedAccessHandler: ((UInt8, Bool, UInt8) -> Void)?

    /// Optional access trace (ring buffer) for debugging; disabled when nil.
    public var trace: IOTrace?
    /// Supplies the cycle stamp for traced accesses.
    public var cycleSource: (() -> UInt64)?

    public init() {}

    public func map(_ port: UInt8, to device: IODevice) {
        handlers[Int(port)] = device
    }

    public func map<S: Sequence>(_ ports: S, to device: IODevice) where S.Element == UInt8 {
        for port in ports { map(port, to: device) }
    }

    public func device(for port: UInt8) -> IODevice? {
        handlers[Int(port)]
    }

    /// Port read from the CPU; `busAddress` is the full 16-bit Z80 I/O
    /// address, of which the ASIC decodes the low byte.
    @inline(__always)
    public func read(busAddress port: UInt16) -> UInt8 {
        let p = Int(port & 0xFF)
        let value: UInt8
        if let device = handlers[p] {
            value = device.read(port: UInt8(p))
        } else {
            value = unmappedReadValue
            unmappedAccessHandler?(UInt8(p), false, value)
        }
        lastRead[p] = value
        if let trace { trace.record(IOAccess(direction: .read, port: UInt8(p), value: value, cycle: cycleSource?() ?? 0)) }
        return value
    }

    @inline(__always)
    public func write(busAddress port: UInt16, value: UInt8) {
        let p = Int(port & 0xFF)
        lastWritten[p] = value
        if let trace { trace.record(IOAccess(direction: .write, port: UInt8(p), value: value, cycle: cycleSource?() ?? 0)) }
        if let device = handlers[p] {
            device.write(port: UInt8(p), value: value)
        } else {
            unmappedAccessHandler?(UInt8(p), true, value)
        }
    }

    public func read(port: UInt8) -> UInt8 { read(busAddress: UInt16(port)) }
    public func write(port: UInt8, value: UInt8) { write(busAddress: UInt16(port), value: value) }

    /// Debugger read that does not disturb device state where avoidable:
    /// returns the last value the CPU read from that port.
    public func peek(port: UInt8) -> UInt8 {
        lastRead[Int(port)]
    }
}

/// Fixed-size ring buffer of I/O accesses.
public final class IOTrace {
    public let capacity: Int
    private var buffer: [IOAccess] = []
    private var next = 0

    public init(capacity: Int = 256) {
        self.capacity = capacity
        buffer.reserveCapacity(capacity)
    }

    func record(_ access: IOAccess) {
        if buffer.count < capacity {
            buffer.append(access)
        } else {
            buffer[next] = access
        }
        next = (next + 1) % capacity
    }

    /// Accesses from oldest to newest.
    public var entries: [IOAccess] {
        buffer.count < capacity ? buffer : Array(buffer[next...] + buffer[..<next])
    }
}
