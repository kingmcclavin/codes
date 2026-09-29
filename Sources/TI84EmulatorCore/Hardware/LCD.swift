/// A rendered 96×64 frame of the calculator screen.
///
/// `pixels` holds one byte per pixel in row-major order: 0 = pixel off
/// (clear), 255 = pixel fully on (dark). Intermediate values appear when LCD
/// persistence is enabled, reproducing the slow response of the real panel
/// that grayscale programs depend on.
public struct LCDFrame: Equatable, Sendable {
    public static let width = 96
    public static let height = 64

    public var pixels: [UInt8]
    /// Contrast setting 0...63 (the OS default is around 0x18–0x30).
    public var contrast: UInt8
    /// False when the display has been switched off (e.g. calculator powered down).
    public var isDisplayOn: Bool
    /// Increases every time the frame content changes.
    public var sequence: UInt64

    public init(pixels: [UInt8] = [UInt8](repeating: 0, count: LCDFrame.width * LCDFrame.height),
                contrast: UInt8 = 32, isDisplayOn: Bool = false, sequence: UInt64 = 0) {
        self.pixels = pixels
        self.contrast = contrast
        self.isDisplayOn = isDisplayOn
        self.sequence = sequence
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * LCDFrame.width + x]
    }

    public func isOn(x: Int, y: Int) -> Bool { self[x, y] >= 128 }

    /// Text rendering for logs and tests ("#" = on).
    public var asciiArt: String {
        var s = ""
        for y in 0..<LCDFrame.height {
            for x in 0..<LCDFrame.width { s.append(isOn(x: x, y: y) ? "#" : ".") }
            s.append("\n")
        }
        return s
    }
}

/// Toshiba T6A04 LCD driver as wired in the TI-84 Plus (ports 10h/11h,
/// mirrored at 12h/13h).
///
/// The controller has 120×64 bits of display RAM, of which the leftmost 96
/// columns are visible. The CPU talks to it with commands on the control
/// port and reads/writes pixel data on the data port, 8 or 6 bits at a time,
/// with auto-increment in one of four directions. Reads return the value
/// latched by the previous access (the first read after an address change is
/// a "dummy read"), as on the real chip.
public final class T6A04: IODevice {
    public static let memoryColumns = 120
    public static let rows = 64
    public static let stride = memoryColumns / 8

    public enum CounterMode: UInt8, Codable, Sendable {
        case rowDecrement = 4, rowIncrement = 5, columnDecrement = 6, columnIncrement = 7
    }

    /// Display RAM, `stride` bytes per row, MSB = leftmost pixel.
    public private(set) var memory = [UInt8](repeating: 0, count: T6A04.stride * T6A04.rows)

    public private(set) var displayOn = false
    public private(set) var eightBitMode = true
    public private(set) var counterMode: CounterMode = .columnIncrement
    public private(set) var row = 0
    public private(set) var column = 0
    /// Z address: first memory row shown on the top line of the screen.
    public private(set) var rowShift = 0
    public private(set) var contrast: UInt8 = 32
    private var readLatch: UInt8 = 0

    /// Incremented on every change that affects the visible image.
    public private(set) var version: UInt64 = 0

    /// Busy time after each access, in master ticks. Accesses during this
    /// window are ignored when `enforceBusyTiming` is set (as on hardware);
    /// the busy flag is reported either way.
    public var busyTicks = EmulatorClock.ticks(microseconds: 5)
    public var enforceBusyTiming = false
    private var busyUntil: UInt64 = 0

    unowned let clock: EmulatorClock

    /// Extra CPU wait states the ASIC inserts on each LCD port access at
    /// 15 MHz (configured through ports 29h–2Ch).
    var portDelayCycles: UInt64 = 0

    init(clock: EmulatorClock) {
        self.clock = clock
    }

    public func reset() {
        displayOn = false
        eightBitMode = true
        counterMode = .columnIncrement
        row = 0
        column = 0
        rowShift = 0
        contrast = 32
        readLatch = 0
        busyUntil = 0
        version &+= 1
    }

