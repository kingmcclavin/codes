import Foundation

/// An immutable copy of the machine state for the debugger UI, captured on the
/// emulation thread.
public struct DebugSnapshot {
    public struct Line: Identifiable {
        public let address: UInt32
        public let bytes: String
        public let text: String
        public let isCurrent: Bool
        public var id: UInt32 { address }
    }

    public struct NamedValue: Identifiable {
        public let name: String
        public let value: String
        public var id: String { name }
    }

    public var registers: Registers
    public var adl: Bool
    public var madl: Bool
    public var ief1: Bool
    public var ief2: Bool
    public var interruptMode: UInt8
    public var halted: Bool
    public var cycles: Int64
    public var cpuHz: UInt64
    public var emulatedSeconds: Double
    public var currentInstruction: String
    public var disassembly: [Line]
    public var stack: [NamedValue]
    public var memoryBase: UInt32
    public var memory: [UInt8]
    public var ioPort: UInt16
    public var ioBytes: [UInt8]
    public var interrupts: [NamedValue]
    public var lcd: [NamedValue]
    public var keypad: [NamedValue]
    public var timers: [NamedValue]
    public var lastUnsupported: String?

    public var sp: UInt32 { adl ? registers.spl : registers.sps }
    public var flags: String { Flag.describe(registers.f) }
}

extension Emulator {
    /// Captures the machine state. Must be called on the emulation thread.
    /// - Parameters:
    ///   - memoryAddress: start of the 256-byte memory view.
    ///   - ioPort: start of the 16-byte I/O port view (read with `peek`, no side effects).
    public func debugSnapshot(memoryAddress: UInt32, ioPort: UInt16) -> DebugSnapshot {
        let r = cpu.registers
        let dis = Disassembler(read: { [bus] in bus.peek($0) })
        let pcAddress = cpu.adl ? r.pc : (UInt32(r.mbase) << 16) | (r.pc & 0xFFFF)

        var lines: [DebugSnapshot.Line] = []
        var a = pcAddress
        for i in 0..<12 {
            let ins = dis.decode(at: a, adl: cpu.adl, mbase: r.mbase)
            lines.append(.init(address: a,
                               bytes: ins.bytes.map { String(format: "%02X", $0) }.joined(separator: " "),
                               text: ins.text, isCurrent: i == 0))
            a &+= UInt32(ins.length)
        }

        let sp = cpu.adl ? r.spl : (UInt32(r.mbase) << 16) | r.sps
        let width: UInt32 = cpu.adl ? 3 : 2
        let stack = (0..<8).map { i -> DebugSnapshot.NamedValue in
            let addr = sp &+ UInt32(i) * width
            var v: UInt32 = 0
            for b in 0..<width { v |= UInt32(bus.peek(addr &+ b)) << (8 * b) }
            return .init(name: String(format: "%06X", addr), value: String(format: cpu.adl ? "%06X" : "%04X", v))
        }

        let base = memoryAddress & 0xFF_FFF0
        let memory = (0..<256).map { bus.peek(base &+ UInt32($0)) }
        let ioBytes = (0..<16).map { io.peek(ioPort &+ UInt16($0)) }

        let ic = interrupts.state
        let names = InterruptSource.names.sorted { $0.key < $1.key }
        let pendingNames = names.filter { ic.banks[0].status & (1 << UInt32($0.key)) != 0 }.map { $0.value }
        let enabledNames = names.filter { ic.banks[0].enabled & (1 << UInt32($0.key)) != 0 }.map { $0.value }
        let interruptInfo: [DebugSnapshot.NamedValue] = [
            .init(name: "Enabled", value: String(format: "%06X", ic.banks[0].enabled)),
            .init(name: "Status", value: String(format: "%06X", ic.banks[0].status)),
            .init(name: "Latched", value: String(format: "%06X", ic.banks[0].latched)),
            .init(name: "Raw lines", value: String(format: "%06X", ic.raw)),
            .init(name: "IRQ line", value: cpu.irq ? "asserted" : "idle"),
            .init(name: "Pending", value: pendingNames.isEmpty ? "—" : pendingNames.joined(separator: ", ")),
            .init(name: "Sources on", value: enabledNames.isEmpty ? "—" : enabledNames.joined(separator: ", ")),
        ]

        let lcdInfo: [DebugSnapshot.NamedValue] = [
            .init(name: "Control", value: String(format: "%08X", lcd.control)),
            .init(name: "Mode", value: ["1 bpp", "2 bpp", "4 bpp", "8 bpp", "16 bpp 1555", "24 bpp", "16 bpp 565", "12 bpp 444"][lcd.bppMode]),
            .init(name: "Base", value: String(format: "%06X", lcd.upbase)),
            .init(name: "Scan", value: "\(lcd.pixelsPerLine) × \(lcd.linesPerPanel)"),
            .init(name: "Int status", value: String(format: "%02X / mask %02X", lcd.ris, lcd.imsc)),
            .init(name: "Panel", value: "\(panel.sleeping ? "asleep" : "awake"), \(panel.displayOn ? "on" : "off")\(panel.inverted ? ", inverted" : "")"),
            .init(name: "MADCTL", value: String(format: "%02X", panel.madctl)),
            .init(name: "Backlight", value: String(format: "%.0f%%", backlight.brightness * 100)),
            .init(name: "Frames", value: "\(lcd.framesRendered)"),
        ]

        let kp = keypad
        var keypadInfo: [DebugSnapshot.NamedValue] = [
            .init(name: "Mode", value: ["idle", "any key", "single scan", "continuous"][Int(kp.mode)]),
            .init(name: "Control", value: String(format: "%08X", kp.control)),
            .init(name: "Status", value: String(format: "%02X / enable %02X", kp.status, kp.enable)),
            .init(name: "ON key", value: kp.onKeyDown ? "down" : "up"),
        ]
        for g in 1...7 {
            keypadInfo.append(.init(name: "Group \(g)", value: String(format: "data %02X  switches %02X", kp.data[g], kp.matrix[g])))
        }

        var timerInfo: [DebugSnapshot.NamedValue] = [
            .init(name: "Control", value: String(format: "%08X", timers.control)),
            .init(name: "Status", value: String(format: "%08X / mask %08X", timers.status, timers.mask)),
        ]
        for (i, ch) in timers.channels.enumerated() {
            timerInfo.append(.init(name: "Timer \(i + 1)", value: String(format: "%08X ↻%08X m%08X/%08X", ch.counter, ch.reload, ch.match1, ch.match2)))
        }
        let t = rtc.time
        timerInfo.append(.init(name: "RTC", value: String(format: "day %d %02d:%02d:%02d", t.days, t.hours, t.minutes, t.seconds)))

        return DebugSnapshot(
            registers: r, adl: cpu.adl, madl: cpu.madl, ief1: cpu.ief1, ief2: cpu.ief2,
            interruptMode: cpu.im, halted: cpu.halted, cycles: scheduler.cycles, cpuHz: scheduler.cpuHz,
            emulatedSeconds: Double(scheduler.now) / Double(Scheduler.baseHz),
            currentInstruction: lines.first.map { "\($0.bytes)  \($0.text)" } ?? "",
            disassembly: lines, stack: stack, memoryBase: base, memory: memory,
            ioPort: ioPort, ioBytes: ioBytes,
            interrupts: interruptInfo, lcd: lcdInfo, keypad: keypadInfo, timers: timerInfo,
            lastUnsupported: cpu.lastUnsupported)
    }
}
