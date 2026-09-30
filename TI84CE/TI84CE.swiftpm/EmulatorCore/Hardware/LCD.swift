import Foundation

/// A rendered LCD frame in RGBA8888 (row-major, top-left origin), exactly what the
/// panel glass shows.
public struct LCDFrame {
    public static let width = 320
    public static let height = 240

    public var width: Int
    public var height: Int
    /// width * height * 4 bytes, RGBA.
    public var pixels: [UInt8]
    /// Increments whenever the displayed image changes.
    public var serial: UInt64

    public init(width: Int = LCDFrame.width, height: Int = LCDFrame.height) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        serial = 0
    }
}

/// ARM PrimeCell PL111 colour LCD controller (port range 4xxx, memory-mapped at
/// 0xE30000). Once per frame it DMAs the framebuffer at `upbase` (0xD40000 for the
/// OS) and streams the pixels to the panel over the RGB interface.
///
///     +000..+00C timing 0-3   +010 upper panel base   +014 lower panel base
///     +018 control: bit0 enable, bits1-3 bpp, bit5 TFT, bit8 BGR, bit9 BEBO,
///                   bit10 BEPO, bit11 power, bits12-13 vertical compare point
///     +01C int mask  +020 raw int status  +024 masked int status  +028 int clear
///     +02C/+030 current base addresses   +200..+3FF palette   +800.. cursor
///
/// Note the OS programs the controller for 240-pixel lines x 320 lines (the panel's
/// native portrait scan); the panel's own address counter (see `LCDPanel`) places
/// the linear pixel stream into its 320x240 window.
public final class LCDController: IODevice {
    public private(set) var timing = [UInt32](repeating: 0, count: 4)
    public private(set) var upbase: UInt32 = 0
    public private(set) var lpbase: UInt32 = 0
    public private(set) var control: UInt32 = 0
    public private(set) var imsc: UInt32 = 0
    public private(set) var ris: UInt32 = 0
    public private(set) var palette = [UInt8](repeating: 0, count: 0x200)
    public private(set) var cursor = [UInt8](repeating: 0, count: 0x400)

    unowned let scheduler: Scheduler
    unowned let interrupts: InterruptController
    unowned let bus: MemoryBus
    unowned let panel: LCDPanel

    /// Most recent displayed frame (only touched by the emulation thread).
    public private(set) var frame = LCDFrame()
    public private(set) var framesRendered: UInt64 = 0
    /// Called on the emulation thread whenever `frame` changes.
    public var onFrame: ((LCDFrame) -> Void)?

    init(scheduler: Scheduler, interrupts: InterruptController, bus: MemoryBus, panel: LCDPanel) {
        self.scheduler = scheduler
        self.interrupts = interrupts
        self.bus = bus
        self.panel = panel
    }

    public func reset() {
        timing = [0, 0, 0, 0]
        upbase = 0; lpbase = 0; control = 0; imsc = 0; ris = 0
        palette = [UInt8](repeating: 0, count: 0x200)
        cursor = [UInt8](repeating: 0, count: 0x400)
        scheduler.cancel(.lcdFrame)
        updateInterrupt()
    }

    public var enabled: Bool { control & 1 != 0 }
    public var powered: Bool { control & 0x800 != 0 }
    public var bppMode: Int { Int((control >> 1) & 7) }

    public var pixelsPerLine: Int { Int(((timing[0] >> 2) & 0x3F) + 1) * 16 }
    public var linesPerPanel: Int { Int(timing[1] & 0x3FF) + 1 }

