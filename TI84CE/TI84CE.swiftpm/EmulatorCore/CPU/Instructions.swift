import Foundation

/// Sign / zero / parity lookup for 8-bit results (includes undocumented bits 3 and 5).
let szpTable: [UInt8] = (0..<256).map { v -> UInt8 in
    var f: UInt8 = UInt8(v) & (Flag.s | Flag.x | Flag.y)
    if v == 0 { f |= Flag.z }
    if v.nonzeroBitCount % 2 == 0 { f |= Flag.pv }
    return f
}

extension CPU {
    // MARK: - Register operand helpers

    /// The register selected by the current prefix: HL, IX or IY (width L).
    @inline(__always) var index: UInt32 {
        let v = prefix == 0 ? r.hl : (prefix == 2 ? r.ix : r.iy)
        return mask(v, L)
    }

    @inline(__always) func setIndex(_ v: UInt32) {
        switch prefix {
        case 0: put(&r.hl, v)
        case 2: put(&r.ix, v)
        default: put(&r.iy, v)
        }
    }

    /// The index register that is *not* selected (IY for DD, IX for FD).
    var otherIndex: UInt32 {
        get { mask(prefix == 3 ? r.ix : r.iy, L) }
        set { if prefix == 3 { put(&r.ix, newValue) } else { put(&r.iy, newValue) } }
    }

    /// Effective address of the (HL) / (IX+d) / (IY+d) operand (fetches d if needed).
    @inline(__always) func indexAddress() -> UInt32 {
        if prefix == 0 { return mask(r.hl, L) }
        return mask(index &+ fetchDisplacement(), L)
    }

    /// 8-bit register operand r[i], with H/L replaced by IXH/IXL/IYH/IYL under a prefix.
    @inline(__always) func reg(_ i: UInt8) -> UInt8 {
        switch i {
        case 0: return r.b
        case 1: return r.c
        case 2: return r.d
        case 3: return r.e
        case 4: return prefix == 0 ? r.h : (prefix == 2 ? r.ixh : r.iyh)
        case 5: return prefix == 0 ? r.l : (prefix == 2 ? r.ixl : r.iyl)
        default: return r.a
        }
    }

    @inline(__always) func setReg(_ i: UInt8, _ v: UInt8) {
        switch i {
        case 0: r.b = v
        case 1: r.c = v
        case 2: r.d = v
        case 3: r.e = v
        case 4: if prefix == 0 { r.h = v } else if prefix == 2 { r.ixh = v } else { r.iyh = v }
        case 5: if prefix == 0 { r.l = v } else if prefix == 2 { r.ixl = v } else { r.iyl = v }
        default: r.a = v
        }
    }

    /// r[i] ignoring index prefixes (used alongside an (IX+d) operand).
    @inline(__always) func regPlain(_ i: UInt8) -> UInt8 {
        switch i {
        case 0: return r.b
        case 1: return r.c
        case 2: return r.d
        case 3: return r.e
        case 4: return r.h
        case 5: return r.l
        default: return r.a
        }
    }

    @inline(__always) func setRegPlain(_ i: UInt8, _ v: UInt8) {
        switch i {
        case 0: r.b = v
        case 1: r.c = v
        case 2: r.d = v
        case 3: r.e = v
        case 4: r.h = v
        case 5: r.l = v
        default: r.a = v
        }
    }

    /// Register pair table rp[p]: BC, DE, HL/IX/IY, SP.
    @inline(__always) func rp(_ p: UInt8) -> UInt32 {
        switch p {
        case 0: return mask(r.bc, L)
        case 1: return mask(r.de, L)
        case 2: return index
        default: return sp
        }
    }

    @inline(__always) func setRP(_ p: UInt8, _ v: UInt32) {
        switch p {
        case 0: put(&r.bc, v)
        case 1: put(&r.de, v)
        case 2: setIndex(v)
        default: sp = v
        }
    }

    /// Register pair table rp3[p] used by eZ80 LD rr,(HL)-style opcodes: BC, DE, HL, IX/IY.
    func rp3(_ p: UInt8) -> UInt32 {
        switch p {
        case 0: return mask(r.bc, L)
        case 1: return mask(r.de, L)
        case 2: return mask(r.hl, L)
        default: return index
        }
    }

    func setRP3(_ p: UInt8, _ v: UInt32) {
        switch p {
        case 0: put(&r.bc, v)
        case 1: put(&r.de, v)
        case 2: put(&r.hl, v)
        default: setIndex(v)
        }
    }

