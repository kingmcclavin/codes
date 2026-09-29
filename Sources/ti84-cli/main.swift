import Foundation
import TI84EmulatorCore

setvbuf(stdout, nil, _IONBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    usage:
      ti84-cli zex <file.com>              run a CP/M Z80 exerciser (ZEXDOC/ZEXALL)
    """)
    exit(2)
}

guard let command = arguments.first else { usage() }

switch command {
case "zex":
    guard arguments.count >= 2 else { usage() }
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
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