    /// Frame period in base ticks derived from the programmed timings, assuming the
    /// 24 MHz LCD clock; clamped to a sane 20-120 Hz window.
    public var framePeriod: UInt64 {
        let t0 = timing[0], t1 = timing[1], t2 = timing[2]
        let ppl = UInt64(pixelsPerLine)
        let hsw = UInt64((t0 >> 8) & 0xFF) + 1
        let hfp = UInt64((t0 >> 16) & 0xFF) + 1
        let hbp = UInt64(t0 >> 24) + 1
        let lpp = UInt64(linesPerPanel)
        let vsw = UInt64((t1 >> 10) & 0x3F) + 1
        let vfp = UInt64((t1 >> 16) & 0xFF)
        let vbp = UInt64(t1 >> 24)
        let pcd = UInt64((t2 & 0x1F) | ((t2 >> 27) << 5))
        let divider = (t2 >> 26) & 1 != 0 ? 1 : pcd + 2
        let clocks = (ppl + hsw + hfp + hbp) * (lpp + vsw + vfp + vbp) * divider
        let ticks = clocks * 64                          // 24 MHz = 64 base ticks
        let minT = Scheduler.baseHz / 120, maxT = Scheduler.baseHz / 20
        return ticks < minT || ticks > maxT ? Scheduler.baseHz / 60 : ticks
    }

    private func updateInterrupt() {
        interrupts.set(InterruptSource.lcd, ris & imsc & 0x1E != 0)
    }

    private func scheduleFrame() {
        if enabled {
            if !scheduler.isScheduled(.lcdFrame) { scheduler.schedule(.lcdFrame, after: framePeriod) }
        } else {
            scheduler.cancel(.lcdFrame)
        }
    }

    /// Scheduler callback at each frame boundary: latch the base address, raise the
    /// base-update and vertical-compare interrupts and stream the framebuffer.
    func handleEvent() {
        guard enabled else { return }
        ris |= 0x04 | 0x08
        updateInterrupt()
        render()
        scheduler.schedule(.lcdFrame, after: framePeriod)
    }

    /// Streams one frame to the panel (if the controller is running) and publishes
    /// the panel image if it changed.
    public func render() {
        if enabled && powered {
            stream()
        }
        framesRendered += 1
        var next = frame
        let changed = next.pixels.withUnsafeMutableBytes { raw -> Bool in
            panel.present(into: raw.bindMemory(to: UInt32.self))
        }
        if changed {
            next.serial = frame.serial &+ 1
            frame = next
            onFrame?(frame)
        }
    }

    @inline(__always) private func rgba(r: UInt32, g: UInt32, b: UInt32) -> UInt32 {
        0xFF00_0000 | (b << 16) | (g << 8) | r
    }

    private func paletteColor(_ index: Int, bgr: Bool) -> UInt32 {
        let v = UInt32(palette[index * 2]) | UInt32(palette[index * 2 + 1]) << 8
        var lo = (v & 0x1F), hi = (v >> 10) & 0x1F
        let g = (v >> 5) & 0x1F
        if bgr { swap(&lo, &hi) }
        let i = (v >> 15) & 1
        let r6 = lo << 1 | i, g6 = g << 1 | i, b6 = hi << 1 | i
        return rgba(r: r6 << 2 | r6 >> 4, g: g6 << 2 | g6 >> 4, b: b6 << 2 | b6 >> 4)
    }

