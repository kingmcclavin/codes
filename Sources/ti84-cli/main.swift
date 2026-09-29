import Foundation
import TI84EmulatorCore

// Headless developer tool for the emulator core.

setvbuf(stdout, nil, _IONBF, 0)

func usage() -> Never {
    print("""
    usage:
      ti84-cli info [--rom <file>]
          Validate a ROM and print its model and checksums.
      ti84-cli boot [--rom <file>] [--seconds <n>] [--keys <k1,k2,...>] [--ppm <out.ppm>] [--events]
          Boot the ROM headless, optionally type keys (Key names such as two,add,three,enter;
          "wait<seconds>" pauses),
          then print the LCD as text and a register dump.
      ti84-cli bench [--rom <file>] [--seconds <n>]
          Measure emulation speed relative to real time.
      ti84-cli zex <file.com>
          Run a CP/M Z80 instruction exerciser (ZEXDOC / ZEXALL) on the CPU core.

    Without --rom, the bundled ROM (or $TI84_ROM_PATH) is used.
    """)
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else { usage() }
let command = arguments.removeFirst()

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

func loadROM() -> ROMImage {
    do {
        if let path = option("--rom") {
            return try ROMLoader.load(.file(URL(fileURLWithPath: path)))
        }
        return try ROMLoader.load()
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

func describe(_ rom: ROMImage) {
    print("Model:   \(rom.model.rawValue)")
    print("Size:    \(rom.size) bytes (\(rom.profile.flashPages) Flash pages, boot page \(hex(UInt8(rom.profile.bootPage)))h)")
    print("CRC-32:  \(hex(rom.crc32))")
    print("SHA-256: \(rom.sha256)")
    for warning in rom.warnings { print("Warning: \(warning)") }
}

switch command {
case "info":
    describe(loadROM())

case "boot":
    let rom = loadROM()
    describe(rom)
    let seconds = Double(option("--seconds") ?? "") ?? 5
    let emulator = Emulator(rom: rom)
    if arguments.contains("--events") {
        emulator.onEvent = { print("event: \($0)") }
    }
    emulator.run(seconds: seconds)
    if let keys = option("--keys") {
        for name in keys.split(separator: ",") {
            if name.hasPrefix("wait") {
                // "wait<seconds>", e.g. wait1.5, pauses between keys.
                emulator.run(seconds: Double(name.dropFirst(4)) ?? 1)
                continue
            }
            guard let key = Key(rawValue: String(name)) else {
                print("error: unknown key '\(name)'. Keys: \(Key.allCases.map(\.rawValue).joined(separator: ", "))")
                exit(1)
            }
            emulator.setKey(key, pressed: true)
            emulator.run(seconds: 0.1)
            emulator.setKey(key, pressed: false)
            emulator.run(seconds: 0.2)
        }
        emulator.run(seconds: 0.5)
    }
    print("")
    print(emulator.frame.asciiArt)
    print(emulator.debugSnapshot().summary)
    if let path = option("--ppm") {
        let data = Data(LCDRenderer().ppm(emulator.frame))
        try data.write(to: URL(fileURLWithPath: path))
        print("LCD image written to \(path)")
    }

case "bench":
    let rom = loadROM()
    let seconds = Double(option("--seconds") ?? "") ?? 20
    let emulator = Emulator(rom: rom)
    let start = Date()
    emulator.run(seconds: seconds)
    let wall = Date().timeIntervalSince(start)
    print(String(format: "%.1f emulated seconds in %.2f s wall time: %.1f× real time (%llu cycles)",
                 seconds, wall, seconds / wall, emulator.cpu.cycles))

case "zex":
    guard let path = arguments.first else { usage() }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let harness = CPMHarness(program: [UInt8](data))
    let start = Date()
    harness.run { print($0, terminator: "") }
    let seconds = Date().timeIntervalSince(start)
    print("\n\(harness.cpu.cycles) T-states in \(String(format: "%.1f", seconds)) s "
        + "(\(String(format: "%.1f", Double(harness.cpu.cycles) / seconds / 1e6)) MHz effective)")
    exit(harness.output.contains("ERROR") ? 1 : 0)

default:
    usage()
}
