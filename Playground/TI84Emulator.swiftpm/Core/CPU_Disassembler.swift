/// A decoded instruction for display in the debugger.
public struct DisassembledInstruction: Equatable, Sendable {
    public var address: UInt16
    public var bytes: [UInt8]
    public var text: String

    public var length: Int { bytes.count }
    public var hexBytes: String { bytes.map { hex($0) }.joined(separator: " ") }
}

/// Z80 disassembler covering the full instruction set (including
/// undocumented forms), using the same x/y/z decoding as the CPU.
public enum Disassembler {
    private static let r = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
    private static let rp = ["BC", "DE", "HL", "SP"]
    private static let rp2 = ["BC", "DE", "HL", "AF"]
    private static let cc = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
    private static let alu = ["ADD A,", "ADC A,", "SUB ", "SBC A,", "AND ", "XOR ", "OR ", "CP "]
    private static let rot = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SLL", "SRL"]
    private static let accumulatorOps = ["RLCA", "RRCA", "RLA", "RRA", "DAA", "CPL", "SCF", "CCF"]
    private static let blockOps = [
        ["LDI", "CPI", "INI", "OUTI"], ["LDD", "CPD", "IND", "OUTD"],
        ["LDIR", "CPIR", "INIR", "OTIR"], ["LDDR", "CPDR", "INDR", "OTDR"],
    ]