    /// DMA + pixel formatter: converts the framebuffer to RGB and feeds the panel.
    private func stream() {
        let total = pixelsPerLine * linesPerPanel
        let bgr = control & 0x100 != 0
        let bepo = control & 0x400 != 0
        var addr = upbase & 0xFF_FFF8
        let mode = bppMode
        let ram = bus.ram.bytes
        let ramSize = UInt32(RAM.size)

        @inline(__always) func byte(_ a: UInt32) -> UInt32 {
            // Fast path for VRAM in RAM; anything else goes through the bus.
            let o = a &- 0xD00000
            return o < ramSize ? UInt32(ram[Int(o)]) : UInt32(bus.peek(a))
        }

        panel.beginFrame()
        switch mode {
        case 4, 6, 7:
            // 16 bpp (1:5:5:5, 5:6:5) or 12 bpp (4:4:4), two bytes per pixel.
            for _ in 0..<total {
                let v = byte(addr) | byte(addr &+ 1) << 8
                addr &+= 2
                var r: UInt32, g: UInt32, b: UInt32
                switch mode {
                case 6:
                    r = v & 0x1F; g = (v >> 5) & 0x3F; b = (v >> 11) & 0x1F
                    if bgr { swap(&r, &b) }
                    r = r << 3 | r >> 2; g = g << 2 | g >> 4; b = b << 3 | b >> 2
                case 4:
                    r = v & 0x1F; g = (v >> 5) & 0x1F; b = (v >> 10) & 0x1F
                    if bgr { swap(&r, &b) }
                    r = r << 3 | r >> 2; g = g << 3 | g >> 2; b = b << 3 | b >> 2
                default:
                    r = v & 0xF; g = (v >> 4) & 0xF; b = (v >> 8) & 0xF
                    if bgr { swap(&r, &b) }
                    r *= 17; g *= 17; b *= 17
                }
                panel.pushPixel(rgba(r: r, g: g, b: b))
            }
        case 5:
            // 24 bpp stored in 32-bit words.
            for _ in 0..<total {
                var r = byte(addr), g = byte(addr &+ 1), b = byte(addr &+ 2)
                addr &+= 4
                if bgr { swap(&r, &b) }
                panel.pushPixel(rgba(r: r, g: g, b: b))
            }
        default:
            // 1/2/4/8 bpp through the palette.
            let bpp = 1 << mode
            let perByte = 8 / bpp
            let pmask = UInt32((1 << bpp) - 1)
            var lut = [UInt32](repeating: 0, count: 1 << bpp)
            for i in 0..<lut.count { lut[i] = paletteColor(i, bgr: bgr) }
            var n = 0
            while n < total {
                let v = byte(addr)
                addr &+= 1
                for k in 0..<perByte where n < total {
                    let slot = bepo ? (perByte - 1 - k) : k
                    panel.pushPixel(lut[Int((v >> UInt32(slot * bpp)) & pmask)])
                    n += 1
                }
            }
        }
    }

    // MARK: Registers

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x000..<0x010: return byteOf(timing[o >> 2], o)
        case 0x010..<0x014: return byteOf(upbase, o)
        case 0x014..<0x018: return byteOf(lpbase, o)
        case 0x018..<0x01C: return byteOf(control, o)
        case 0x01C..<0x020: return byteOf(imsc, o)
        case 0x020..<0x024: return byteOf(ris, o)
        case 0x024..<0x028: return byteOf(ris & imsc, o)
        case 0x02C..<0x030: return byteOf(upbase, o)
        case 0x030..<0x034: return byteOf(lpbase, o)
        case 0x200..<0x400: return palette[o - 0x200]
        case 0x800..<0xC00: return cursor[o - 0x800]
        case 0xFE0..<0x1000:
            let id: [UInt8] = [0x11, 0x11, 0x14, 0x00, 0x0D, 0xF0, 0x05, 0xB1]
            return (o & 3) == 0 ? id[(o - 0xFE0) >> 2] : 0
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x000..<0x010: setByte(&timing[o >> 2], o, value)
        case 0x010..<0x014:
            setByte(&upbase, o, value)
            upbase &= 0xFF_FFF8
        case 0x014..<0x018:
            setByte(&lpbase, o, value)
            lpbase &= 0xFF_FFF8
        case 0x018..<0x01C:
            setByte(&control, o, value)
            scheduleFrame()
        case 0x01C..<0x020:
            setByte(&imsc, o, value)
            imsc &= 0x1E
            updateInterrupt()
        case 0x028..<0x02C:
            ris &= ~(UInt32(value) << (UInt32(o & 3) * 8))
            updateInterrupt()
        case 0x200..<0x400: palette[o - 0x200] = value
        case 0x800..<0xC00: cursor[o - 0x800] = value
        default: break
        }
    }

    public struct State: Codable, Equatable {
        var timing: [UInt32]; var upbase, lpbase, control, imsc, ris: UInt32
        var palette: [UInt8]; var cursor: [UInt8]
    }

    public var state: State {
        get { State(timing: timing, upbase: upbase, lpbase: lpbase, control: control, imsc: imsc, ris: ris, palette: palette, cursor: cursor) }
        set {
            timing = newValue.timing; upbase = newValue.upbase; lpbase = newValue.lpbase
            control = newValue.control; imsc = newValue.imsc; ris = newValue.ris
            palette = newValue.palette; cursor = newValue.cursor
            updateInterrupt()
            scheduleFrame()
        }
    }
}