    @inline(__always) func condition(_ y: UInt8) -> Bool {
        let f = r.f
        switch y {
        case 0: return f & Flag.z == 0
        case 1: return f & Flag.z != 0
        case 2: return f & Flag.c == 0
        case 3: return f & Flag.c != 0
        case 4: return f & Flag.pv == 0
        case 5: return f & Flag.pv != 0
        case 6: return f & Flag.s == 0
        default: return f & Flag.s != 0
        }
    }

    // MARK: - ALU

    @inline(__always) func alu(_ op: UInt8, _ v: UInt8) {
        switch op {
        case 0: add8(v, carry: 0)
        case 1: add8(v, carry: r.f & Flag.c)
        case 2: r.a = sub8(v, carry: 0)
        case 3: r.a = sub8(v, carry: r.f & Flag.c)
        case 4: r.a &= v; r.f = szpTable[Int(r.a)] | Flag.h
        case 5: r.a ^= v; r.f = szpTable[Int(r.a)]
        case 6: r.a |= v; r.f = szpTable[Int(r.a)]
        default:
            _ = sub8(v, carry: 0)
            // CP takes the undocumented bits from the operand.
            r.f = (r.f & ~(Flag.x | Flag.y)) | (v & (Flag.x | Flag.y))
        }
    }

    @inline(__always) func add8(_ v: UInt8, carry: UInt8) {
        let a = r.a
        let res = UInt16(a) + UInt16(v) + UInt16(carry)
        let r8 = UInt8(truncatingIfNeeded: res)
        var f = r8 & (Flag.s | Flag.x | Flag.y)
        if r8 == 0 { f |= Flag.z }
        if (a ^ v ^ r8) & 0x10 != 0 { f |= Flag.h }
        if (a ^ r8) & (v ^ r8) & 0x80 != 0 { f |= Flag.pv }
        if res > 0xFF { f |= Flag.c }
        r.a = r8
        r.f = f
    }

    @inline(__always) func sub8(_ v: UInt8, carry: UInt8) -> UInt8 {
        let a = r.a
        let res = Int(a) - Int(v) - Int(carry)
        let r8 = UInt8(truncatingIfNeeded: res)
        var f = (r8 & (Flag.s | Flag.x | Flag.y)) | Flag.n
        if r8 == 0 { f |= Flag.z }
        if (a ^ v ^ r8) & 0x10 != 0 { f |= Flag.h }
        if (a ^ v) & (a ^ r8) & 0x80 != 0 { f |= Flag.pv }
        if res < 0 { f |= Flag.c }
        r.f = f
        return r8
    }

    @inline(__always) func inc8(_ v: UInt8) -> UInt8 {
        let res = v &+ 1
        var f = (r.f & Flag.c) | (res & (Flag.s | Flag.x | Flag.y))
        if res == 0 { f |= Flag.z }
        if res & 0x0F == 0 { f |= Flag.h }
        if v == 0x7F { f |= Flag.pv }
        r.f = f
        return res
    }

    @inline(__always) func dec8(_ v: UInt8) -> UInt8 {
        let res = v &- 1
        var f = (r.f & Flag.c) | Flag.n | (res & (Flag.s | Flag.x | Flag.y))
        if res == 0 { f |= Flag.z }
        if v & 0x0F == 0 { f |= Flag.h }
        if v == 0x80 { f |= Flag.pv }
        r.f = f
        return res
    }

    /// ADD HL/IX/IY, rr (16- or 24-bit). S, Z and P/V are preserved.
    func addWide(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let res = a &+ b
        let top: UInt32 = L ? 0xFF_FFFF : 0xFFFF
        var f = r.f & (Flag.s | Flag.z | Flag.pv)
        if (a & 0xFFF) + (b & 0xFFF) > 0xFFF { f |= Flag.h }
        if res > top { f |= Flag.c }
        f |= UInt8(truncatingIfNeeded: res >> 8) & (Flag.x | Flag.y)
        r.f = f
        return res & top
    }

    func adcWide(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let c: UInt32 = r.f & Flag.c != 0 ? 1 : 0
        let top: UInt32 = L ? 0xFF_FFFF : 0xFFFF
        let sign: UInt32 = L ? 0x80_0000 : 0x8000
        let full = a &+ b &+ c
        let res = full & top
        var f: UInt8 = 0
        if res & sign != 0 { f |= Flag.s }
        if res == 0 { f |= Flag.z }
        if (a & 0xFFF) + (b & 0xFFF) + c > 0xFFF { f |= Flag.h }
        if (a ^ res) & (b ^ res) & sign != 0 { f |= Flag.pv }
        if full > top { f |= Flag.c }
        r.f = f
        return res
    }