    /// Disassembles one instruction starting at `address`, reading memory
    /// through `read` (which should be side-effect free).
    public static func disassemble(at address: UInt16, read: (UInt16) -> UInt8) -> DisassembledInstruction {
        var pc = address
        var bytes: [UInt8] = []
        func next() -> UInt8 {
            let b = read(pc)
            bytes.append(b)
            pc &+= 1
            return b
        }
        func imm8() -> String { "$" + hex(next()) }
        func imm16() -> String {
            let lo = UInt16(next()), hi = UInt16(next())
            return "$" + hex(hi << 8 | lo)
        }

        var op = next()
        var index: String? = nil
        while op == 0xDD || op == 0xFD {
            index = op == 0xDD ? "IX" : "IY"
            op = next()
        }

        var displacement: String?
        func memoryOperand() -> String {
            guard let index else { return "(HL)" }
            if displacement == nil {
                let d = Int8(bitPattern: next())
                displacement = d < 0 ? "-$\(hex(UInt8(-Int(d))))" : "+$\(hex(UInt8(d)))"
            }
            return "(\(index)\(displacement!))"
        }
        func reg(_ i: UInt8, allowIndexHalves: Bool = true) -> String {
            if i == 6 { return memoryOperand() }
            if let index, allowIndexHalves, i == 4 || i == 5 { return index + (i == 4 ? "H" : "L") }
            return r[Int(i)]
        }
        func pair(_ p: UInt8, _ table: [String]) -> String {
            p == 2 && index != nil ? index! : table[Int(p)]
        }
        func relative() -> String {
            let d = Int8(bitPattern: next())
            return "$" + hex(pc &+ UInt16(bitPattern: Int16(d)))
        }

        let text: String
        if op == 0xCB {
            if index != nil {
                let mem = memoryOperand()
                let sub = next()
                let x = sub >> 6, y = (sub >> 3) & 7, z = sub & 7
                let copy = z == 6 ? "" : "," + r[Int(z)]
                switch x {
                case 0: text = "\(rot[Int(y)]) \(mem)\(copy)"
                case 1: text = "BIT \(y),\(mem)"
                case 2: text = "RES \(y),\(mem)\(copy)"
                default: text = "SET \(y),\(mem)\(copy)"
                }
            } else {
                let sub = next()
                let x = sub >> 6, y = (sub >> 3) & 7, z = sub & 7
                switch x {
                case 0: text = "\(rot[Int(y)]) \(r[Int(z)])"
                case 1: text = "BIT \(y),\(r[Int(z)])"
                case 2: text = "RES \(y),\(r[Int(z)])"
                default: text = "SET \(y),\(r[Int(z)])"
                }
            }
        } else if op == 0xED {
            let sub = next()
            let x = sub >> 6, y = (sub >> 3) & 7, z = sub & 7, p = y >> 1, q = y & 1
            if x == 1 {
                switch z {
                case 0: text = y == 6 ? "IN (C)" : "IN \(r[Int(y)]),(C)"
                case 1: text = y == 6 ? "OUT (C),0" : "OUT (C),\(r[Int(y)])"
                case 2: text = (q == 0 ? "SBC HL," : "ADC HL,") + rp[Int(p)]
                case 3: text = q == 0 ? "LD (\(imm16())),\(rp[Int(p)])" : "LD \(rp[Int(p)]),(\(imm16()))"
                case 4: text = "NEG"
                case 5: text = y == 1 ? "RETI" : "RETN"
                case 6: text = "IM \(["0", "0/1", "1", "2"][Int(y & 3)])"
                default: text = ["LD I,A", "LD R,A", "LD A,I", "LD A,R", "RRD", "RLD", "NOP*", "NOP*"][Int(y)]
                }
            } else if x == 2 && y >= 4 && z <= 3 {
                text = blockOps[Int(y - 4)][Int(z)]
            } else {
                text = "NOP* (ED \(hex(sub)))"
            }
        } else {
            let x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1
            switch x {
            case 0:
                switch z {
                case 0:
                    switch y {
                    case 0: text = "NOP"
                    case 1: text = "EX AF,AF'"
                    case 2: text = "DJNZ \(relative())"
                    case 3: text = "JR \(relative())"
                    default: text = "JR \(cc[Int(y - 4)]),\(relative())"
                    }
                case 1:
                    text = q == 0 ? "LD \(pair(p, rp)),\(imm16())" : "ADD \(pair(2, rp)),\(pair(p, rp))"
                case 2:
                    switch y {
                    case 0: text = "LD (BC),A"
                    case 1: text = "LD A,(BC)"
                    case 2: text = "LD (DE),A"
                    case 3: text = "LD A,(DE)"
                    case 4: text = "LD (\(imm16())),\(pair(2, rp))"
                    case 5: text = "LD \(pair(2, rp)),(\(imm16()))"
                    case 6: text = "LD (\(imm16())),A"
                    default: text = "LD A,(\(imm16()))"
                    }
                case 3: text = (q == 0 ? "INC " : "DEC ") + pair(p, rp)
                case 4: text = "INC \(reg(y))"
                case 5: text = "DEC \(reg(y))"
                case 6:
                    let target = reg(y)
                    text = "LD \(target),\(imm8())"
                default: text = accumulatorOps[Int(y)]
                }
            case 1:
                if op == 0x76 {
                    text = "HALT"
                } else if z == 6 || y == 6 {
                    let dst = reg(y, allowIndexHalves: false), src = reg(z, allowIndexHalves: false)
                    text = "LD \(dst),\(src)"
                } else {
                    text = "LD \(reg(y)),\(reg(z))"
                }
            case 2:
                text = alu[Int(y)] + reg(z)
            default:
                switch z {
                case 0: text = "RET \(cc[Int(y)])"
                case 1:
                    if q == 0 {
                        text = "POP \(pair(p, rp2))"
                    } else {
                        text = ["RET", "EXX", "JP (\(pair(2, rp)))", "LD SP,\(pair(2, rp))"][Int(p)]
                    }
                case 2: text = "JP \(cc[Int(y)]),\(imm16())"
                case 3:
                    switch y {
                    case 0: text = "JP \(imm16())"
                    case 2: text = "OUT (\(imm8())),A"
                    case 3: text = "IN A,(\(imm8()))"
                    case 4: text = "EX (SP),\(pair(2, rp))"
                    case 5: text = "EX DE,HL"
                    case 6: text = "DI"
                    case 7: text = "EI"
                    default: text = "CB"
                    }
                case 4: text = "CALL \(cc[Int(y)]),\(imm16())"
                case 5: text = q == 0 ? "PUSH \(pair(p, rp2))" : "CALL \(imm16())"
                case 6: text = alu[Int(y)] + imm8()
                default: text = "RST $\(hex(UInt8(y * 8)))"
                }
            }
        }
        return DisassembledInstruction(address: address, bytes: bytes, text: text)
    }

    /// Disassembles `count` consecutive instructions.
    public static func disassemble(from address: UInt16, count: Int, read: (UInt16) -> UInt8) -> [DisassembledInstruction] {
        var result: [DisassembledInstruction] = []
        var pc = address
        for _ in 0..<count {
            let instruction = disassemble(at: pc, read: read)
            result.append(instruction)
            pc &+= UInt16(instruction.length)
        }
        return result
    }
}
