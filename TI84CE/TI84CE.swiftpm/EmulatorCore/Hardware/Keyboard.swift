import Foundation

/// A physical key position in the TI-84 Plus CE key matrix: `group` is the scan row
/// (1...7, register 0xF50010 + 2*group) and `bit` the column.
/// The ON key is not part of the matrix; it drives its own interrupt line.
public struct KeyPosition: Hashable, Codable {
    public let group: Int
    public let bit: Int
    public init(group: Int, bit: Int) { self.group = group; self.bit = bit }
    public static let on = KeyPosition(group: 0, bit: 0xFF)
    public var isOn: Bool { bit == 0xFF }
}

/// The TI-84 Plus CE's physical keys, with their matrix positions.
public enum CalculatorKey: String, CaseIterable, Codable {
    case graph, trace, zoom, window, yEquals, second, mode, del
    case sto, ln, log, square, inverse, math, alpha
    case k0, k1, k4, k7, comma, sin, apps, xton
    case decimal, k2, k5, k8, leftParen, cos, prgm, stat
    case negate, k3, k6, k9, rightParen, tan, vars
    case enter, add, subtract, multiply, divide, power, clear
    case down, left, right, up
    case on

    public var position: KeyPosition {
        switch self {
        case .graph: return .init(group: 1, bit: 0)
        case .trace: return .init(group: 1, bit: 1)
        case .zoom: return .init(group: 1, bit: 2)
        case .window: return .init(group: 1, bit: 3)
        case .yEquals: return .init(group: 1, bit: 4)
        case .second: return .init(group: 1, bit: 5)
        case .mode: return .init(group: 1, bit: 6)
        case .del: return .init(group: 1, bit: 7)
        case .sto: return .init(group: 2, bit: 1)
        case .ln: return .init(group: 2, bit: 2)
        case .log: return .init(group: 2, bit: 3)
        case .square: return .init(group: 2, bit: 4)
        case .inverse: return .init(group: 2, bit: 5)
        case .math: return .init(group: 2, bit: 6)
        case .alpha: return .init(group: 2, bit: 7)
        case .k0: return .init(group: 3, bit: 0)
        case .k1: return .init(group: 3, bit: 1)
        case .k4: return .init(group: 3, bit: 2)
        case .k7: return .init(group: 3, bit: 3)
        case .comma: return .init(group: 3, bit: 4)
        case .sin: return .init(group: 3, bit: 5)
        case .apps: return .init(group: 3, bit: 6)
        case .xton: return .init(group: 3, bit: 7)
        case .decimal: return .init(group: 4, bit: 0)
        case .k2: return .init(group: 4, bit: 1)
        case .k5: return .init(group: 4, bit: 2)
        case .k8: return .init(group: 4, bit: 3)
        case .leftParen: return .init(group: 4, bit: 4)
        case .cos: return .init(group: 4, bit: 5)
        case .prgm: return .init(group: 4, bit: 6)
        case .stat: return .init(group: 4, bit: 7)
        case .negate: return .init(group: 5, bit: 0)
        case .k3: return .init(group: 5, bit: 1)
        case .k6: return .init(group: 5, bit: 2)
        case .k9: return .init(group: 5, bit: 3)
        case .rightParen: return .init(group: 5, bit: 4)
        case .tan: return .init(group: 5, bit: 5)
        case .vars: return .init(group: 5, bit: 6)
        case .enter: return .init(group: 6, bit: 0)
        case .add: return .init(group: 6, bit: 1)
        case .subtract: return .init(group: 6, bit: 2)
        case .multiply: return .init(group: 6, bit: 3)
        case .divide: return .init(group: 6, bit: 4)
        case .power: return .init(group: 6, bit: 5)
        case .clear: return .init(group: 6, bit: 6)
        case .down: return .init(group: 7, bit: 0)
        case .left: return .init(group: 7, bit: 1)
        case .right: return .init(group: 7, bit: 2)
        case .up: return .init(group: 7, bit: 3)
        case .on: return .on
        }
    }
}

/// Keypad controller (port range Axxx, memory-mapped at 0xF50000).
///
///     +00 control: bits 0-1 mode (0 idle, 1 any-key, 2 single scan, 3 continuous),
///                  bits 2-15 row wait, bits 16-31 scan wait (in 6 MHz clocks)
///     +04 rows (8) / columns (8)
///     +08 interrupt status (write 1 to clear): bit0 scan done, bit1 data changed, bit2 key pressed
///     +0C interrupt enable
///     +10..+2F scanned data, 16 bits per row
///
/// The ROM's keyboard driver programs a scan and reads the data registers; the
/// emulated matrix is sampled row by row with the programmed timing, exactly as the
/// hardware does, so the ROM sees key presses through its own scanning code.
public final class Keypad: IODevice {
    /// Live state of the physical switches (bit set = pressed), per group.
    public private(set) var matrix = [UInt16](repeating: 0, count: 16)
    public private(set) var onKeyDown = false

    public private(set) var control: UInt32 = 0
    public private(set) var rows: UInt8 = 8
    public private(set) var columns: UInt8 = 8
    public private(set) var status: UInt8 = 0
    public private(set) var enable: UInt8 = 0
    public private(set) var data = [UInt16](repeating: 0, count: 16)
    public private(set) var gpioEnable: UInt32 = 0
    private var scanRow = 0
    private var scanChanged = false