    func sbcWide(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let c: UInt32 = r.f & Flag.c != 0 ? 1 : 0
        let top: UInt32 = L ? 0xFF_FFFF : 0xFFFF
        let sign: UInt32 = L ? 0x80_0000 : 0x8000
        let full = Int64(a) - Int64(b) - Int64(c)
        let res = UInt32(truncatingIfNeeded: full) & top
        var f: UInt8 = Flag.n
        if res & sign != 0 { f |= Flag.s }
        if res == 0 { f |= Flag.z }
        if Int(a & 0xFFF) - Int(b & 0xFFF) - Int(c) < 0 { f |= Flag.h }
        if (a ^ b) & (a ^ res) & sign != 0 { f |= Flag.pv }
        if full < 0 { f |= Flag.c }
        r.f = f
        return res
    }

    /// CB-prefix rotate/shift group; returns the result and sets flags.
    func rotate(_ op: UInt8, _ v: UInt8) -> UInt8 {
        let cin: UInt8 = r.f & Flag.c
        var res: UInt8
        var cout: UInt8
        switch op {
        case 0: cout = v >> 7; res = v << 1 | cout                   // RLC
        case 1: cout = v & 1; res = v >> 1 | cout << 7               // RRC
        case 2: cout = v >> 7; res = v << 1 | cin                    // RL
        case 3: cout = v & 1; res = v >> 1 | cin << 7                // RR
        case 4: cout = v >> 7; res = v << 1                          // SLA
        case 5: cout = v & 1; res = (v >> 1) | (v & 0x80)            // SRA
        case 6: cout = v >> 7; res = v << 1 | 1                      // SLL (not an eZ80 op)
        default: cout = v & 1; res = v >> 1                          // SRL
        }
        r.f = szpTable[Int(res)] | cout
        return res
    }

    func daa() {
        var a = r.a
        let f = r.f
        var correction: UInt8 = 0
        var carry = f & Flag.c
        if f & Flag.h != 0 || a & 0x0F > 9 { correction |= 0x06 }
        if carry != 0 || a > 0x99 { correction |= 0x60; carry = Flag.c }
        let neg = f & Flag.n != 0
        let old = a
        a = neg ? a &- correction : a &+ correction
        var nf = szpTable[Int(a)] | carry | (f & Flag.n)
        if (old ^ a) & 0x10 != 0 { nf |= Flag.h }
        r.a = a
        r.f = nf
    }

    // MARK: - Main opcode table

