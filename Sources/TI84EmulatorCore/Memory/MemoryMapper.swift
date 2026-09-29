/// A 16 KB physical page: either Flash or RAM.
public enum PhysicalPage: Equatable, Codable, CustomStringConvertible, Sendable {
    case flash(Int)
    case ram(Int)

    public var description: String {
        switch self {
        case let .flash(p): return "Flash \(hex(UInt8(truncatingIfNeeded: p)))"
        case let .ram(p): return "RAM \(p)"
        }
    }
}

/// The TI-84 Plus ASIC memory controller.
///
/// Translates the paging ports into the four CPU banks:
///
/// | Bank        | Mode 0 (port 04h bit 0 = 0) | Mode 1              |
/// |-------------|-----------------------------|---------------------|
/// | 0000–3FFF   | Flash page 0                | Flash page 0        |
/// | 4000–7FFF   | port 06h (bank A)           | bank A, even page   |
/// | 8000–BFFF   | port 07h (bank B)           | bank A, odd page    |
/// | C000–FFFF   | RAM page from port 05h      | port 07h (bank B)   |
///
/// Ports 06h/07h select RAM when bit 7 is set. Ports 27h/28h remap the top
/// (C000+) and bottom (8000+) ends of the upper banks to RAM pages 0 and 1 in
/// 64-byte steps. The certificate page is unreadable while Flash is locked.
///
/// It also watches opcode fetches from privileged Flash pages for the
/// `nop / nop / im 1 / di / out (14h),a` sequence that is the only way to
/// write the Flash-protection port.
public final class MemoryMapper: MemoryDevice, OpcodeFetchObserver, IODevice {
    public let profile: HardwareProfile
    public let bus: MemoryBus
    public let flash: FlashChip
    public let ram: RAM

    public private(set) var port04: UInt8 = 0
    public private(set) var port05: UInt8 = 0
    public private(set) var port06: UInt8 = 0
    public private(set) var port07: UInt8 = 0
    public private(set) var port0E: UInt8 = 0
    public private(set) var port0F: UInt8 = 0
    public private(set) var port27: UInt8 = 0
    public private(set) var port28: UInt8 = 0

    /// Pages currently visible in each bank (for the debugger).
    public private(set) var banks: [PhysicalPage] = [.flash(0), .flash(0), .flash(0), .ram(0)]

    /// Progress through the privileged unlock sequence (0...6).
    public private(set) var protectionSequence = 0
    private static let protectionBytes: [UInt8] = [0x00, 0x00, 0xED, 0x56, 0xF3, 0xD3]

    public init(profile: HardwareProfile, bus: MemoryBus, flash: FlashChip, ram: RAM) {
        self.profile = profile
        self.bus = bus
        self.flash = flash
        self.ram = ram
        flash.onMappingChange = { [unowned self] in self.remap() }
        bus.opcodeObserver = self
        reset()
    }

    /// Power-on state: memory mode 1 with the boot page in banks 2 and 3;
    /// execution starts at 8000h inside the boot code.
    public func reset() {
        let boot = UInt8(profile.bootPage)
        port04 = 0x07
        port05 = 0
        port06 = boot
        port07 = boot
        port0E = 0
        port0F = 0
        port27 = 0
        port28 = 0
        protectionSequence = 0
        remap()
    }

    /// Memory-map mode bit of port 04h (port 04h is shared with the timers).
    public func setMode(fromPort04 value: UInt8) {
        port04 = value
        remap()
    }

    // MARK: - IODevice (ports 05, 06, 07, 0E, 0F, 27, 28)

    public func read(port: UInt8) -> UInt8 {
        switch port {
        case 0x05: return port05 & 0x0F
        case 0x06: return port06
        case 0x07: return port07
        case 0x0E: return port0E & 0x03
        case 0x0F: return port0F & 0x03
        case 0x27: return port27
        case 0x28: return port28
        default: return 0
        }
    }

    public func write(port: UInt8, value: UInt8) {
        switch port {
        case 0x05: port05 = value & 0x0F
        case 0x06: port06 = value
        case 0x07: port07 = value
        case 0x0E: port0E = value
        case 0x0F: port0F = value
        case 0x27: port27 = value
        case 0x28: port28 = value
        default: return
        }
        remap()
    }

    // MARK: - Mapping

    private func page(forBankPort value: UInt8) -> PhysicalPage {
        value & 0x80 != 0
            ? .ram(Int(value & 0x07) % profile.ramPages)
            : .flash(Int(value & profile.flashPageMask))
    }