/// The LCD panel's own controller (ST7789-class, 320x240 landscape glass).
///
/// It is wired as a 3-wire serial device for commands: every word is 9 bits, a D/C
/// bit (1 = data) followed by 8 bits MSB first. The ROM may split a word over
/// several SPI frames of any length, so the panel consumes a raw bit stream.
///
/// Pixels arrive over the RGB interface and are written into panel RAM through the
/// column/row window (CASET/RASET) using the address order selected by MADCTL
/// (MY/MX mirror, MV exchanges rows and columns). The glass shows panel RAM.
public final class LCDPanel {
    public static let columns = 320
    public static let rows = 240

    public private(set) var sleeping = true
    public private(set) var displayOn = false
    public private(set) var inverted = false
    public private(set) var madctl: UInt8 = 0
    public private(set) var colmod: UInt8 = 0x66
    public private(set) var columnStart = 0, columnEnd = LCDPanel.columns - 1
    public private(set) var rowStart = 0, rowEnd = LCDPanel.rows - 1

    private var command: UInt8 = 0
    private var params: [UInt8] = []
    private var shiftIn: UInt16 = 0
    private var bitCount = 0
    private var readBits: [Bool] = []

    /// Panel RAM, RGBA pixels, row-major 320x240.
    public private(set) var gram: [UInt32]
    // Address counter.
    private var curCol = 0, curRow = 0

    /// Optional log of panel traffic (debugging): (isCommand, byte).
    public var trace: ((Bool, UInt8) -> Void)?

    public init() {
        gram = [UInt32](repeating: 0xFFFF_FFFF, count: LCDPanel.columns * LCDPanel.rows)
    }

    public func reset() {
        sleeping = true; displayOn = false; inverted = false
        madctl = 0; colmod = 0x66; command = 0; params = []
        columnStart = 0; columnEnd = LCDPanel.columns - 1
        rowStart = 0; rowEnd = LCDPanel.rows - 1
        shiftIn = 0; bitCount = 0; readBits = []
        curCol = 0; curRow = 0
    }

    public var displayVisible: Bool { !sleeping && displayOn }

    // MARK: Serial command interface

    /// Clocks one bit in (MOSI) and returns the bit driven out (MISO).
    public func clock(_ bit: Bool) -> Bool {
        let out = readBits.isEmpty ? false : readBits.removeFirst()
        shiftIn = (shiftIn << 1) | (bit ? 1 : 0)
        bitCount += 1
        if bitCount == 9 {
            let word = shiftIn & 0x1FF
            shiftIn = 0
            bitCount = 0
            trace?(word & 0x100 == 0, UInt8(word & 0xFF))
            if word & 0x100 != 0 { writeData(UInt8(word & 0xFF)) } else { writeCommand(UInt8(word & 0xFF)) }
        }
        return out
    }

    public func writeCommand(_ c: UInt8) {
        command = c
        params = []
        readBits = []
        var reply: [UInt8] = []
        switch c {
        case 0x01:                                    // software reset
            let keep = gram
            reset()
            gram = keep
        case 0x10: sleeping = true
        case 0x11: sleeping = false
        case 0x20: inverted = false
        case 0x21: inverted = true
        case 0x28: displayOn = false
        case 0x29: displayOn = true
        case 0x2C: beginFrame()                       // RAMWR restarts the address counter
        case 0x04: reply = [0x85, 0x85, 0x52]         // RDDID
        case 0xDA: reply = [0x85]
        case 0xDB: reply = [0x85]
        case 0xDC: reply = [0x52]
        default: break
        }
        if !reply.isEmpty {
            // One dummy clock precedes multi-byte reads in 3-wire mode.
            readBits = (reply.count > 1 ? [false] : []) + reply.flatMap { b in (0..<8).map { b & (0x80 >> $0) != 0 } }
        }
    }