    func executeMain(_ op: UInt8) {
        switch op {
        case 0x00: break                                             // NOP
        case 0x08:                                                   // EX AF,AF'
            let a = r.a, f = r.f
            r.a = r.a_; r.f = r.f_; r.a_ = a; r.f_ = f
        case 0x10:                                                   // DJNZ d
            let d = fetchDisplacement()
            r.b = r.b &- 1
            if r.b != 0 { r.pc = mask(r.pc &+ d, adl); scheduler.cycles &+= 1 }
        case 0x18:                                                   // JR d
            let d = fetchDisplacement()
            r.pc = mask(r.pc &+ d, adl)
            scheduler.cycles &+= 1
        case 0x20, 0x28, 0x30, 0x38:                                 // JR cc,d
            let d = fetchDisplacement()
            if condition((op >> 3) & 3) { r.pc = mask(r.pc &+ d, adl); scheduler.cycles &+= 1 }

        case 0x01, 0x11, 0x21:                                       // LD rp,nn
            setRP(op >> 4, fetchWord())
        case 0x31:
            if prefix != 0 {                                         // LD IY,(IX+d) / LD IX,(IY+d)
                let a = indexAddress()
                otherIndex = readWordAt(a)
            } else {
                sp = fetchWord()
            }
        case 0x09, 0x19, 0x29, 0x39:                                 // ADD HL,rp
            setIndex(addWide(index, rp(op >> 4)))

        case 0x02: writeByte(mask(r.bc, L), r.a)                     // LD (BC),A
        case 0x12: writeByte(mask(r.de, L), r.a)                     // LD (DE),A
        case 0x22: writeWordAt(fetchWord(), index)                   // LD (nn),HL
        case 0x32: writeByte(fetchWord(), r.a)                       // LD (nn),A
        case 0x0A: r.a = readByte(mask(r.bc, L))                     // LD A,(BC)
        case 0x1A: r.a = readByte(mask(r.de, L))                     // LD A,(DE)
        case 0x2A: setIndex(readWordAt(fetchWord()))                 // LD HL,(nn)
        case 0x3A: r.a = readByte(fetchWord())                       // LD A,(nn)

        case 0x03, 0x13, 0x23, 0x33:                                 // INC rp
            setRP(op >> 4, rp(op >> 4) &+ 1)
        case 0x0B, 0x1B, 0x2B, 0x3B:                                 // DEC rp
            setRP(op >> 4, rp(op >> 4) &- 1)

        case 0x34:                                                   // INC (HL)
            let a = indexAddress()
            writeByte(a, inc8(readByte(a)))
        case 0x35:                                                   // DEC (HL)
            let a = indexAddress()
            writeByte(a, dec8(readByte(a)))
        case 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C:               // INC r
            let y = (op >> 3) & 7
            setReg(y, inc8(reg(y)))
        case 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D:               // DEC r
            let y = (op >> 3) & 7
            setReg(y, dec8(reg(y)))
        case 0x36:                                                   // LD (HL),n
            let a = indexAddress()
            writeByte(a, fetch())
        case 0x3E:
            if prefix != 0 {                                         // LD (IX+d),IY / LD (IY+d),IX
                let a = indexAddress()
                writeWordAt(a, otherIndex)
            } else {
                r.a = fetch()
            }
        case 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E:                     // LD r,n
            setReg((op >> 3) & 7, fetch())

        case 0x07, 0x0F, 0x17, 0x1F, 0x27, 0x2F, 0x37, 0x3F:
            if prefix != 0 {
                executeIndexedWideLoad(op)
            } else {
                executeAccumulatorOp(op)
            }

        case 0x76:                                                   // HALT
            halted = true

        case 0x40...0x7F:                                            // LD r,r'
            let y = (op >> 3) & 7
            let z = op & 7
            if z == 6 {
                setRegPlain(y, readByte(indexAddress()))
            } else if y == 6 {
                let a = indexAddress()
                writeByte(a, regPlain(z))
            } else {
                setReg(y, reg(z))
            }

        case 0x80...0xBF:                                            // ALU A,r
            let z = op & 7
            let v = z == 6 ? readByte(indexAddress()) : reg(z)
            alu((op >> 3) & 7, v)

        case 0xC0, 0xC8, 0xD0, 0xD8, 0xE0, 0xE8, 0xF0, 0xF8:         // RET cc
            scheduler.cycles &+= 1
            if condition((op >> 3) & 7) { ret() }
        case 0xC1, 0xD1, 0xE1:                                       // POP rp2
            let v = pop()
            switch op {
            case 0xC1: put(&r.bc, v)
            case 0xD1: put(&r.de, v)
            default: setIndex(v)
            }
        case 0xF1:                                                   // POP AF
            r.af = UInt16(truncatingIfNeeded: pop())
        case 0xC9: ret()                                             // RET
        case 0xD9:                                                   // EXX
            let bc = r.bc, de = r.de, hl = r.hl
            r.bc = r.bc_; r.de = r.de_; r.hl = r.hl_
            r.bc_ = bc; r.de_ = de; r.hl_ = hl
        case 0xE9:                                                   // JP (HL)
            jump(index, wide: L)
        case 0xF9:                                                   // LD SP,HL
            sp = index
        case 0xC2, 0xCA, 0xD2, 0xDA, 0xE2, 0xEA, 0xF2, 0xFA:         // JP cc,nn
            let t = fetchWord()
            if condition((op >> 3) & 7) { jump(t, wide: IL) }
        case 0xC3:                                                   // JP nn
            jump(fetchWord(), wide: IL)
        case 0xCB:
            executeCB()
        case 0xD3:                                                   // OUT (n),A
            let n = fetch()
            portOut(UInt32(r.a) << 8 | UInt32(n), r.a)
        case 0xDB:                                                   // IN A,(n)
            let n = fetch()
            r.a = portIn(UInt32(r.a) << 8 | UInt32(n))
        case 0xE3:                                                   // EX (SP),HL
            let s = sp
            let v = readWordAt(s)
            writeWordAt(s, index)
            setIndex(v)
        case 0xEB:                                                   // EX DE,HL
            if L { let d = r.de; r.de = r.hl; r.hl = d } else {
                let d = r.de, h = r.hl
                put(&r.de, h); put(&r.hl, d)
            }
        case 0xF3:                                                   // DI
            ief1 = false; ief2 = false
        case 0xFB:                                                   // EI
            ief1 = true; ief2 = true; iefWait = true
        case 0xC4, 0xCC, 0xD4, 0xDC, 0xE4, 0xEC, 0xF4, 0xFC:         // CALL cc,nn
            let t = fetchWord()
            if condition((op >> 3) & 7) { call(t) }
        case 0xC5: push(mask(r.bc, L))                               // PUSH rp2
        case 0xD5: push(mask(r.de, L))
        case 0xE5: push(index)
        case 0xF5: push(UInt32(r.af))
        case 0xCD:                                                   // CALL nn
            call(fetchWord())
        case 0xED:
            executeED()
        case 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE:         // ALU A,n
            alu((op >> 3) & 7, fetch())
        case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF:         // RST p
            call(UInt32(op & 0x38))
        default:
            // 0xDD / 0xFD are consumed as prefixes before we get here.
            unsupported([op])
        }
    }

