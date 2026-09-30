import Foundation

/// eZ80 disassembler used by the debugger and trace tools.
public struct Disassembler {
    public struct Instruction {
        public let address: UInt32
        public let length: Int
        public let bytes: [UInt8]
        public let text: String
    }

    /// Reads a byte at a 24-bit address without side effects.
    let read: (UInt32) -> UInt8

    public init(read: @escaping (UInt32) -> UInt8) { self.read = read }

    static let r8 = ["b", "c", "d", "e", "h", "l", "(hl)", "a"]
    static let rp = ["bc", "de", "hl", "sp"]
    static let rp2 = ["bc", "de", "hl", "af"]
    static let cc = ["nz", "z", "nc", "c", "po", "pe", "p", "m"]
    static let aluOps = ["add a,", "adc a,", "sub ", "sbc a,", "and ", "xor ", "or ", "cp "]
    static let rot = ["rlc", "rrc", "rl", "rr", "sla", "sra", "sll", "srl"]

    /// Disassembles one instruction. `adl` is the CPU mode; `mbase` supplies the
    /// upper address byte in Z80 mode.
    public func decode(at address: UInt32, adl: Bool, mbase: UInt8 = 0) -> Instruction {
        var pc = address
        var bytes: [UInt8] = []
        func next() -> UInt8 {
            let a = adl ? pc & 0xFF_FFFF : (UInt32(mbase) << 16) | (pc & 0xFFFF)
            let b = read(a)
            bytes.append(b)
            pc &+= 1
            return b
        }
        var L = adl, IL = adl
        var suffix = ""
        var idx = "hl"
        var op = next()
        loop: while true {
            switch op {
            case 0x40 where idx == "hl": L = false; IL = false; suffix = ".sis"
            case 0x49 where idx == "hl": L = true; IL = false; suffix = ".lis"
            case 0x52 where idx == "hl": L = false; IL = true; suffix = ".sil"
            case 0x5B where idx == "hl": L = true; IL = true; suffix = ".lil"
            case 0xDD: idx = "ix"
            case 0xFD: idx = "iy"
            default: break loop
            }
            op = next()
        }
        _ = L
        func imm() -> String {
            var v = UInt32(next()) | UInt32(next()) << 8
            if IL { v |= UInt32(next()) << 16; return String(format: "$%06X", v) }
            return String(format: "$%04X", v)
        }
        func n() -> String { String(format: "$%02X", next()) }
        func disp() -> Int { Int(Int8(bitPattern: next())) }
        func dstr(_ d: Int) -> String { d < 0 ? "-\(-d)" : "+\(d)" }
        func mem() -> String { idx == "hl" ? "(hl)" : "(\(idx)\(dstr(disp())))" }
        func reg(_ i: UInt8) -> String {
            if i == 4 && idx != "hl" { return idx + "h" }
            if i == 5 && idx != "hl" { return idx + "l" }
            return Disassembler.r8[Int(i)]
        }
        func rpName(_ p: UInt8) -> String { p == 2 ? idx : Disassembler.rp[Int(p)] }
        func rel() -> String {
            let d = disp()
            let t = UInt32(bitPattern: Int32(Int(pc) + d)) & (adl ? 0xFF_FFFF : 0xFFFF)
            return String(format: adl ? "$%06X" : "$%04X", t)
        }
        let other = idx == "ix" ? "iy" : "ix"

        let x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1
        var t: String
        switch x {
        case 0:
            switch z {
            case 0:
                switch y {
                case 0: t = "nop"
                case 1: t = "ex af,af'"
                case 2: t = "djnz \(rel())"
                case 3: t = "jr \(rel())"
                default: t = "jr \(Disassembler.cc[Int(y - 4)]),\(rel())"
                }
            case 1:
                if q == 0 {
                    if p == 3 && idx != "hl" { t = "ld \(other),(\(idx)\(dstr(disp())))" }
                    else { t = "ld \(rpName(p)),\(imm())" }
                } else { t = "add \(idx),\(rpName(p))" }
            case 2:
                switch (q, p) {
                case (0, 0): t = "ld (bc),a"
                case (0, 1): t = "ld (de),a"
                case (0, 2): t = "ld (\(imm())),\(idx)"
                case (0, _): t = "ld (\(imm())),a"
                case (_, 0): t = "ld a,(bc)"
                case (_, 1): t = "ld a,(de)"
                case (_, 2): t = "ld \(idx),(\(imm()))"
                default: t = "ld a,(\(imm()))"
                }
            case 3: t = (q == 0 ? "inc " : "dec ") + rpName(p)
            case 4: t = "inc " + (y == 6 ? mem() : reg(y))
            case 5: t = "dec " + (y == 6 ? mem() : reg(y))
            case 6:
                if y == 7 && idx != "hl" { t = "ld (\(idx)\(dstr(disp()))),\(other)" }
                else if y == 6 { let m = mem(); t = "ld \(m),\(n())" }
                else { t = "ld \(reg(y)),\(n())" }
            default:
                if idx != "hl" {
                    let names = ["bc", "de", "hl", idx]
                    let m = "(\(idx)\(dstr(disp())))"
                    t = q == 0 ? "ld \(names[Int(p)]),\(m)" : "ld \(m),\(names[Int(p)])"
                } else {
                    t = ["rlca", "rrca", "rla", "rra", "daa", "cpl", "scf", "ccf"][Int(y)]
                }
            }
        case 1:
            if op == 0x76 { t = "halt" }
            else if z == 6 { t = "ld \(Disassembler.r8[Int(y)]),\(mem())" }
            else if y == 6 { t = "ld \(mem()),\(Disassembler.r8[Int(z)])" }
            else { t = "ld \(reg(y)),\(reg(z))" }
        case 2:
            t = Disassembler.aluOps[Int(y)] + (z == 6 ? mem() : reg(z))
        default:
            switch z {
            case 0: t = "ret \(Disassembler.cc[Int(y)])"
            case 1:
                if q == 0 { t = "pop " + (p == 2 ? idx : Disassembler.rp2[Int(p)]) }
                else { t = ["ret", "exx", "jp (\(idx))", "ld sp,\(idx)"][Int(p)] }
            case 2: t = "jp \(Disassembler.cc[Int(y)]),\(imm())"
            case 3:
                switch y {
                case 0: t = "jp \(imm())"
                case 1:
                    if idx != "hl" {
                        let d = disp(); let o = next()
                        t = cbText(o, operand: "(\(idx)\(dstr(d)))")
                    } else {
                        let o = next()
                        t = cbText(o, operand: Disassembler.r8[Int(o & 7)])
                    }
                case 2: t = "out (\(n())),a"
                case 3: t = "in a,(\(n()))"
                case 4: t = "ex (sp),\(idx)"
                case 5: t = "ex de,hl"
                case 6: t = "di"
                default: t = "ei"
                }
            case 4: t = "call \(Disassembler.cc[Int(y)]),\(imm())"
            case 5:
                if q == 0 { t = "push " + (p == 2 ? idx : Disassembler.rp2[Int(p)]) }
                else if p == 0 { t = "call \(imm())" }
                else if p == 2 { t = edText(next(), imm: imm, n: n, disp: disp, dstr: dstr) }
                else { t = "??" }
            case 6: t = Disassembler.aluOps[Int(y)] + n()
            default: t = String(format: "rst $%02X", y * 8)
            }
        }
        if !suffix.isEmpty, let space = t.firstIndex(of: " ") {
            t.insert(contentsOf: suffix, at: space)
        } else if !suffix.isEmpty {
            t += suffix
        }
        return Instruction(address: address, length: bytes.count, bytes: bytes, text: t)
    }