    public var isBusy: Bool { clock.now < busyUntil }

    public var status: UInt8 {
        (isBusy ? 0x80 : 0) | (eightBitMode ? 0x40 : 0) | (displayOn ? 0x20 : 0) | (counterMode.rawValue & 0x03)
    }

    // MARK: IODevice

    public func read(port: UInt8) -> UInt8 {
        clock.cpu.cycles &+= portDelayCycles
        if port & 1 == 0 { return status }
        return readData()
    }

    public func write(port: UInt8, value: UInt8) {
        clock.cpu.cycles &+= portDelayCycles
        if port & 1 == 0 {
            command(value)
        } else {
            writeData(value)
        }
    }

    // MARK: Commands

    public func command(_ value: UInt8) {
        if enforceBusyTiming && isBusy { return }
        switch value {
        case 0x00, 0x01:
            eightBitMode = value == 0x01
        case 0x02, 0x03:
            displayOn = value == 0x03
            version &+= 1
        case 0x04...0x07:
            counterMode = CounterMode(rawValue: value)!
        case 0x20...0x3F:
            column = Int(value - 0x20)
        case 0x40...0x7F:
            rowShift = Int(value - 0x40)
            version &+= 1
        case 0x80...0xBF:
            row = Int(value - 0x80)
        case 0xC0...0xFF:
            contrast = value - 0xC0
            version &+= 1
        default:
            // 08h–1Fh: test mode / op-amp power control; no visible effect.
            break
        }
        markBusy()
    }

    private var columnLimit: Int { eightBitMode ? T6A04.stride : (T6A04.memoryColumns + 5) / 6 }

    private func wrapCursor() {
        let limit = columnLimit
        if column >= limit { column = 0 } else if column < 0 { column = limit - 1 }
        if row >= T6A04.rows { row = 0 } else if row < 0 { row = T6A04.rows - 1 }
    }

    private func advanceCursor() {
        switch counterMode {
        case .rowDecrement: row -= 1
        case .rowIncrement: row += 1
        case .columnDecrement: column -= 1
        case .columnIncrement: column += 1
        }
    }

    public func writeData(_ value: UInt8) {
        if enforceBusyTiming && isBusy { return }
        wrapCursor()
        let base = row * T6A04.stride
        if eightBitMode {
            memory[base + column] = value
        } else {
            // 6-bit mode: bits 5..0 of `value` land at pixel column 6*column.
            let bit = column * 6
            let offset = base + bit / 8
            let shift = bit % 8
            let sprite = (UInt16(value & 0x3F) << 10) >> UInt16(shift)   // aligned to the high bits of 16
            let mask = UInt16(0xFC00) >> UInt16(shift)
            let hi = UInt8(truncatingIfNeeded: sprite >> 8), hiMask = UInt8(truncatingIfNeeded: mask >> 8)
            memory[offset] = (memory[offset] & ~hiMask) | hi
            let lo = UInt8(truncatingIfNeeded: sprite), loMask = UInt8(truncatingIfNeeded: mask)
            if loMask != 0 && offset + 1 < base + T6A04.stride {
                memory[offset + 1] = (memory[offset + 1] & ~loMask) | lo
            }
        }
        advanceCursor()
        version &+= 1
        markBusy()
    }

    public func readData() -> UInt8 {
        if enforceBusyTiming && isBusy { return 0 }
        let result = readLatch
        wrapCursor()
        let base = row * T6A04.stride
        if eightBitMode {
            readLatch = memory[base + column]
        } else {
            let bit = column * 6
            let offset = base + bit / 8
            let hi = UInt16(memory[offset])
            let lo = offset + 1 < base + T6A04.stride ? UInt16(memory[offset + 1]) : 0
            readLatch = UInt8(truncatingIfNeeded: ((hi << 8 | lo) >> UInt16(10 - bit % 8)) & 0x3F)
        }
        advanceCursor()
        markBusy()
        return result
    }