    /// RLCA, RRCA, RLA, RRA, DAA, CPL, SCF, CCF.
    private func executeAccumulatorOp(_ op: UInt8) {
        let a = r.a
        let keep = r.f & (Flag.s | Flag.z | Flag.pv)
        switch op {
        case 0x07:
            let c = a >> 7
            r.a = a << 1 | c
            r.f = keep | c | (r.a & (Flag.x | Flag.y))
        case 0x0F:
            let c = a & 1
            r.a = a >> 1 | c << 7
            r.f = keep | c | (r.a & (Flag.x | Flag.y))
        case 0x17:
            let c = a >> 7
            r.a = a << 1 | (r.f & Flag.c)
            r.f = keep | c | (r.a & (Flag.x | Flag.y))
        case 0x1F:
            let c = a & 1
            r.a = a >> 1 | (r.f & Flag.c) << 7
            r.f = keep | c | (r.a & (Flag.x | Flag.y))
        case 0x27:
            daa()
        case 0x2F:
            r.a = ~a
            r.f = (r.f & (Flag.s | Flag.z | Flag.pv | Flag.c)) | Flag.h | Flag.n | (r.a & (Flag.x | Flag.y))
        case 0x37:
            r.f = keep | Flag.c | (a & (Flag.x | Flag.y))
        default:
            let c = r.f & Flag.c
            r.f = keep | (c != 0 ? Flag.h : Flag.c) | (a & (Flag.x | Flag.y))
        }
    }

    /// eZ80 DD/FD 07..3F: LD rr,(IX+d) and LD (IX+d),rr.
    private func executeIndexedWideLoad(_ op: UInt8) {
        let y = (op >> 3) & 7
        let p = y >> 1
        let a = indexAddress()
        if y & 1 == 0 {
            setRP3(p, readWordAt(a))
        } else {
            writeWordAt(a, rp3(p))
        }
    }

    // MARK: - CB prefix

    private func executeCB() {
        let addr: UInt32?
        let op: UInt8
        if prefix != 0 {
            addr = indexAddress()          // displacement precedes the opcode
            op = fetch()
        } else {
            op = fetchOpcode()
            addr = (op & 7) == 6 ? mask(r.hl, L) : nil
        }
        let x = op >> 6
        let y = (op >> 3) & 7
        let z = op & 7
        if prefix != 0 && z != 6 {
            // Undocumented Z80 "copy result to register" forms do not exist on the eZ80.
            unsupported([prefix == 2 ? 0xDD : 0xFD, 0xCB, op])
        }
        if x == 0 && y == 6 {
            unsupported(prefix != 0 ? [prefix == 2 ? 0xDD : 0xFD, 0xCB, op] : [0xCB, op])
        }
        let v = addr.map { readByte($0) } ?? regPlain(z)
        switch x {
        case 0:
            let res = rotate(y, v)
            if let a = addr { writeByte(a, res) } else { setRegPlain(z, res) }
        case 1:
            let bit = v & (1 << y)
            var f = (r.f & Flag.c) | Flag.h | (v & (Flag.x | Flag.y))
            if bit == 0 { f |= Flag.z | Flag.pv }
            if y == 7 && bit != 0 { f |= Flag.s }
            r.f = f
        case 2:
            let res = v & ~(1 << y)
            if let a = addr { writeByte(a, res) } else { setRegPlain(z, res) }
        default:
            let res = v | (1 << y)
            if let a = addr { writeByte(a, res) } else { setRegPlain(z, res) }
        }
    }

