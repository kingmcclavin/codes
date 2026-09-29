/// Runs CP/M `.COM` CPU exerciser programs (such as ZEXDOC/ZEXALL) on a bare
/// Z80 with 64 KB of RAM, emulating just the two BDOS console calls they use.
/// Used to validate the CPU core against real-silicon reference results.
public final class CPMHarness {
    public let cpu: CPU
    public let memory: MemoryBus
    public private(set) var output = ""

    public init(program: [UInt8]) {
        let (bus, _) = MemoryBus.flatRAM()
        memory = bus
        cpu = CPU(memory: bus, io: IOBus())
        memory.load(program, at: 0x0100)
        // 0x0000: HALT-style exit trap; 0x0005: BDOS entry (RET, intercepted).
        memory.write(0x0000, value: 0x76)
        memory.write(0x0005, value: 0xC9)
        // BDOS top-of-memory pointer used by some programs for the stack.
        memory.write(0x0006, value: 0x00)
        memory.write(0x0007, value: 0xF0)
        cpu.registers.pc = 0x0100
        cpu.registers.sp = 0xF000
    }

    /// Runs until the program warm-boots (jumps to 0) or `maxCycles` elapse.
    /// `onOutput` receives console text as it is produced.
    @discardableResult
    public func run(maxCycles: UInt64 = .max, onOutput: ((String) -> Void)? = nil) -> Bool {
        while cpu.cycles < maxCycles {
            let pc = cpu.registers.pc
            if pc == 0x0000 { return true }
            if pc == 0x0005 {
                let text = bdosCall()
                if !text.isEmpty {
                    output += text
                    onOutput?(text)
                }
            }
            cpu.step()
        }
        return false
    }

    private func bdosCall() -> String {
        switch cpu.registers.c {
        case 2:
            return String(UnicodeScalar(cpu.registers.e))
        case 9:
            var address = cpu.registers.de
            var text = ""
            while true {
                let byte = memory.read(address)
                if byte == UInt8(ascii: "$") { break }
                text.append(Character(UnicodeScalar(byte)))
                address &+= 1
            }
            return text
        default:
            return ""
        }
    }
}