    public func writeData(_ d: UInt8) {
        params.append(d)
        switch (command, params.count) {
        case (0x36, 1): madctl = d
        case (0x3A, 1): colmod = d
        case (0x2A, 4):
            columnStart = Int(params[0]) << 8 | Int(params[1])
            columnEnd = Int(params[2]) << 8 | Int(params[3])
        case (0x2B, 4):
            rowStart = Int(params[0]) << 8 | Int(params[1])
            rowEnd = Int(params[2]) << 8 | Int(params[3])
        default: break
        }
    }

    // MARK: Pixel interface

    /// Start of a frame (VSYNC) or RAMWR: the address counter returns to the window start.
    public func beginFrame() {
        curCol = columnStart
        curRow = rowStart
    }

    private var exchange: Bool { madctl & 0x20 != 0 }

    @inline(__always) public func pushPixel(_ color: UInt32) {
        // Logical address -> panel RAM position.
        var x = curCol, y = curRow
        if exchange { swap(&x, &y) }
        if madctl & 0x40 != 0 { x = LCDPanel.columns - 1 - x }
        if madctl & 0x80 != 0 { y = LCDPanel.rows - 1 - y }
        if x >= 0 && x < LCDPanel.columns && y >= 0 && y < LCDPanel.rows {
            gram[y * LCDPanel.columns + x] = color
        }
        // Advance: columns first (rows first when MV swaps the axes, which the
        // swap above already accounts for), wrapping inside the window.
        curCol += 1
        if curCol > columnEnd {
            curCol = columnStart
            curRow += 1
            if curRow > rowEnd { curRow = rowStart }
        }
    }

    /// Writes what the glass shows into `out`; returns true if anything changed.
    func present(into out: UnsafeMutableBufferPointer<UInt32>) -> Bool {
        var changed = false
        if !displayVisible {
            for i in 0..<out.count where out[i] != 0xFF00_0000 { out[i] = 0xFF00_0000; changed = true }
            return changed
        }
        let invert: UInt32 = inverted ? 0x00FF_FFFF : 0
        gram.withUnsafeBufferPointer { g in
            for i in 0..<min(out.count, g.count) {
                let c = g[i] ^ invert
                if out[i] != c { out[i] = c; changed = true }
            }
        }
        return changed
    }

    public struct State: Codable, Equatable {
        var sleeping, displayOn, inverted: Bool; var madctl, colmod, command: UInt8
        var window: [Int]; var shiftIn: UInt16; var bitCount: Int
    }
    public var state: State {
        get {
            State(sleeping: sleeping, displayOn: displayOn, inverted: inverted, madctl: madctl, colmod: colmod, command: command,
                  window: [columnStart, columnEnd, rowStart, rowEnd], shiftIn: shiftIn, bitCount: bitCount)
        }
        set {
            sleeping = newValue.sleeping; displayOn = newValue.displayOn; inverted = newValue.inverted
            madctl = newValue.madctl; colmod = newValue.colmod; command = newValue.command
            if newValue.window.count == 4 {
                columnStart = newValue.window[0]; columnEnd = newValue.window[1]
                rowStart = newValue.window[2]; rowEnd = newValue.window[3]
            }
            shiftIn = newValue.shiftIn; bitCount = newValue.bitCount; readBits = []; params = []
        }
    }
}