    // MARK: - ED prefix

    private func executeED() {
        let op = fetchOpcode()
        prefix = 0
        let x = op >> 6
        let y = (op >> 3) & 7
        let z = op & 7
        let p = y >> 1
        let q = y & 1

        switch x {
        case 0:
            executeED0(op, y: y, z: z)
        case 1:
            executeED1(op, y: y, z: z, p: p, q: q)
        case 2:
            executeBlock(op)
        default:
            switch op {
            case 0xC2: blockIOX(input: true, delta: 1)               // INIRX
            case 0xC3: blockIOX(input: false, delta: 1)              // OTIRX
            case 0xCA: blockIOX(input: true, delta: -1)              // INDRX
            case 0xCB: blockIOX(input: false, delta: -1)             // OTDRX
            case 0xC7: r.i = UInt16(truncatingIfNeeded: r.hl)        // LD I,HL
            case 0xD7: put(&r.hl, UInt32(r.i)); if L { r.hl = UInt32(r.mbase) << 16 | UInt32(r.i) } // LD HL,I
            default: unsupported([0xED, op])
            }
        }
    }

    private func executeED0(_ op: UInt8, y: UInt8, z: UInt8) {
        switch z {
        case 0:                                                      // IN0 r,(n)
            let n = fetch()
            let v = portIn(UInt32(n))
            r.f = (r.f & Flag.c) | szpTable[Int(v)]
            if y != 6 { setRegPlain(y, v) }
        case 1:
            if y == 6 {                                              // LD IY,(HL)
                put(&r.iy, readWordAt(mask(r.hl, L)))
            } else {                                                 // OUT0 (n),r
                let n = fetch()
                portOut(UInt32(n), regPlain(y))
            }
        case 2, 3:
            if y & 1 == 0 {                                          // LEA rr,IX+d / LEA rr,IY+d
                let base = z == 2 ? r.ix : r.iy
                let v = mask(base &+ fetchDisplacement(), L)
                switch y >> 1 {
                case 0: put(&r.bc, v)
                case 1: put(&r.de, v)
                case 2: put(&r.hl, v)
                default: if z == 2 { put(&r.ix, v) } else { put(&r.iy, v) }
                }
            } else {
                unsupported([0xED, op])
            }
        case 4:                                                      // TST A,r
            let v = y == 6 ? readByte(mask(r.hl, L)) : regPlain(y)
            r.f = szpTable[Int(r.a & v)] | Flag.h
        case 6:
            if y == 7 {                                              // LD (HL),IY
                writeWordAt(mask(r.hl, L), mask(r.iy, L))
            } else {
                unsupported([0xED, op])
            }
        case 7:
            let p = y >> 1
            let a = mask(r.hl, L)
            if y & 1 == 0 {                                          // LD rr,(HL)
                let v = readWordAt(a)
                switch p {
                case 0: put(&r.bc, v)
                case 1: put(&r.de, v)
                case 2: put(&r.hl, v)
                default: put(&r.ix, v)
                }
            } else {                                                 // LD (HL),rr
                let v: UInt32
                switch p {
                case 0: v = r.bc
                case 1: v = r.de
                case 2: v = r.hl
                default: v = r.ix
                }
                writeWordAt(a, mask(v, L))
            }
        default:
            unsupported([0xED, op])
        }
    }

