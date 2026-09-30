import EmulatorCore
import Foundation

// Headless TI-84 Plus CE runner for debugging and CI.
//
//   ce-headless --rom ti84ce.rom [--seconds 10] [--screenshot out.ppm]
//               [--trace 64] [--hotspots] [--io] [--break D1A881]
//               [--keys "4.0:enter,5.0:k2"] [--state in.plist] [--save-state out.plist]

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func flag(_ name: String) -> Bool { args.contains(name) }

guard let romPath = option("--rom") else {
    print("usage: ce-headless --rom <file> [--seconds N] [--screenshot out.ppm] [--trace N] [--hotspots] [--io] [--keys t:key,...]")
    exit(2)
}

let rom: ROMImage
do { rom = try ROMImage(contentsOf: URL(fileURLWithPath: romPath)) } catch { print("\(error)"); exit(1) }
print(rom.summary)

let emu = Emulator(rom: rom)
if let statePath = option("--state") {
    let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
    try emu.loadState(Emulator.decode(data))
    print("Loaded state from \(statePath)")
}

let seconds = Double(option("--seconds") ?? "5") ?? 5
let traceDepth = Int(option("--trace") ?? "0") ?? 0
let dis = Disassembler(read: { emu.bus.peek($0) })

var ring = [(UInt32, Bool)](repeating: (0, false), count: max(traceDepth, 1))
var ringPos = 0
var hotspots = [UInt32: Int]()
// --trace-skip A-B[,C-D]: exclude PC ranges (e.g. delay loops) from the trace ring.
let skipRanges: [ClosedRange<UInt32>] = (option("--trace-skip") ?? "").split(separator: ",").compactMap {
    let p = $0.split(separator: "-")
    guard p.count == 2, let a = UInt32(p[0], radix: 16), let b = UInt32(p[1], radix: 16) else { return nil }
    return a...b
}
// --stop-pc A-B: stop the run as soon as PC enters the range (e.g. runaway execution).
var stopRange: ClosedRange<UInt32>?
if let r = option("--stop-pc") {
    let p = r.split(separator: "-")
    stopRange = UInt32(p[0], radix: 16)!...UInt32(p[1], radix: 16)!
}
var stopped = false
// --stop-nops: stop after 8 consecutive NOPs (a runaway into erased/zeroed memory).
let stopOnNops = flag("--stop-nops")
var nopRun = 0
if traceDepth > 0 || flag("--hotspots") || stopRange != nil || stopOnNops {
    let wantHot = flag("--hotspots")
    emu.cpu.traceHook = { cpu in
        let pc = cpu.registers.pc
        if stopOnNops {
            if emu.bus.peek(pc) == 0 { nopRun += 1 } else { nopRun = 0 }
            if nopRun == 8 && !stopped { stopped = true; cpu.triggerBreak(); return }
        }
        if let sr = stopRange, sr.contains(pc), !stopped {
            stopped = true
            cpu.triggerBreak()
            return
        }
        if traceDepth > 0 && !skipRanges.contains(where: { $0.contains(pc) }) { ring[ringPos % ring.count] = (pc, cpu.adl); ringPos += 1 }
        if wantHot { hotspots[pc, default: 0] += 1 }
    }
}

var ioLog = [String: Int]()
// --io-pc A0: print the instruction address of accesses to ports whose top byte matches.
if let hi = option("--io-pc"), let top = UInt16(hi, radix: 16) {
    var seen = Set<String>()
    emu.io.trace = { port, value, write in
        guard port >> 8 == top else { return }
        let key = String(format: "%06X %@ %04X", emu.cpu.instructionPC, write ? "W" : "R", port)
        if seen.insert(key).inserted { print(key + String(format: " = %02X", value)) }
    }
}
if flag("--io") {
    emu.io.trace = { port, value, write in
        let key = String(format: "%@ %04X", write ? "W" : "R", port)
        ioLog[key, default: 0] += 1
    }
}

if flag("--flash-writes") {
    var n = 0
    emu.bus.flashWriteTrace = { a, v in
        if flag("--stop-flash-write") && emu.cpu.instructionPC < 0xD00000 && !stopped { stopped = true; emu.cpu.triggerBreak() }
        n += 1
        if n <= 60 { print(String(format: "flash write %06X <- %02X  (PC %06X, mode after: ", a, v, emu.cpu.instructionPC)) }
    }
}

if flag("--panel") {
    var line = ""
    emu.panel.trace = { isCmd, b in
        if isCmd { if !line.isEmpty { print(line) }; line = String(format: "panel cmd %02X:", b) }
        else { line += String(format: " %02X", b) }
    }
}

if let b = option("--break"), let addr = UInt32(b, radix: 16) {
    emu.cpu.breakpoints = [addr]
}

emu.cpu.onUnsupported = { msg in
    print("!! \(msg.replacingOccurrences(of: "\n", with: " "))")
}

// Scripted key presses: "time:key" (pressed for 150 ms).
struct KeyEvent { let time: Double; let key: CalculatorKey; let down: Bool }
var keyEvents: [KeyEvent] = []
if let spec = option("--keys") {
    for item in spec.split(separator: ",") {
        let parts = item.split(separator: ":")
        guard parts.count == 2, let t = Double(parts[0]), let k = CalculatorKey(rawValue: String(parts[1])) else {
            print("bad key spec \(item)"); exit(2)
        }
        keyEvents.append(KeyEvent(time: t, key: k, down: true))
        keyEvents.append(KeyEvent(time: t + (Double(option("--hold") ?? "0.15") ?? 0.15), key: k, down: false))
    }
    keyEvents.sort { $0.time < $1.time }
}