/// ARM PL022-style synchronous serial port (port range Dxxx, memory-mapped at
/// 0xF80000), connecting the CPU to the LCD panel controller.
///
///     +00 CR0  +04 CR1 (bits 16-20: frame length - 1)  +08 CR2 (bit0 enable,
///     bit2/3 clear RX/TX FIFO, bit7 TX enable, bit8 RX enable)
///     +0C status: bit1 TX FIFO not full, bit2 busy, bits4-8 RX entries, bits12-16 TX entries
///     +18 data FIFO
///
/// Transfers complete instantly, so the TX FIFO is always empty and never busy.
public final class SPIController: IODevice {
    public private(set) var cr0: UInt32 = 0
    public private(set) var cr1: UInt32 = 0
    public private(set) var cr2: UInt32 = 0
    public private(set) var intCtrl: UInt32 = 0
    private var rxFIFO: [UInt32] = []
    private var txShift: UInt32 = 0

    unowned let panel: LCDPanel

    init(panel: LCDPanel) { self.panel = panel }

    public func reset() {
        cr0 = 0; cr1 = 0; cr2 = 0; intCtrl = 0; rxFIFO = []; txShift = 0
    }

    private var frameBits: Int { Int((cr1 >> 16) & 0x1F) + 1 }

    /// Shifts one frame out to the panel, MSB first, capturing the reply bits.
    private func transfer(_ v: UInt32) {
        let bits = frameBits
        var rx: UInt32 = 0
        for i in stride(from: bits - 1, through: 0, by: -1) {
            let out = panel.clock(v & (1 << UInt32(i)) != 0)
            rx = rx << 1 | (out ? 1 : 0)
        }
        if cr2 & 0x100 != 0 && rxFIFO.count < 16 {
            rxFIFO.append(rx)
        }
    }

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00..<0x04: return byteOf(cr0, o)
        case 0x04..<0x08: return byteOf(cr1, o)
        case 0x08..<0x0C: return byteOf(cr2, o)
        case 0x0C..<0x10:
            let rx = UInt32(rxFIFO.count)
            let status: UInt32 = (rx << 4) | 0x2 | (rx == 16 ? 1 : 0)
            return byteOf(status, o)
        case 0x10..<0x14: return byteOf(intCtrl, o)
        case 0x18..<0x1C:
            if o == 0x18 { txShift = rxFIFO.isEmpty ? 0 : rxFIFO.removeFirst() }
            return byteOf(txShift, o)
        case 0x60..<0x64: return byteOf(0x0001_2100, o)     // revision
        case 0x64..<0x68: return byteOf(0x0E0F_0F1F, o)     // FIFO depths / widths
        default: return 0
        }
    }

    public func peek(_ offset: UInt16) -> UInt8 {
        offset >= 0x18 && offset < 0x1C ? byteOf(txShift, Int(offset)) : read(offset)
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x00..<0x04: setByte(&cr0, o, value)
        case 0x04..<0x08: setByte(&cr1, o, value)
        case 0x08..<0x0C:
            setByte(&cr2, o, value)
            if cr2 & 0x04 != 0 { rxFIFO.removeAll(); cr2 &= ~0x04 }
            cr2 &= ~0x08
        case 0x10..<0x14: setByte(&intCtrl, o, value)
        case 0x18..<0x1C:
            setByte(&txShift, o, value)
            // A frame is committed when its most significant byte is written.
            let lastByte = (frameBits - 1) / 8
            if o - 0x18 == lastByte {
                transfer(txShift)
                txShift = 0
            }
        default: break
        }
    }

    public struct State: Codable, Equatable { var cr0, cr1, cr2, intCtrl: UInt32; var rx: [UInt32] }
    public var state: State {
        get { State(cr0: cr0, cr1: cr1, cr2: cr2, intCtrl: intCtrl, rx: rxFIFO) }
        set { cr0 = newValue.cr0; cr1 = newValue.cr1; cr2 = newValue.cr2; intCtrl = newValue.intCtrl; rxFIFO = newValue.rx }
    }
}