    private func executeED1(_ op: UInt8, y: UInt8, z: UInt8, p: UInt8, q: UInt8) {
        switch z {
        case 0:                                                      // IN r,(C)
            let v = portIn(r.bc & 0xFFFF)
            r.f = (r.f & Flag.c) | szpTable[Int(v)]
            if y != 6 { setRegPlain(y, v) }
        case 1:                                                      // OUT (C),r
            if y == 6 { unsupported([0xED, op]); return }
            portOut(r.bc & 0xFFFF, regPlain(y))
        case 2:
            let hl = mask(r.hl, L)
            let v: UInt32
            switch p {
            case 0: v = mask(r.bc, L)
            case 1: v = mask(r.de, L)
            case 2: v = hl
            default: v = sp
            }
            put(&r.hl, q == 0 ? sbcWide(hl, v) : adcWide(hl, v))     // SBC/ADC HL,rp
        case 3:
            let a = fetchWord()
            if q == 0 {                                              // LD (nn),rp
                let v: UInt32
                switch p {
                case 0: v = mask(r.bc, L)
                case 1: v = mask(r.de, L)
                case 2: v = mask(r.hl, L)
                default: v = sp
                }
                writeWordAt(a, v)
            } else {                                                 // LD rp,(nn)
                let v = readWordAt(a)
                switch p {
                case 0: put(&r.bc, v)
                case 1: put(&r.de, v)
                case 2: put(&r.hl, v)
                default: sp = v
                }
            }
        case 4:
            switch y {
            case 0:                                                  // NEG
                let a = r.a
                r.a = 0
                r.a = sub8(a, carry: 0)
            case 1, 3, 5, 7:                                         // MLT rr
                let product: UInt32
                switch p {
                case 0: product = UInt32(r.b) * UInt32(r.c); put(&r.bc, product)
                case 1: product = UInt32(r.d) * UInt32(r.e); put(&r.de, product)
                case 2: product = UInt32(r.h) * UInt32(r.l); put(&r.hl, product)
                default:
                    let s = sp
                    sp = UInt32(UInt8(truncatingIfNeeded: s >> 8)) * UInt32(UInt8(truncatingIfNeeded: s))
                }
                scheduler.cycles &+= 4
            case 2:                                                  // LEA IX,IY+d
                put(&r.ix, mask(r.iy &+ fetchDisplacement(), L))
            case 4:                                                  // TST A,n
                r.f = szpTable[Int(r.a & fetch())] | Flag.h
            case 6:                                                  // TSTIO n
                let n = fetch()
                let v = portIn(UInt32(r.c))
                r.f = szpTable[Int(v & n)] | Flag.h
            default:
                unsupported([0xED, op])
            }
        case 5:
            switch y {
            case 0:                                                  // RETN
                ret(); ief1 = ief2
            case 1:                                                  // RETI
                ret(); ief1 = ief2
            case 2:                                                  // LEA IY,IX+d
                put(&r.iy, mask(r.ix &+ fetchDisplacement(), L))
            case 4:                                                  // PEA IX+d
                push(mask(r.ix &+ fetchDisplacement(), L))
            case 5:                                                  // LD MB,A
                if adl { r.mbase = r.a }
            case 7:                                                  // STMIX
                madl = true
            default:
                unsupported([0xED, op])
            }
        case 6:
            switch y {
            case 0: im = 0
            case 2: im = 1
            case 3: im = 2
            case 4: push(mask(r.iy &+ fetchDisplacement(), L))       // PEA IY+d
            case 5: r.a = r.mbase                                    // LD A,MB
            case 6: halted = true                                    // SLP
            case 7: madl = false                                     // RSMIX
            default: unsupported([0xED, op])
            }
        default:
            switch y {
            case 0: r.i = (r.i & 0xFF00) | UInt16(r.a)               // LD I,A
            case 1: r.r = r.a                                        // LD R,A
            case 2, 3:                                               // LD A,I / LD A,R
                r.a = y == 2 ? UInt8(truncatingIfNeeded: r.i) : r.r
                r.f = (r.f & Flag.c) | (szpTable[Int(r.a)] & ~Flag.pv) | (ief2 ? Flag.pv : 0)
            case 4:                                                  // RRD
                let a = mask(r.hl, L)
                let m = readByte(a)
                writeByte(a, (r.a << 4) | (m >> 4))
                r.a = (r.a & 0xF0) | (m & 0x0F)
                r.f = (r.f & Flag.c) | szpTable[Int(r.a)]
            case 5:                                                  // RLD
                let a = mask(r.hl, L)
                let m = readByte(a)
                writeByte(a, (m << 4) | (r.a & 0x0F))
                r.a = (r.a & 0xF0) | (m >> 4)
                r.f = (r.f & Flag.c) | szpTable[Int(r.a)]
            default:
                unsupported([0xED, op])
            }
        }
    }

    // MARK: - Block instructions

    @inline(__always) private func step(_ v: inout UInt32, _ delta: Int) {
        put(&v, delta > 0 ? v &+ 1 : v &- 1)
    }

    /// Re-executes the current instruction on the next step (for repeating forms).
    @inline(__always) private func repeatInstruction() {
        r.pc = instructionPC
        scheduler.cycles &+= 1
    }

