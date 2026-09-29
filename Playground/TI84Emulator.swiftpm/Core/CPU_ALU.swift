// Arithmetic, logic, rotate and bit operations with exact Z80 flag behaviour,
// including the undocumented X (bit 3) and Y (bit 5) flags.

extension CPU {

    /// ALU operation selected by y: ADD, ADC, SUB, SBC, AND, XOR, OR, CP.
    @inline(__always)
    func alu(_ y: UInt8, _ v: UInt8) {
        switch y {
        case 0: add8(v, carry: false)
        case 1: add8(v, carry: true)
        case 2: sub8(v, carry: false)
        case 3: sub8(v, carry: true)
        case 4:
            registers.a &= v
            registers.f = sz53p[Int(registers.a)] | Flag.h
        case 5:
            registers.a ^= v
            registers.f = sz53p[Int(registers.a)]
        case 6:
            registers.a |= v
            registers.f = sz53p[Int(registers.a)]
        default:
            compare(v)
        }
    }

    @inline(__always)
    func add8(_ v: UInt8, carry: Bool) {
        let a = registers.a
        let c: UInt16 = carry ? UInt16(registers.f & Flag.c) : 0
        let wide = UInt16(a) + UInt16(v) + c
        let result = UInt8(truncatingIfNeeded: wide)
        var f = sz53[Int(result)] | ((a ^ v ^ result) & Flag.h)
        if wide > 0xFF { f |= Flag.c }
        if (a ^ ~v) & (a ^ result) & 0x80 != 0 { f |= Flag.pv }
        registers.a = result
        registers.f = f
    }

    @inline(__always)
    func sub8(_ v: UInt8, carry: Bool) {
        registers.a = subtract(v, carry: carry)
    }

    @inline(__always)
    func compare(_ v: UInt8) {
        _ = subtract(v, carry: false)
        // CP takes X/Y from the operand, not from the result.
        registers.f = (registers.f & ~Flag.xy) | (v & Flag.xy)
    }

    @inline(__always)
    private func subtract(_ v: UInt8, carry: Bool) -> UInt8 {
        let a = registers.a
        let c: Int = carry ? Int(registers.f & Flag.c) : 0
        let wide = Int(a) - Int(v) - c
        let result = UInt8(truncatingIfNeeded: wide)
        var f = sz53[Int(result)] | Flag.n | ((a ^ v ^ result) & Flag.h)
        if wide < 0 { f |= Flag.c }
        if (a ^ v) & (a ^ result) & 0x80 != 0 { f |= Flag.pv }
        registers.f = f
        return result
    }

    @inline(__always)
    func inc8(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        var f = (registers.f & Flag.c) | sz53[Int(r)]
        if r == 0x80 { f |= Flag.pv }
        if r & 0x0F == 0 { f |= Flag.h }
        registers.f = f
        return r
    }

    @inline(__always)
    func dec8(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        var f = (registers.f & Flag.c) | sz53[Int(r)] | Flag.n
        if r == 0x7F { f |= Flag.pv }
        if r & 0x0F == 0x0F { f |= Flag.h }
        registers.f = f
        return r
    }

    /// ADD HL,rr (also IX/IY): only H, N, C and X/Y are affected.
    @inline(__always)
    func add16(_ a: UInt16, _ b: UInt16) -> UInt16 {
        let wide = UInt32(a) + UInt32(b)
        let result = UInt16(truncatingIfNeeded: wide)
        var f = registers.f & (Flag.s | Flag.z | Flag.pv)
        f |= UInt8(truncatingIfNeeded: result >> 8) & Flag.xy
        f |= UInt8(truncatingIfNeeded: (UInt32(a) ^ UInt32(b) ^ wide) >> 8) & Flag.h
        if wide > 0xFFFF { f |= Flag.c }
        registers.f = f
        registers.wz = a &+ 1
        return result
    }

    func adc16(_ v: UInt16) {
        let hl = registers.hl
        let c = UInt32(registers.f & Flag.c)
        let wide = UInt32(hl) + UInt32(v) + c
        let result = UInt16(truncatingIfNeeded: wide)
        var f = UInt8(truncatingIfNeeded: result >> 8) & (Flag.s | Flag.xy)
        if result == 0 { f |= Flag.z }
        f |= UInt8(truncatingIfNeeded: (UInt32(hl) ^ UInt32(v) ^ wide) >> 8) & Flag.h
        if (hl ^ ~v) & (hl ^ result) & 0x8000 != 0 { f |= Flag.pv }
        if wide > 0xFFFF { f |= Flag.c }
        registers.wz = hl &+ 1
        registers.hl = result
        registers.f = f
    }