    unowned(unsafe) let scheduler: Scheduler
    unowned(unsafe) let interrupts: InterruptController

    init(scheduler: Scheduler, interrupts: InterruptController) {
        self.scheduler = scheduler
        self.interrupts = interrupts
    }

    public func reset() {
        control = 0; rows = 8; columns = 8; status = 0; enable = 0
        data = [UInt16](repeating: 0, count: 16)
        gpioEnable = 0
        scanRow = 0
        scheduler.cancel(.keypadScan)
        updateInterrupt()
    }

    public var mode: UInt8 { UInt8(control & 3) }
    private var rowWait: UInt64 { UInt64((control >> 2) & 0x3FFF) }
    private var scanWait: UInt64 { UInt64(control >> 16) }

    // MARK: Host input

    public func setKey(_ key: KeyPosition, pressed: Bool) {
        if key.isOn {
            onKeyDown = pressed
            interrupts.set(InterruptSource.on, pressed)
            return
        }
        guard key.group < 16, key.bit < 16 else { return }
        let bit = UInt16(1) << UInt16(key.bit)
        if pressed { matrix[key.group] |= bit } else { matrix[key.group] &= ~bit }
        if mode == 1 { anyKeyCheck() }
    }

    public func releaseAll() {
        for i in matrix.indices { matrix[i] = 0 }
        if onKeyDown { onKeyDown = false; interrupts.set(InterruptSource.on, false) }
    }

    public func isPressed(_ key: KeyPosition) -> Bool {
        key.isOn ? onKeyDown : matrix[key.group] & (1 << UInt16(key.bit)) != 0
    }

    // MARK: Scanning

    private func anyKeyCheck() {
        if matrix.contains(where: { $0 != 0 }) {
            status |= 4
            updateInterrupt()
        }
    }

    private func startScan() {
        scanRow = 0
        scanChanged = false
        scheduler.schedule(.keypadScan, after: max(1, rowWait) * Scheduler.ticksPer6MHz)
    }

    /// Scheduler callback: samples one row, or finishes a scan.
    func handleEvent() {
        let m = mode
        guard m >= 2 else { return }
        let rowCount = min(Int(rows), 16)
        if scanRow < rowCount {
            let colMask: UInt16 = columns >= 16 ? 0xFFFF : UInt16((1 << Int(columns)) - 1)
            let v = matrix[scanRow] & colMask
            if data[scanRow] != v { data[scanRow] = v; scanChanged = true }
            scanRow += 1
            scheduler.schedule(.keypadScan, after: max(1, rowWait) * Scheduler.ticksPer6MHz)
            return
        }
        // Scan complete.
        status |= 1
        if scanChanged { status |= 2 }
        if data.contains(where: { $0 != 0 }) { status |= 4 }
        scanRow = 0
        scanChanged = false
        if m == 3 {
            scheduler.schedule(.keypadScan, after: max(1, scanWait + rowWait) * Scheduler.ticksPer6MHz)
        } else {
            control &= ~3                     // single scan finished: back to idle
        }
        updateInterrupt()
    }

    private func updateInterrupt() {
        interrupts.set(InterruptSource.keypad, status & enable & 7 != 0)
    }

    // MARK: Registers

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00..<0x04: return byteOf(control, o)
        case 0x04: return rows
        case 0x05: return columns
        case 0x08: return status
        case 0x0C: return enable
        case 0x10..<0x30:
            let row = (o - 0x10) >> 1
            return o & 1 == 0 ? UInt8(truncatingIfNeeded: data[row]) : UInt8(truncatingIfNeeded: data[row] >> 8)
        case 0x40..<0x44: return byteOf(gpioEnable, o)
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x00..<0x04:
            let oldMode = mode
            setByte(&control, o, value)
            if o == 0 {
                let m = mode
                if m >= 2 && (oldMode < 2 || !scheduler.isScheduled(.keypadScan)) { startScan() }
                if m < 2 { scheduler.cancel(.keypadScan) }
                if m == 1 { anyKeyCheck() }
            }
        case 0x04: rows = value
        case 0x05: columns = value
        case 0x08:
            status &= ~value
            // In any-key mode the detector keeps asserting while a key is held.
            if mode == 1 { anyKeyCheck() }
            updateInterrupt()
        case 0x0C:
            enable = value & 7
            updateInterrupt()
        case 0x40..<0x44: setByte(&gpioEnable, o, value)
        default: break
        }
    }

    public struct State: Codable, Equatable {
        var control: UInt32; var rows, columns, status, enable: UInt8
        var data: [UInt16]; var gpioEnable: UInt32; var scanRow: Int
    }

    public var state: State {
        get { State(control: control, rows: rows, columns: columns, status: status, enable: enable, data: data, gpioEnable: gpioEnable, scanRow: scanRow) }
        set {
            control = newValue.control; rows = newValue.rows; columns = newValue.columns
            status = newValue.status; enable = newValue.enable; data = newValue.data
            gpioEnable = newValue.gpioEnable; scanRow = newValue.scanRow
            updateInterrupt()
        }
    }
}
