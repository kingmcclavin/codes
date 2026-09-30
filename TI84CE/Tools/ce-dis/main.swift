import EmulatorCore
import Foundation
// ce-dis <rom> <hexaddr> [count] [z80]
let a = CommandLine.arguments
let rom = try! ROMImage(contentsOf: URL(fileURLWithPath: a[1]))
var pc = UInt32(a[2], radix: 16)!
let count = a.count > 3 ? Int(a[3])! : 30
let adl = !(a.count > 4 && a[4] == "z80")
let d = Disassembler(read: { rom.data[Int($0 & 0x3FFFFF)] })
for _ in 0..<count {
    let i = d.decode(at: pc, adl: adl)
    print(String(format: "%06X  %-16@ %@", pc, i.bytes.map { String(format: "%02X", $0) }.joined(separator: " "), i.text))
    pc += UInt32(i.length)
}