    private func executeBlock(_ op: UInt8) {
        switch op {
        case 0xA0, 0xA8, 0xB0, 0xB8:                                 // LDI/LDD/LDIR/LDDR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = readByte(mask(r.hl, L))
            writeByte(mask(r.de, L), v)
            step(&r.hl, d); step(&r.de, d)
            put(&r.bc, mask(r.bc, L) &- 1)
            let bcNonZero = mask(r.bc, L) != 0
            let n = r.a &+ v
            r.f = (r.f & (Flag.s | Flag.z | Flag.c)) | (bcNonZero ? Flag.pv : 0)
                | (n & Flag.x) | ((n << 4) & Flag.y)
            if op >= 0xB0 && bcNonZero { repeatInstruction() }
        case 0xA1, 0xA9, 0xB1, 0xB9:                                 // CPI/CPD/CPIR/CPDR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = readByte(mask(r.hl, L))
            let c = r.f & Flag.c
            _ = sub8(v, carry: 0)
            step(&r.hl, d)
            put(&r.bc, mask(r.bc, L) &- 1)
            let bcNonZero = mask(r.bc, L) != 0
            r.f = (r.f & ~(Flag.pv | Flag.c)) | c | (bcNonZero ? Flag.pv : 0)
            if op >= 0xB0 && bcNonZero && r.f & Flag.z == 0 { repeatInstruction() }
        case 0xA2, 0xAA, 0xB2, 0xBA:                                 // INI/IND/INIR/INDR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = portIn(r.bc & 0xFFFF)
            writeByte(mask(r.hl, L), v)
            step(&r.hl, d)
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0xB0 && r.b != 0 { repeatInstruction() }
        case 0xA3, 0xAB, 0xB3, 0xBB:                                 // OUTI/OUTD/OTIR/OTDR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = readByte(mask(r.hl, L))
            portOut(r.bc & 0xFFFF, v)
            step(&r.hl, d)
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0xB0 && r.b != 0 { repeatInstruction() }
        case 0x82, 0x8A, 0x92, 0x9A:                                 // INIM/INDM/INIMR/INDMR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = portIn(UInt32(r.c))
            writeByte(mask(r.hl, L), v)
            step(&r.hl, d)
            r.c = d > 0 ? r.c &+ 1 : r.c &- 1
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0x90 && r.b != 0 { repeatInstruction() }
        case 0x83, 0x8B, 0x93, 0x9B:                                 // OTIM/OTDM/OTIMR/OTDMR
            let d = op & 0x08 == 0 ? 1 : -1
            let v = readByte(mask(r.hl, L))
            portOut(UInt32(r.c), v)
            step(&r.hl, d)
            r.c = d > 0 ? r.c &+ 1 : r.c &- 1
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0x90 && r.b != 0 { repeatInstruction() }
        case 0x84, 0x8C, 0x94, 0x9C:                                 // INI2/IND2/INI2R/IND2R
            let d = op & 0x08 == 0 ? 1 : -1
            let v = portIn(r.bc & 0xFFFF)
            writeByte(mask(r.hl, L), v)
            step(&r.hl, d)
            r.c = d > 0 ? r.c &+ 1 : r.c &- 1
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0x90 && r.b != 0 { repeatInstruction() }
        case 0xA4, 0xAC, 0xB4, 0xBC:                                 // OUTI2/OUTD2/OTI2R/OTD2R
            let d = op & 0x08 == 0 ? 1 : -1
            let v = readByte(mask(r.hl, L))
            portOut(r.bc & 0xFFFF, v)
            step(&r.hl, d)
            r.c = d > 0 ? r.c &+ 1 : r.c &- 1
            r.b = r.b &- 1
            setBlockIOFlags(v)
            if op >= 0xB0 && r.b != 0 { repeatInstruction() }
        default:
            unsupported([0xED, op])
        }
    }

    /// INIRX / OTIRX / INDRX / OTDRX: port {D,E}, 24-bit BC counter.
    private func blockIOX(input: Bool, delta: Int) {
        let port = r.de & 0xFFFF
        if input {
            writeByte(mask(r.hl, L), portIn(port))
        } else {
            portOut(port, readByte(mask(r.hl, L)))
        }
        step(&r.hl, delta)
        put(&r.bc, mask(r.bc, L) &- 1)
        let done = mask(r.bc, L) == 0
        r.f = (r.f & ~(Flag.z | Flag.n)) | (done ? Flag.z : 0) | Flag.n
        if !done { repeatInstruction() }
    }

    @inline(__always) private func setBlockIOFlags(_ v: UInt8) {
        var f = r.f & ~(Flag.z | Flag.n | Flag.s)
        if r.b == 0 { f |= Flag.z }
        if r.b & 0x80 != 0 { f |= Flag.s }
        if v & 0x80 != 0 { f |= Flag.n }
        r.f = f
    }
}