    public func remap() {
        let a = page(forBankPort: port06)
        let b = page(forBankPort: port07)
        if port04 & 0x01 != 0 {
            banks = [.flash(0), a.withLowBit(false), a.withLowBit(true), b]
        } else {
            banks = [.flash(0), a, b, .ram(Int(port05 & 0x07) % profile.ramPages)]
        }
        for bank in 0..<4 {
            configure(bank: bank)
        }
    }

    private func configure(bank: Int) {
        let partial = (bank == 3 && port27 != 0) || (bank == 2 && port28 != 0)
        switch banks[bank] {
        case let .ram(p):
            if partial {
                bus.map(bank: bank, read: nil, write: nil, device: self)
            } else {
                let base = ram.pagePointer(p)
                bus.map(bank: bank, read: base, write: base, device: self)
            }
        case let .flash(p):
            let direct = !partial && flash.isInReadMode
                && (p != profile.certificatePage || flash.unlocked)
            bus.map(bank: bank,
                    read: direct ? flash.pagePointer(p) : nil,
                    write: nil,
                    device: self,
                    watchOpcodeFetches: profile.isPrivilegedPage(p))
        }
    }

    /// Resolves a CPU address to a physical page and offset, applying the
    /// port 27h/28h partial remaps.
    public func physicalPage(for address: UInt16) -> PhysicalPage {
        if address & 0x8000 != 0 {
            if port27 != 0 && Int(address) > 0xFFFF - 64 * Int(port27) { return .ram(0) }
            if port28 != 0 && Int(address) < 0x8000 + 64 * Int(port28) { return .ram(1) }
        }
        return banks[Int(address >> 14)]
    }

    // MARK: - MemoryDevice (slow path)

    public func read(_ address: UInt16) -> UInt8 {
        let offset = Int(address & 0x3FFF)
        switch physicalPage(for: address) {
        case let .ram(p):
            return ram[physical: p * MemoryBus.bankSize + offset]
        case let .flash(p):
            if p == profile.certificatePage && !flash.unlocked { return 0xFF }
            return flash.read(physical: p * MemoryBus.bankSize + offset)
        }
    }

    public func peek(_ address: UInt16) -> UInt8 {
        let offset = Int(address & 0x3FFF)
        switch physicalPage(for: address) {
        case let .ram(p): return ram[physical: p * MemoryBus.bankSize + offset]
        case let .flash(p): return flash.storage[p * MemoryBus.bankSize + offset]
        }
    }

    public func write(_ address: UInt16, value: UInt8) {
        let offset = Int(address & 0x3FFF)
        switch physicalPage(for: address) {
        case let .ram(p):
            ram[physical: p * MemoryBus.bankSize + offset] = value
        case let .flash(p):
            flash.write(physical: p * MemoryBus.bankSize + offset, value: value)
        }
    }

    // MARK: - Privileged sequence detection

    public func opcodeFetched(at address: UInt16, value: UInt8) {
        guard case let .flash(p) = physicalPage(for: address), profile.isPrivilegedPage(p) else {
            protectionSequence = 0
            bus.opcodeObserverArmed = false
            return
        }
        if protectionSequence < 6 && value == Self.protectionBytes[protectionSequence] {
            protectionSequence += 1
        } else {
            protectionSequence = value == Self.protectionBytes[0] ? 1 : 0
        }
        bus.opcodeObserverArmed = protectionSequence != 0
    }

    /// True while the `out (14h),a` at the end of the privileged sequence executes.
    public var isPrivilegedWriteAllowed: Bool { protectionSequence == 6 }

    // MARK: - State

    var snapshot: MapperState {
        MapperState(port04: port04, port05: port05, port06: port06, port07: port07,
                    port0E: port0E, port0F: port0F, port27: port27, port28: port28)
    }

    func restore(_ s: MapperState) {
        port04 = s.port04; port05 = s.port05; port06 = s.port06; port07 = s.port07
        port0E = s.port0E; port0F = s.port0F; port27 = s.port27; port28 = s.port28
        protectionSequence = 0
        bus.opcodeObserverArmed = false
        remap()
    }
}

public struct MapperState: Codable, Equatable, Sendable {
    var port04, port05, port06, port07, port0E, port0F, port27, port28: UInt8
}

private extension PhysicalPage {
    func withLowBit(_ set: Bool) -> PhysicalPage {
        switch self {
        case let .flash(p): return .flash(set ? p | 1 : p & ~1)
        case let .ram(p): return .ram(set ? p | 1 : p & ~1)
        }
    }
}
