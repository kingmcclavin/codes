/// The calculator's NOR Flash chip (AMD/Fujitsu command set), which holds
/// the boot code, the OS and the user archive.
///
/// The chip starts as a copy of the ROM image. The OS may program and erase
/// it (to archive variables or garbage-collect) through the standard unlock
/// command sequences; the original `ROMImage` is never modified.
public final class FlashChip {
    public enum State: UInt8, Codable, Sendable {
        case read, unlock1, unlock2, program, erase, eraseUnlock1, eraseUnlock2, error
        case bypass, bypassProgram, bypassReset
    }

    public let size: Int
    public let storage: UnsafeMutableBufferPointer<UInt8>
    private let sectors: [FlashSector]

    /// Set by port 14h (only writable via the privileged unlock sequence).
    public var unlocked = false {
        didSet { if unlocked != oldValue { onMappingChange?() } }
    }
    /// Protection groups enabled for writing by port 21h.
    public var overrideGroup: UInt8 = 0
    public private(set) var state: State = .read {
        didSet { if (state == .read) != (oldValue == .read) { onMappingChange?() } }
    }
    /// Set whenever the contents change, so the host can persist the archive.
    public var isDirty = false
    /// Human-readable log of notable events (erases, protection violations).
    public var eventHandler: ((String) -> Void)?

    /// Called when direct-pointer reads become valid or invalid.
    var onMappingChange: (() -> Void)?

    private var lastProgrammedByte: UInt8 = 0
    private var toggle: UInt8 = 0

    public init(image: ROMImage) {
        size = image.size
        sectors = image.profile.flashSectors
        overrideGroup = image.profile.flashOverrideGroupReset
        storage = .allocate(capacity: size)
        _ = storage.initialize(from: image.bytes)
    }

    deinit {
        storage.deallocate()
    }

    public func pagePointer(_ page: Int) -> UnsafeMutablePointer<UInt8> {
        storage.baseAddress! + (page * MemoryBus.bankSize) % size
    }

    /// Whether reads currently return array contents (so the memory bus may
    /// read through a direct pointer).
    public var isInReadMode: Bool { state == .read }

    public func reset() {
        unlocked = false
        state = .read
    }

    public func read(physical address: Int) -> UInt8 {
        if state == .error {
            // Status polling: DQ7 = complement of the data, DQ5 = timeout,
            // DQ6 toggles on every read.
            toggle ^= 0x40
            return ((~lastProgrammedByte) & 0x80) | 0x20 | toggle
        }
        if state != .read && state != .bypass {
            // Reading in the middle of a command sequence aborts it.
            state = .read
        }
        return storage[address]
    }

    public func write(physical address: Int, value: UInt8) {
        guard unlocked else { return }
        let command = address & 0xFFF
        let previous = state
        state = .read

        switch previous {
        case .read, .error:
            if command == 0xAAA && value == 0xAA { state = .unlock1 }
        case .unlock1:
            if command == 0x555 && value == 0x55 { state = .unlock2 }
        case .unlock2:
            guard command == 0xAAA else { return }
            switch value {
            case 0x80: state = .erase
            case 0xA0: state = .program
            case 0x20: state = .bypass
            default: break   // F0 (reset), 90 (autoselect: not supported) etc.
            }
        case .program:
            program(address, value)
        case .bypass:
            if value == 0xA0 { state = .bypassProgram }
            else if value == 0x90 { state = .bypassReset }
            else { state = .bypass }
        case .bypassProgram:
            program(address, value)
            if state != .error { state = .bypass }
        case .bypassReset:
            if value != 0xF0 { state = .bypass }
        case .erase:
            if command == 0xAAA && value == 0xAA { state = .eraseUnlock1 }
        case .eraseUnlock1:
            if command == 0x555 && value == 0x55 { state = .eraseUnlock2 }
        case .eraseUnlock2:
            if command == 0xAAA && value == 0x10 {
                eventHandler?("Flash: chip erase")
                for sector in sectors where isWritable(sector) { erase(sector) }
            } else if value == 0x30 {
                if let sector = sector(containing: address) {
                    if isWritable(sector) {
                        eventHandler?("Flash: erase sector \(hex(UInt32(sector.start)))")
                        erase(sector)
                    } else {
                        eventHandler?("Flash: attempt to erase protected sector \(hex(UInt32(sector.start)))")
                    }
                }
            }
        }
    }

    private func program(_ address: Int, _ value: UInt8) {
        guard let sector = sector(containing: address), isWritable(sector) else {
            eventHandler?("Flash: attempt to program protected address \(hex(UInt32(address)))")
            return
        }
        // Programming can only clear bits.
        let result = storage[address] & value
        storage[address] = result
        lastProgrammedByte = value
        isDirty = true
        if result != value {
            eventHandler?("Flash: bad program of \(hex(value)) over \(hex(result)) at \(hex(UInt32(address)))")
            state = .error
        }
    }

    private func erase(_ sector: FlashSector) {
        for i in sector.start..<(sector.start + sector.size) { storage[i] = 0xFF }
        isDirty = true
    }

    private func sector(containing address: Int) -> FlashSector? {
        sectors.first { address >= $0.start && address < $0.start + $0.size }
    }

    private func isWritable(_ sector: FlashSector) -> Bool {
        sector.protectionGroup & ~overrideGroup == 0
    }

    // MARK: - Persistence

    public var contents: [UInt8] { Array(storage) }

    public func load(_ bytes: [UInt8]) {
        guard bytes.count == size else { return }
        for i in 0..<size { storage[i] = bytes[i] }
        onMappingChange?()
    }

    var snapshot: FlashState {
        FlashState(unlocked: unlocked, overrideGroup: overrideGroup, state: state,
                   lastProgrammedByte: lastProgrammedByte)
    }

    func restore(_ s: FlashState) {
        unlocked = s.unlocked
        overrideGroup = s.overrideGroup
        state = s.state
        lastProgrammedByte = s.lastProgrammedByte
        onMappingChange?()
    }
}

public struct FlashState: Codable, Equatable, Sendable {
    var unlocked: Bool
    var overrideGroup: UInt8
    var state: FlashChip.State
    var lastProgrammedByte: UInt8
}