    private func markBusy() {
        busyUntil = clock.now &+ busyTicks
    }

    // MARK: Output

    /// Whether the visible pixel at (x, y) is set in display RAM.
    public func pixel(x: Int, y: Int) -> Bool {
        let memoryRow = (y + rowShift) % T6A04.rows
        return memory[memoryRow * T6A04.stride + x / 8] & (0x80 >> UInt8(x % 8)) != 0
    }

    /// Writes the visible 96×64 image (0 or 255 per pixel) into `buffer`.
    public func renderVisible(into buffer: inout [UInt8]) {
        buffer.withUnsafeMutableBufferPointer { out in
            var i = 0
            for y in 0..<LCDFrame.height {
                let base = ((y + rowShift) % T6A04.rows) * T6A04.stride
                for byteIndex in 0..<(LCDFrame.width / 8) {
                    let byte = memory[base + byteIndex]
                    for bit in 0..<8 {
                        out[i] = byte & (0x80 >> UInt8(bit)) != 0 ? 255 : 0
                        i += 1
                    }
                }
            }
        }
    }

    // MARK: State

    var snapshot: LCDState {
        LCDState(memory: memory, displayOn: displayOn, eightBitMode: eightBitMode,
                 counterMode: counterMode, row: row, column: column, rowShift: rowShift,
                 contrast: contrast, readLatch: readLatch)
    }

    func restore(_ s: LCDState) {
        if s.memory.count == memory.count { memory = s.memory }
        displayOn = s.displayOn
        eightBitMode = s.eightBitMode
        counterMode = s.counterMode
        row = s.row
        column = s.column
        rowShift = s.rowShift
        contrast = s.contrast
        readLatch = s.readLatch
        busyUntil = 0
        version &+= 1
    }
}

public struct LCDState: Codable, Equatable, Sendable {
    var memory: [UInt8]
    var displayOn: Bool
    var eightBitMode: Bool
    var counterMode: T6A04.CounterMode
    var row: Int
    var column: Int
    var rowShift: Int
    var contrast: UInt8
    var readLatch: UInt8
}

/// Samples the LCD at a fixed refresh rate and produces `LCDFrame`s.
///
/// With `persistence` > 0 each frame blends toward the new image, emulating
/// the slow liquid-crystal response (which is what makes flicker-based
/// grayscale work on the real calculator). With 0, frames are exact 1-bit
/// snapshots.
public final class LCDFrameBuilder {
    public private(set) var frame = LCDFrame()
    /// 0 = no persistence ... 0.9 = very slow panel.
    public var persistence: Double = 0.0
    private var raw = [UInt8](repeating: 0, count: LCDFrame.width * LCDFrame.height)
    private var accumulated = [Double](repeating: 0, count: LCDFrame.width * LCDFrame.height)
    private var lastVersion: UInt64 = .max

    public init() {}

    /// Returns true when the published frame changed.
    @discardableResult
    func sample(_ lcd: T6A04) -> Bool {
        let blending = persistence > 0
        if lcd.version == lastVersion && !blending { return false }
        lastVersion = lcd.version
        lcd.renderVisible(into: &raw)
        var pixels = frame.pixels
        if blending {
            let keep = persistence
            for i in 0..<raw.count {
                accumulated[i] = accumulated[i] * keep + Double(raw[i]) * (1 - keep)
                pixels[i] = UInt8(accumulated[i].rounded())
            }
        } else {
            pixels = raw
            for i in 0..<raw.count { accumulated[i] = Double(raw[i]) }
        }
        let changed = pixels != frame.pixels || frame.contrast != lcd.contrast || frame.isDisplayOn != lcd.displayOn
        if changed {
            frame = LCDFrame(pixels: pixels, contrast: lcd.contrast, isDisplayOn: lcd.displayOn,
                             sequence: frame.sequence &+ 1)
        }
        return changed
    }

    func invalidate() { lastVersion = .max }
}
