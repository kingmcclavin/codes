// Instruction decoding and execution for the Z80 core.
//
// Opcodes are decoded with the standard x/y/z/p/q bit-field scheme
// (x = op[7:6], y = op[5:3], z = op[2:0], p = y >> 1, q = y & 1).
// `idx` selects which register plays the role of HL: 0 = HL, 1 = IX (DD
// prefix), 2 = IY (FD prefix).

extension CPU {

    // MARK: - Dispatch

    @inline(__always)
    func executeInstruction() {
        lastOpcodePC = registers.pc
        let op = fetchOpcode()
        switch op {
        case 0xCB: executeCB()
        case 0xED: executeED()
        case 0xDD: executeIndexPrefix(1)
        case 0xFD: executeIndexPrefix(2)
        default: executeMain(op, 0)
        }
    }

    private func executeIndexPrefix(_ first: Int) {
        var idx = first
        while true {
            cycles &+= 4
            let op = fetchOpcode()
            switch op {
            case 0xDD: idx = 1        // a repeated prefix acts as a 4 T-state NOP
            case 0xFD: idx = 2
            case 0xCB: executeIndexedCB(idx); return
            case 0xED: executeED(); return   // ED cancels the index prefix
            default: executeMain(op, idx); return
            }
        }
    }

    // MARK: - Register helpers

    @inline(__always)
    func getHLX(_ idx: Int) -> UInt16 {
        switch idx {
        case 1: return registers.ix
        case 2: return registers.iy
        default: return registers.hl
        }
    }

    @inline(__always)
    func setHLX(_ idx: Int, _ value: UInt16) {
        switch idx {
        case 1: registers.ix = value
        case 2: registers.iy = value
        default: registers.hl = value
        }
    }

    /// 8-bit register by 3-bit code (never 6), with H/L replaced by the
    /// index register halves when a DD/FD prefix is active.
    @inline(__always)
    func getR(_ code: UInt8, _ idx: Int) -> UInt8 {
        switch code {
        case 0: return registers.b
        case 1: return registers.c
        case 2: return registers.d
        case 3: return registers.e
        case 4: return idx == 0 ? registers.h : UInt8(truncatingIfNeeded: getHLX(idx) >> 8)
        case 5: return idx == 0 ? registers.l : UInt8(truncatingIfNeeded: getHLX(idx))
        default: return registers.a
        }
    }

    @inline(__always)
    func setR(_ code: UInt8, _ value: UInt8, _ idx: Int) {
        switch code {
        case 0: registers.b = value
        case 1: registers.c = value
        case 2: registers.d = value
        case 3: registers.e = value
        case 4:
            if idx == 0 { registers.h = value } else { setHLX(idx, (getHLX(idx) & 0x00FF) | UInt16(value) << 8) }
        case 5:
            if idx == 0 { registers.l = value } else { setHLX(idx, (getHLX(idx) & 0xFF00) | UInt16(value)) }
        default: registers.a = value
        }
    }

    /// Register pair table `rp`: BC, DE, HL/IX/IY, SP.
    @inline(__always)
    func getRP(_ p: UInt8, _ idx: Int) -> UInt16 {
        switch p {
        case 0: return registers.bc
        case 1: return registers.de
        case 2: return getHLX(idx)
        default: return registers.sp
        }
    }

    @inline(__always)
    func setRP(_ p: UInt8, _ value: UInt16, _ idx: Int) {
        switch p {
        case 0: registers.bc = value
        case 1: registers.de = value
        case 2: setHLX(idx, value)
        default: registers.sp = value
        }
    }

    /// Register pair table `rp2`: BC, DE, HL/IX/IY, AF.
    @inline(__always)
    func getRP2(_ p: UInt8, _ idx: Int) -> UInt16 {
        p == 3 ? registers.af : getRP(p, idx)
    }

    @inline(__always)
    func setRP2(_ p: UInt8, _ value: UInt16, _ idx: Int) {
        if p == 3 { registers.af = value } else { setRP(p, value, idx) }
    }

    /// Address of the `(HL)` operand, or `(IX+d)`/`(IY+d)` when prefixed
    /// (fetching the displacement byte and adding its 8 extra T-states,
    /// minus `discount`).
    @inline(__always)
    func memoryOperandAddress(_ idx: Int, discount: UInt64 = 0) -> UInt16 {
        if idx == 0 { return registers.hl }
        let d = Int8(bitPattern: fetch8())
        let address = getHLX(idx) &+ UInt16(bitPattern: Int16(d))
        registers.wz = address
        cycles &+= 8 &- discount
        return address
    }