    func sbc16(_ v: UInt16) {
        let hl = registers.hl
        let c = Int(registers.f & Flag.c)
        let wide = Int(hl) - Int(v) - c
        let result = UInt16(truncatingIfNeeded: wide)
        var f = (UInt8(truncatingIfNeeded: result >> 8) & (Flag.s | Flag.xy)) | Flag.n
        if result == 0 { f |= Flag.z }
        f |= UInt8(truncatingIfNeeded: (hl ^ v ^ result) >> 8) & Flag.h
        if (hl ^ v) & (hl ^ result) & 0x8000 != 0 { f |= Flag.pv }
        if wide < 0 { f |= Flag.c }
        registers.wz = hl &+ 1
        registers.hl = result
        registers.f = f
    }

    /// RLCA, RRCA, RLA, RRA, DAA, CPL, SCF, CCF.
    func accumulatorOp(_ y: UInt8) {
        let a = registers.a
        let f = registers.f
        let keep = f & (Flag.s | Flag.z | Flag.pv)
        switch y {
        case 0: // RLCA
            let r = a << 1 | a >> 7
            registers.a = r
            registers.f = keep | (r & Flag.xy) | (a >> 7)
        case 1: // RRCA
            let r = a >> 1 | a << 7
            registers.a = r
            registers.f = keep | (r & Flag.xy) | (a & 1)
        case 2: // RLA
            let r = a << 1 | (f & Flag.c)
            registers.a = r
            registers.f = keep | (r & Flag.xy) | (a >> 7)
        case 3: // RRA
            let r = a >> 1 | (f & Flag.c) << 7
            registers.a = r
            registers.f = keep | (r & Flag.xy) | (a & 1)
        case 4:
            daa()
        case 5: // CPL
            let r = ~a
            registers.a = r
            registers.f = (f & (Flag.s | Flag.z | Flag.pv | Flag.c)) | (r & Flag.xy) | Flag.h | Flag.n
        case 6: // SCF
            registers.f = keep | (a & Flag.xy) | Flag.c
        default: // CCF
            let oldCarry = f & Flag.c
            registers.f = keep | (a & Flag.xy) | (oldCarry != 0 ? Flag.h : Flag.c)
        }
    }

    func daa() {
        let a = registers.a
        let f = registers.f
        var correction: UInt8 = 0
        var carry = f & Flag.c
        if f & Flag.h != 0 || a & 0x0F > 9 { correction = 0x06 }
        if carry != 0 || a > 0x99 {
            correction |= 0x60
            carry = Flag.c
        }
        let result: UInt8
        let half: UInt8
        if f & Flag.n != 0 {
            result = a &- correction
            half = (f & Flag.h != 0 && a & 0x0F < 6) ? Flag.h : 0
        } else {
            result = a &+ correction
            half = a & 0x0F > 9 ? Flag.h : 0
        }
        registers.a = result
        registers.f = sz53p[Int(result)] | carry | (f & Flag.n) | half
    }

    /// CB-prefixed rotate/shift selected by y: RLC, RRC, RL, RR, SLA, SRA, SLL, SRL.
    @inline(__always)
    func rotateShift(_ y: UInt8, _ v: UInt8) -> UInt8 {
        let r: UInt8
        let carry: UInt8
        switch y {
        case 0: r = v << 1 | v >> 7; carry = v >> 7
        case 1: r = v >> 1 | v << 7; carry = v & 1
        case 2: r = v << 1 | (registers.f & Flag.c); carry = v >> 7
        case 3: r = v >> 1 | (registers.f & Flag.c) << 7; carry = v & 1
        case 4: r = v << 1; carry = v >> 7
        case 5: r = v >> 1 | (v & 0x80); carry = v & 1
        case 6: r = v << 1 | 1; carry = v >> 7       // undocumented SLL
        default: r = v >> 1; carry = v & 1
        }
        registers.f = sz53p[Int(r)] | carry
        return r
    }

    /// BIT n,v. `xySource` supplies the undocumented X/Y flags: the operand
    /// for registers, MEMPTR high byte for (HL), address high byte for (IX+d).
    @inline(__always)
    func bitTest(_ bit: UInt8, _ v: UInt8, xySource: UInt8) {
        let set = v & (1 << bit)
        var f = (registers.f & Flag.c) | Flag.h | (xySource & Flag.xy)
        if set == 0 { f |= Flag.z | Flag.pv }
        if bit == 7 && set != 0 { f |= Flag.s }
        registers.f = f
    }
}