let start = Date()
var emulated = 0.0
let slice = 0.01
while emulated < seconds {
    while let e = keyEvents.first, e.time <= emulated {
        emu.setKey(e.key, pressed: e.down)
        keyEvents.removeFirst()
    }
    emu.run(seconds: slice)
    emulated += slice
    if emu.cpu.breakpointHit {
        print(String(format: "Breakpoint hit at %06X after %.3f s", emu.cpu.registers.pc, emulated))
        break
    }
}
let wall = Date().timeIntervalSince(start)
print(String(format: "Emulated %.2f s in %.2f s wall (%.0f%% speed), %d frames rendered", emulated, wall, emulated / wall * 100, emu.lcd.framesRendered))
print(emu.debugDescription)
print(String(format: "LCD control=%08X upbase=%06X timing=%@ panel on=%d sleep=%d unsupported=%d",
             emu.lcd.control, emu.lcd.upbase, emu.lcd.timing.map { String(format: "%08X", $0) }.joined(separator: ","),
             emu.panel.displayOn ? 1 : 0, emu.panel.sleeping ? 1 : 0, emu.cpu.unsupportedCount))
print(String(format: "Keypad control=%08X status=%02X enable=%02X rows=%d cols=%d int.enabled=%08X int.latched=%08X int.status=%08X", emu.keypad.control, emu.keypad.status, emu.keypad.enable, emu.keypad.rows, emu.keypad.columns, emu.interrupts.banks[0].enabled, emu.interrupts.banks[0].latched, emu.interrupts.banks[0].status))
print(String(format: "GPT control=%08X status=%08X mask=%08X ", emu.timers.control, emu.timers.status, emu.timers.mask) + emu.timers.channels.map { String(format: "[cnt=%08X rel=%08X m1=%08X m2=%08X]", $0.counter, $0.reload, $0.match1, $0.match2) }.joined(separator: " "))
print(String(format: "Panel MADCTL=%02X COLMOD=%02X inverted=%d", emu.panel.madctl, emu.panel.colmod, emu.panel.inverted ? 1 : 0))

if traceDepth > 0 {
    print("--- last \(min(ringPos, ring.count)) instructions ---")
    let n = min(ringPos, ring.count)
    for i in 0..<n {
        let (pc, adl) = ring[(ringPos - n + i) % ring.count]
        let ins = dis.decode(at: pc, adl: adl, mbase: emu.cpu.registers.mbase)
        print(String(format: "%06X  %-14@ %@", pc, ins.bytes.map { String(format: "%02X", $0) }.joined(separator: " "), ins.text))
    }
}

if flag("--hotspots") {
    print("--- hotspots ---")
    for (pc, count) in hotspots.sorted(by: { $0.value > $1.value }).prefix(25) {
        let ins = dis.decode(at: pc, adl: true)
        print(String(format: "%06X %10d  %@", pc, count, ins.text))
    }
}

if flag("--io") {
    print("--- I/O ports ---")
    for (k, v) in ioLog.sorted(by: { $0.key < $1.key }) { print("\(k) x\(v)") }
}

// --dis ADDR:N disassembles emulated memory after the run.
if let spec = option("--dis") {
    let p = spec.split(separator: ":")
    var a = UInt32(p[0], radix: 16) ?? 0
    for _ in 0..<(p.count > 1 ? Int(p[1]) ?? 20 : 20) {
        let ins = dis.decode(at: a, adl: true)
        print(String(format: "%06X  %-16@ %@", a, ins.bytes.map { String(format: "%02X", $0) }.joined(separator: " "), ins.text))
        a += UInt32(ins.length)
    }
}

// --find HEXBYTES searches RAM for a byte pattern after the run.
if let pat = option("--find") {
    var bytes = [UInt8]()
    var i = pat.startIndex
    while i < pat.endIndex { let j = pat.index(i, offsetBy: 2); bytes.append(UInt8(pat[i..<j], radix: 16)!); i = j }
    let ram = emu.ram.contents
    for o in 0...(ram.count - bytes.count) where Array(ram[o..<o + bytes.count]) == bytes {
        print(String(format: "found at %06X", 0xD00000 + o))
    }
}

// --dump ADDR:N hex-dumps emulated memory after the run.
if let spec = option("--dump") {
    let p = spec.split(separator: ":")
    let a = UInt32(p[0], radix: 16) ?? 0
    let n = p.count > 1 ? Int(p[1]) ?? 64 : 64
    for row in stride(from: 0, to: n, by: 16) {
        let bytes = (0..<min(16, n - row)).map { String(format: "%02X", emu.bus.peek(a + UInt32(row + $0))) }
        print(String(format: "%06X  ", a + UInt32(row)) + bytes.joined(separator: " "))
    }
}

if let shot = option("--screenshot") {
    let f = emu.lcd.frame
    var out = Data("P6\n\(f.width) \(f.height)\n255\n".utf8)
    for i in 0..<(f.width * f.height) {
        out.append(contentsOf: [f.pixels[i * 4], f.pixels[i * 4 + 1], f.pixels[i * 4 + 2]])
    }
    try out.write(to: URL(fileURLWithPath: shot))
    print("Screenshot written to \(shot)")
}

if let savePath = option("--save-state") {
    try Emulator.encode(emu.saveState()).write(to: URL(fileURLWithPath: savePath))
    print("State saved to \(savePath)")
}