    @inline(__always)
    func condition(_ cc: UInt8) -> Bool {
        let f = registers.f
        switch cc {
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

    // MARK: - Unprefixed (and DD/FD-prefixed) opcodes

    func executeMain(_ op: UInt8, _ idx: Int) {
        let y = (op >> 3) & 7
        let z = op & 7
        switch op >> 6 {
        case 1:
            if op == 0x76 {
                halted = true
                cycles &+= 4
            } else if z == 6 {
                // LD r,(HL) — r is never an index half.
                let address = memoryOperandAddress(idx)
                setR(y, read8(address), 0)
                cycles &+= 7
            } else if y == 6 {
                let address = memoryOperandAddress(idx)
                write8(address, getR(z, 0))
                cycles &+= 7
            } else {
                setR(y, getR(z, idx), idx)
                cycles &+= 4
            }

        case 2:
            let value: UInt8
            if z == 6 {
                value = read8(memoryOperandAddress(idx))
                cycles &+= 7
            } else {
                value = getR(z, idx)
                cycles &+= 4
            }
            alu(y, value)

        case 0:
            executeBlock0(op, y, z, idx)

        default:
            executeBlock3(op, y, z, idx)
        }
    }

    private func executeBlock0(_ op: UInt8, _ y: UInt8, _ z: UInt8, _ idx: Int) {
        let p = y >> 1
        let q = y & 1
        switch z {
        case 0:
            switch y {
            case 0:
                cycles &+= 4
            case 1:
                let af = registers.af
                registers.af = registers.altAF
                registers.altAF = af
                cycles &+= 4
            case 2:
                let d = Int8(bitPattern: fetch8())
                registers.b &-= 1
                if registers.b != 0 {
                    registers.pc = registers.pc &+ UInt16(bitPattern: Int16(d))
                    registers.wz = registers.pc
                    cycles &+= 13
                } else {
                    cycles &+= 8
                }
            case 3:
                let d = Int8(bitPattern: fetch8())
                registers.pc = registers.pc &+ UInt16(bitPattern: Int16(d))
                registers.wz = registers.pc
                cycles &+= 12
            default:
                let d = Int8(bitPattern: fetch8())
                if condition(y - 4) {
                    registers.pc = registers.pc &+ UInt16(bitPattern: Int16(d))
                    registers.wz = registers.pc
                    cycles &+= 12
                } else {
                    cycles &+= 7
                }
            }

        case 1:
            if q == 0 {
                setRP(p, fetch16(), idx)
                cycles &+= 10
            } else {
                setHLX(idx, add16(getHLX(idx), getRP(p, idx)))
                cycles &+= 11
            }

        case 2:
            switch y {
            case 0: // LD (BC),A
                write8(registers.bc, registers.a)
                registers.wz = UInt16(registers.a) << 8 | ((registers.bc &+ 1) & 0xFF)
                cycles &+= 7
            case 1: // LD A,(BC)
                registers.a = read8(registers.bc)
                registers.wz = registers.bc &+ 1
                cycles &+= 7
            case 2: // LD (DE),A
                write8(registers.de, registers.a)
                registers.wz = UInt16(registers.a) << 8 | ((registers.de &+ 1) & 0xFF)
                cycles &+= 7
            case 3: // LD A,(DE)
                registers.a = read8(registers.de)
                registers.wz = registers.de &+ 1
                cycles &+= 7
            case 4: // LD (nn),HL
                let nn = fetch16()
                write16(nn, getHLX(idx))
                registers.wz = nn &+ 1
                cycles &+= 16
            case 5: // LD HL,(nn)
                let nn = fetch16()
                setHLX(idx, read16(nn))
                registers.wz = nn &+ 1
                cycles &+= 16
            case 6: // LD (nn),A
                let nn = fetch16()
                write8(nn, registers.a)
                registers.wz = UInt16(registers.a) << 8 | ((nn &+ 1) & 0xFF)
                cycles &+= 13
            default: // LD A,(nn)
                let nn = fetch16()
                registers.a = read8(nn)
                registers.wz = nn &+ 1
                cycles &+= 13
            }

        case 3:
            let v = getRP(p, idx)
            setRP(p, q == 0 ? v &+ 1 : v &- 1, idx)
            cycles &+= 6

        case 4, 5:
            let increment = z == 4
            if y == 6 {
                let address = memoryOperandAddress(idx)
                let v = read8(address)
                write8(address, increment ? inc8(v) : dec8(v))
                cycles &+= 11
            } else {
                let v = getR(y, idx)
                setR(y, increment ? inc8(v) : dec8(v), idx)
                cycles &+= 4
            }

        case 6:
            if y == 6 {
                let address = memoryOperandAddress(idx, discount: 3)
                write8(address, fetch8())
                cycles &+= 10
            } else {
                setR(y, fetch8(), idx)
                cycles &+= 7
            }

        default:
            accumulatorOp(y)
            cycles &+= 4
        }
    }

    private func executeBlock3(_ op: UInt8, _ y: UInt8, _ z: UInt8, _ idx: Int) {
        let p = y >> 1
        let q = y & 1
        switch z {
        case 0:
            if condition(y) {
                registers.pc = pop()
                registers.wz = registers.pc
                cycles &+= 11
            } else {
                cycles &+= 5
            }

        case 1:
            if q == 0 {
                setRP2(p, pop(), idx)
                cycles &+= 10
            } else {
                switch p {
                case 0:
                    registers.pc = pop()
                    registers.wz = registers.pc
                    cycles &+= 10
                case 1:
                    let bc = registers.bc, de = registers.de, hl = registers.hl
                    registers.bc = registers.altBC
                    registers.de = registers.altDE
                    registers.hl = registers.altHL
                    registers.altBC = bc
                    registers.altDE = de
                    registers.altHL = hl
                    cycles &+= 4
                case 2:
                    registers.pc = getHLX(idx)
                    cycles &+= 4
                default:
                    registers.sp = getHLX(idx)
                    cycles &+= 6
                }
            }

        case 2:
            let nn = fetch16()
            registers.wz = nn
            if condition(y) { registers.pc = nn }
            cycles &+= 10

        case 3:
            switch y {
            case 0:
                let nn = fetch16()
                registers.pc = nn
                registers.wz = nn
                cycles &+= 10
            case 2: // OUT (n),A
                let n = fetch8()
                let a = registers.a
                portOut(UInt16(a) << 8 | UInt16(n), a)
                registers.wz = UInt16(a) << 8 | UInt16(n &+ 1)
                cycles &+= 11
            case 3: // IN A,(n)
                let n = fetch8()
                let port = UInt16(registers.a) << 8 | UInt16(n)
                registers.a = portIn(port)
                registers.wz = port &+ 1
                cycles &+= 11
            case 4: // EX (SP),HL
                let v = read16(registers.sp)
                write16(registers.sp, getHLX(idx))
                setHLX(idx, v)
                registers.wz = v
                cycles &+= 19
            case 5: // EX DE,HL (never affected by an index prefix)
                let de = registers.de
                registers.de = registers.hl
                registers.hl = de
                cycles &+= 4
            case 6:
                iff1 = false
                iff2 = false
                cycles &+= 4
            case 7:
                iff1 = true
                iff2 = true
                interruptInhibit = true
                cycles &+= 4
            default:
                // 0xCB is dispatched before reaching here.
                preconditionFailure("CB prefix reached executeMain")
            }

        case 4:
            let nn = fetch16()
            registers.wz = nn
            if condition(y) {
                push(registers.pc)
                registers.pc = nn
                cycles &+= 17
            } else {
                cycles &+= 10
            }

        case 5:
            if q == 0 {
                push(getRP2(p, idx))
                cycles &+= 11
            } else {
                // p == 0: CALL nn. DD/ED/FD are dispatched before reaching here.
                let nn = fetch16()
                push(registers.pc)
                registers.pc = nn
                registers.wz = nn
                cycles &+= 17
            }

        case 6:
            alu(y, fetch8())
            cycles &+= 7

        default:
            push(registers.pc)
            registers.pc = UInt16(y) << 3
            registers.wz = registers.pc
            cycles &+= 11
        }
    }

    // MARK: - CB prefix

    private func executeCB() {
        let op = fetchOpcode()
        let x = op >> 6
        let y = (op >> 3) & 7
        let z = op & 7
        if z == 6 {
            let address = registers.hl
            let v = read8(address)
            switch x {
            case 0:
                write8(address, rotateShift(y, v))
                cycles &+= 15
            case 1:
                bitTest(y, v, xySource: UInt8(truncatingIfNeeded: registers.wz >> 8))
                cycles &+= 12
            case 2:
                write8(address, v & ~(1 << y))
                cycles &+= 15
            default:
                write8(address, v | (1 << y))
                cycles &+= 15
            }
        } else {
            let v = getR(z, 0)
            switch x {
            case 0: setR(z, rotateShift(y, v), 0)
            case 1: bitTest(y, v, xySource: v)
            case 2: setR(z, v & ~(1 << y), 0)
            default: setR(z, v | (1 << y), 0)
            }
            cycles &+= 8
        }
    }

    /// DDCB/FDCB: `prefix CB d op`. The displacement precedes the opcode and
    /// the opcode byte is not an M1 cycle (R is not incremented for it).
    private func executeIndexedCB(_ idx: Int) {
        let d = Int8(bitPattern: fetch8())
        let op = fetch8()
        let address = getHLX(idx) &+ UInt16(bitPattern: Int16(d))
        registers.wz = address
        let x = op >> 6
        let y = (op >> 3) & 7
        let z = op & 7
        let v = read8(address)
        if x == 1 {
            bitTest(y, v, xySource: UInt8(truncatingIfNeeded: address >> 8))
            cycles &+= 16
            return
        }
        let result: UInt8
        switch x {
        case 0: result = rotateShift(y, v)
        case 2: result = v & ~(1 << y)
        default: result = v | (1 << y)
        }
        write8(address, result)
        // Undocumented: the result is also copied into register z.
        if z != 6 { setR(z, result, 0) }
        cycles &+= 19
    }

    // MARK: - ED prefix

    private func executeED() {
        let op = fetchOpcode()
        let x = op >> 6
        let y = (op >> 3) & 7
        let z = op & 7
        let p = y >> 1
        let q = y & 1

        if x == 1 {
            switch z {
            case 0: // IN r,(C) / IN (C)
                let bc = registers.bc
                let v = portIn(bc)
                registers.wz = bc &+ 1
                registers.f = (registers.f & Flag.c) | sz53p[Int(v)]
                if y != 6 { setR(y, v, 0) }
                cycles &+= 12
            case 1: // OUT (C),r / OUT (C),0
                let bc = registers.bc
                portOut(bc, y == 6 ? 0 : getR(y, 0))
                registers.wz = bc &+ 1
                cycles &+= 12
            case 2:
                if q == 0 { sbc16(getRP(p, 0)) } else { adc16(getRP(p, 0)) }
                cycles &+= 15
            case 3:
                let nn = fetch16()
                if q == 0 {
                    write16(nn, getRP(p, 0))
                } else {
                    setRP(p, read16(nn), 0)
                }
                registers.wz = nn &+ 1
                cycles &+= 20
            case 4: // NEG (and mirrors)
                let a = registers.a
                registers.a = 0
                sub8(a, carry: false)
                cycles &+= 8
            case 5: // RETN / RETI (and mirrors)
                iff1 = iff2
                registers.pc = pop()
                registers.wz = registers.pc
                cycles &+= 14
            case 6:
                // y & 3 = 0, 1, 2, 3 selects IM 0, 0 (undocumented 0/1), 1, 2.
                let m = y & 3
                interruptMode = m == 0 ? 0 : m - 1
                cycles &+= 8
            default:
                switch y {
                case 0: registers.i = registers.a; cycles &+= 9
                case 1: registers.r = registers.a; cycles &+= 9
                case 2:
                    registers.a = registers.i
                    registers.f = (registers.f & Flag.c) | sz53[Int(registers.a)] | (iff2 ? Flag.pv : 0)
                    cycles &+= 9
                case 3:
                    registers.a = registers.r
                    registers.f = (registers.f & Flag.c) | sz53[Int(registers.a)] | (iff2 ? Flag.pv : 0)
                    cycles &+= 9
                case 4: // RRD
                    let hl = registers.hl
                    let v = read8(hl)
                    let a = registers.a
                    write8(hl, (a << 4) | (v >> 4))
                    registers.a = (a & 0xF0) | (v & 0x0F)
                    registers.f = (registers.f & Flag.c) | sz53p[Int(registers.a)]
                    registers.wz = hl &+ 1
                    cycles &+= 18
                case 5: // RLD
                    let hl = registers.hl
                    let v = read8(hl)
                    let a = registers.a
                    write8(hl, (v << 4) | (a & 0x0F))
                    registers.a = (a & 0xF0) | (v >> 4)
                    registers.f = (registers.f & Flag.c) | sz53p[Int(registers.a)]
                    registers.wz = hl &+ 1
                    cycles &+= 18
                default:
                    undefinedED(op)
                }
            }
            return
        }

        if x == 2 && y >= 4 && z <= 3 {
            blockInstruction(y, z)
            return
        }

        undefinedED(op)
    }

    private func undefinedED(_ op: UInt8) {
        cycles &+= 8
        report(.undefinedEDOpcode(opcode: op, pc: registers.pc &- 2))
    }

    // MARK: - Block transfer / search / I/O

    private func blockInstruction(_ y: UInt8, _ z: UInt8) {
        let increment = y & 1 == 0         // LDI/CPI/INI/OUTI vs the D variants
        let repeats = y >= 6               // the "R" variants
        let delta: UInt16 = increment ? 1 : 0xFFFF

        switch z {
        case 0: // LDI / LDD / LDIR / LDDR
            let v = read8(registers.hl)
            write8(registers.de, v)
            registers.hl &+= delta
            registers.de &+= delta
            registers.bc &-= 1
            let n = v &+ registers.a
            var f = registers.f & (Flag.s | Flag.z | Flag.c)
            if registers.bc != 0 { f |= Flag.pv }
            f |= n & Flag.x
            f |= (n << 4) & Flag.y
            registers.f = f
            if repeats && registers.bc != 0 {
                registers.pc &-= 2
                registers.wz = registers.pc &+ 1
                cycles &+= 21
            } else {
                cycles &+= 16
            }

        case 1: // CPI / CPD / CPIR / CPDR
            let v = read8(registers.hl)
            let a = registers.a
            let result = a &- v
            let halfCarry = (a ^ v ^ result) & Flag.h
            registers.hl &+= delta
            registers.bc &-= 1
            registers.wz &+= delta
            let n = result &- (halfCarry != 0 ? 1 : 0)
            var f = (registers.f & Flag.c) | Flag.n | (sz53[Int(result)] & ~Flag.xy) | halfCarry
            if registers.bc != 0 { f |= Flag.pv }
            f |= n & Flag.x
            f |= (n << 4) & Flag.y
            registers.f = f
            if repeats && registers.bc != 0 && result != 0 {
                registers.pc &-= 2
                registers.wz = registers.pc &+ 1
                cycles &+= 21
            } else {
                cycles &+= 16
            }

        case 2: // INI / IND / INIR / INDR
            let bc = registers.bc
            let v = portIn(bc)
            registers.wz = bc &+ delta
            write8(registers.hl, v)
            registers.b &-= 1
            registers.hl &+= delta
            let k = UInt16(v) + UInt16(registers.c &+ UInt8(truncatingIfNeeded: delta))
            blockIOFlags(v, k)
            if repeats && registers.b != 0 {
                registers.pc &-= 2
                cycles &+= 21
            } else {
                cycles &+= 16
            }

        default: // OUTI / OUTD / OTIR / OTDR
            let v = read8(registers.hl)
            registers.b &-= 1
            registers.wz = registers.bc &+ delta
            portOut(registers.bc, v)
            registers.hl &+= delta
            let k = UInt16(v) + UInt16(registers.l)
            blockIOFlags(v, k)
            if repeats && registers.b != 0 {
                registers.pc &-= 2
                cycles &+= 21
            } else {
                cycles &+= 16
            }
        }
    }

    @inline(__always)
    private func blockIOFlags(_ value: UInt8, _ k: UInt16) {
        let b = registers.b
        var f = sz53[Int(b)]
        if value & 0x80 != 0 { f |= Flag.n }
        if k > 0xFF { f |= Flag.h | Flag.c }
        f |= parity[Int((UInt8(truncatingIfNeeded: k) & 7) ^ b)]
        registers.f = f
    }
}