    private func cbText(_ o: UInt8, operand: String) -> String {
        let x = o >> 6, y = Int((o >> 3) & 7)
        switch x {
        case 0: return "\(Disassembler.rot[y]) \(operand)"
        case 1: return "bit \(y),\(operand)"
        case 2: return "res \(y),\(operand)"
        default: return "set \(y),\(operand)"
        }
    }

    private func edText(_ o: UInt8, imm: () -> String, n: () -> String, disp: () -> Int, dstr: (Int) -> String) -> String {
        let x = o >> 6, y = (o >> 3) & 7, z = o & 7, p = Int(y >> 1), q = y & 1
        let r8 = Disassembler.r8
        switch x {
        case 0:
            switch z {
            case 0: return y == 6 ? "??" : "in0 \(r8[Int(y)]),(\(n()))"
            case 1: return y == 6 ? "ld iy,(hl)" : "out0 (\(n())),\(r8[Int(y)])"
            case 2, 3:
                if q == 1 { return "??" }
                let base = z == 2 ? "ix" : "iy"
                let dst = ["bc", "de", "hl", base][p]
                return "lea \(dst),\(base)\(dstr(disp()))"
            case 4: return "tst a,\(r8[Int(y)])"
            case 6: return y == 7 ? "ld (hl),iy" : "??"
            case 7:
                let names = ["bc", "de", "hl", "ix"]
                return q == 0 ? "ld \(names[p]),(hl)" : "ld (hl),\(names[p])"
            default: return "??"
            }
        case 1:
            switch z {
            case 0: return y == 6 ? "in (c)" : "in \(r8[Int(y)]),(bc)"
            case 1: return y == 6 ? "??" : "out (bc),\(r8[Int(y)])"
            case 2: return (q == 0 ? "sbc hl," : "adc hl,") + Disassembler.rp[p]
            case 3: return q == 0 ? "ld (\(imm())),\(Disassembler.rp[p])" : "ld \(Disassembler.rp[p]),(\(imm()))"
            case 4:
                switch y {
                case 0: return "neg"
                case 2: return "lea ix,iy\(dstr(disp()))"
                case 4: return "tst a,\(n())"
                case 6: return "tstio \(n())"
                default: return "mlt \(Disassembler.rp[p])"
                }
            case 5:
                switch y {
                case 0: return "retn"
                case 1: return "reti"
                case 2: return "lea iy,ix\(dstr(disp()))"
                case 4: return "pea ix\(dstr(disp()))"
                case 5: return "ld mb,a"
                case 7: return "stmix"
                default: return "??"
                }
            case 6:
                switch y {
                case 0: return "im 0"
                case 2: return "im 1"
                case 3: return "im 2"
                case 4: return "pea iy\(dstr(disp()))"
                case 5: return "ld a,mb"
                case 6: return "slp"
                case 7: return "rsmix"
                default: return "??"
                }
            default:
                return ["ld i,a", "ld r,a", "ld a,i", "ld a,r", "rrd", "rld", "??", "??"][Int(y)]
            }
        case 2:
            let names: [UInt8: String] = [
                0xA0: "ldi", 0xA1: "cpi", 0xA2: "ini", 0xA3: "outi", 0xA8: "ldd", 0xA9: "cpd", 0xAA: "ind", 0xAB: "outd",
                0xB0: "ldir", 0xB1: "cpir", 0xB2: "inir", 0xB3: "otir", 0xB8: "lddr", 0xB9: "cpdr", 0xBA: "indr", 0xBB: "otdr",
                0x82: "inim", 0x83: "otim", 0x84: "ini2", 0x8A: "indm", 0x8B: "otdm", 0x8C: "ind2",
                0x92: "inimr", 0x93: "otimr", 0x94: "ini2r", 0x9A: "indmr", 0x9B: "otdmr", 0x9C: "ind2r",
                0xA4: "outi2", 0xAC: "outd2", 0xB4: "oti2r", 0xBC: "otd2r",
            ]
            return names[o] ?? "??"
        default:
            let names: [UInt8: String] = [0xC2: "inirx", 0xC3: "otirx", 0xCA: "indrx", 0xCB: "otdrx", 0xC7: "ld i,hl", 0xD7: "ld hl,i"]
            return names[o] ?? "??"
        }
    }
}
