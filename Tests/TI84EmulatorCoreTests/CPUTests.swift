import XCTest
@testable import TI84EmulatorCore

final class CPUTests: XCTestCase {

    // MARK: Registers & loads

    func testResetState() {
        let m = TestMachine(program: [])
        m.cpu.reset()
        XCTAssertEqual(m.r.pc, 0)
        XCTAssertEqual(m.r.af, 0xFFFF)
        XCTAssertEqual(m.r.sp, 0xFFFF)
        XCTAssertFalse(m.cpu.iff1)
        XCTAssertEqual(m.cpu.interruptMode, 0)
    }

    func testRegisterPairsAndExchange() {
        let m = TestMachine { a in
            a.ldBC(0x1234); a.ldDE(0x5678); a.ldHL(0x9ABC)
            a.db(0xD9)                    // EXX
            a.ldBC(0x1111); a.ldDE(0x2222); a.ldHL(0x3333)
            a.db(0xD9)                    // EXX
            a.db(0xEB)                    // EX DE,HL
            a.ldA(0x42); a.db(0x08)       // EX AF,AF'
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.bc, 0x1234)
        XCTAssertEqual(m.r.de, 0x9ABC)
        XCTAssertEqual(m.r.hl, 0x5678)
        XCTAssertEqual(m.r.altBC, 0x1111)
        XCTAssertEqual(m.r.altHL, 0x3333)
        XCTAssertEqual(m.r.altAF >> 8, 0x42)
    }

    func testLoadStoreMemory() {
        let m = TestMachine { a in
            a.ldA(0x5A); a.ldMemA(0x8000)
            a.ldHL(0xBEEF); a.db(0x22); a.dw(0x8010)   // LD (8010),HL
            a.db(0x2A); a.dw(0x8000)                   // LD HL,(8000)
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.memory.read(0x8000), 0x5A)
        XCTAssertEqual(m.memory.read16(0x8010), 0xBEEF)
        XCTAssertEqual(m.r.l, 0x5A)
    }

    // MARK: Flags

    func testAddOverflowAndHalfCarry() {
        let m = TestMachine { a in a.ldA(0x7F); a.db(0xC6, 0x01); a.halt() }   // ADD A,1
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 0x80)
        XCTAssertTrue(m.r.flag(Flag.s))
        XCTAssertTrue(m.r.flag(Flag.h))
        XCTAssertTrue(m.r.flag(Flag.pv))
        XCTAssertFalse(m.r.flag(Flag.z))
        XCTAssertFalse(m.r.flag(Flag.c))
        XCTAssertFalse(m.r.flag(Flag.n))
    }

    func testSubtractCarryAndZero() {
        let m = TestMachine { a in
            a.ldA(0x10); a.db(0xD6, 0x20)             // SUB 20h -> F0, carry
            a.db(0x47)                                // LD B,A
            a.ldA(0x33); a.db(0xFE, 0x33)             // CP 33h -> Z
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0xF0)
        XCTAssertEqual(m.r.a, 0x33)
        XCTAssertTrue(m.r.flag(Flag.z))
        XCTAssertTrue(m.r.flag(Flag.n))
        XCTAssertFalse(m.r.flag(Flag.c))
    }

    func testCompareTakesXYFromOperand() {
        let m = TestMachine { a in a.ldA(0x00); a.db(0xFE, 0x28); a.halt() }   // CP 28h
        m.runUntilHalt()
        XCTAssertEqual(m.r.f & Flag.xy, 0x28)
    }

    func testIncDecFlags() {
        let m = TestMachine { a in
            a.ldA(0x7F); a.db(0x3C)                   // INC A -> 80, PV, H
            a.db(0x47)                                // LD B,A
            a.db(0x05)                                // DEC B -> 7F, PV, H, N
            a.halt()
        }
        m.cpu.registers.f = Flag.c
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0x7F)
        XCTAssertTrue(m.r.flag(Flag.pv))
        XCTAssertTrue(m.r.flag(Flag.h))
        XCTAssertTrue(m.r.flag(Flag.n))
        XCTAssertTrue(m.r.flag(Flag.c), "INC/DEC must preserve carry")
    }

    func testDAA() {
        let m = TestMachine { a in a.ldA(0x15); a.db(0xC6, 0x27); a.db(0x27); a.halt() }  // ADD 27h; DAA
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 0x42)
        let s = TestMachine { a in a.ldA(0x42); a.db(0xD6, 0x15); a.db(0x27); a.halt() }  // SUB 15h; DAA
        s.runUntilHalt()
        XCTAssertEqual(s.r.a, 0x27)
    }

    func testLogicalOps() {
        let m = TestMachine { a in
            a.ldA(0xF0); a.db(0xE6, 0x3C)             // AND 3Ch -> 30
            a.db(0x47)
            a.ldA(0xF0); a.db(0xEE, 0xFF)             // XOR FFh -> 0F
            a.db(0x4F)
            a.ldA(0x00); a.db(0xF6, 0x00)             // OR 0 -> Z, P
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0x30)
        XCTAssertEqual(m.r.c, 0x0F)
        XCTAssertTrue(m.r.flag(Flag.z))
        XCTAssertTrue(m.r.flag(Flag.pv))
    }

    func test16BitArithmetic() {
        let m = TestMachine { a in
            a.ldHL(0xFFFF); a.ldBC(0x0001)
            a.db(0x09)                                // ADD HL,BC -> 0000, C
            a.ldHL(0x7FFF); a.ldDE(0x0000)
            a.db(0xED, 0x5A)                          // ADC HL,DE (carry in) -> 8000, overflow
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.hl, 0x8000)
        XCTAssertTrue(m.r.flag(Flag.pv))
        XCTAssertTrue(m.r.flag(Flag.s))

        let s = TestMachine { a in
            a.db(0xB7)                                // OR A (clear carry)
            a.ldHL(0x1000); a.ldBC(0x1000)
            a.db(0xED, 0x42)                          // SBC HL,BC -> 0, Z
            a.halt()
        }
        s.runUntilHalt()
        XCTAssertEqual(s.r.hl, 0)
        XCTAssertTrue(s.r.flag(Flag.z))
        XCTAssertTrue(s.r.flag(Flag.n))
    }

    // MARK: Stack, calls, branches

    func testCallReturnAndStack() {
        let m = TestMachine { a in
            a.ldSP(0x9000)
            a.ldBC(0xCAFE); a.db(0xC5)                // PUSH BC
            a.call("sub")
            a.db(0xD1)                                // POP DE
            a.halt()
            a.label("sub")
            a.ldA(0x99)
            a.ret()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 0x99)
        XCTAssertEqual(m.r.de, 0xCAFE)
        XCTAssertEqual(m.r.sp, 0x9000)
    }

    func testRSTAndConditionalReturn() {
        var asm = Asm(origin: 0)
        asm.ldSP(0x9000)
        asm.db(0xAF)          // XOR A (Z set)
        asm.db(0xEF)          // RST 28h
        asm.halt()
        while asm.pc < 0x28 { asm.nop() }
        asm.ldB(0x77)
        asm.db(0xC8)          // RET Z
        asm.ldB(0x00)
        asm.ret()
        let m = TestMachine(program: asm.assembled())
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0x77)
    }

    func testRelativeJumpsAndDJNZ() {
        let m = TestMachine { a in
            a.ldB(10); a.ldA(0)
            a.label("loop")
            a.db(0x3C)                               // INC A
            a.djnz("loop")
            a.db(0xFE, 10)                           // CP 10
            a.jrZ("ok")
            a.ldA(0xEE)
            a.label("ok")
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 10)
        XCTAssertEqual(m.r.b, 0)
    }

    // MARK: Prefixes

    func testIndexRegistersWithDisplacement() {
        let m = TestMachine { a in
            a.db(0xDD, 0x21); a.dw(0x8010)            // LD IX,8010
            a.db(0xDD, 0x36, 0xFE, 0x5A)              // LD (IX-2),5Ah
            a.db(0xDD, 0x7E, 0xFE)                    // LD A,(IX-2)
            a.db(0xFD, 0x21); a.dw(0x8000)            // LD IY,8000
            a.db(0xFD, 0x77, 0x05)                    // LD (IY+5),A
            a.db(0xDD, 0x34, 0x03)                    // INC (IX+3)
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.memory.read(0x800E), 0x5A)
        XCTAssertEqual(m.memory.read(0x8005), 0x5A)
        XCTAssertEqual(m.memory.read(0x8013), 0x01)
        XCTAssertEqual(m.r.a, 0x5A)
    }

    func testUndocumentedIndexHalves() {
        let m = TestMachine { a in
            a.db(0xDD, 0x21); a.dw(0x1234)            // LD IX,1234
            a.db(0xDD, 0x7C)                          // LD A,IXH
            a.db(0xDD, 0x6F)                          // LD IXL,A
            a.db(0xFD, 0x26, 0x99)                    // LD IYH,99h
            a.db(0xDD, 0x66, 0x00)                    // LD H,(IX+0): H is the real H
            a.halt()
        }
        m.memory.write(0x1212, value: 0x77)
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 0x12)
        XCTAssertEqual(m.r.ix, 0x1212)
        XCTAssertEqual(m.r.iy >> 8, 0x99)
        XCTAssertEqual(m.r.h, 0x77)
    }

    func testCBPrefixBitOps() {
        let m = TestMachine { a in
            a.ldA(0x81)
            a.db(0xCB, 0x07)                          // RLC A -> 03, C
            a.db(0xCB, 0x7F)                          // BIT 7,A -> Z
            a.db(0xF5); a.db(0xD1)                    // PUSH AF; POP DE (keep flags in E)
            a.ldHL(0x8000)
            a.db(0xCB, 0xFE)                          // SET 7,(HL)
            a.db(0xCB, 0x36)                          // SLL (HL) (undocumented)
            a.halt()
        }
        m.runUntilHalt()
        XCTAssertEqual(m.r.a, 0x03)
        XCTAssertNotEqual(m.r.e & Flag.z, 0, "BIT 7 of 03h is zero")
        XCTAssertNotEqual(m.r.e & Flag.h, 0)
        XCTAssertNotEqual(m.r.e & Flag.c, 0, "carry from RLC preserved by BIT")
        XCTAssertEqual(m.memory.read(0x8000), 0x01)   // 80h << 1 | 1
        XCTAssertTrue(m.r.flag(Flag.c))
    }

    func testDDCBWithRegisterCopy() {
        let m = TestMachine { a in
            a.db(0xDD, 0x21); a.dw(0x8000)
            a.db(0xDD, 0xCB, 0x04, 0xC0)              // SET 0,(IX+4),B (undocumented copy)
            a.halt()
        }
        m.memory.write(0x8004, value: 0x80)
        m.runUntilHalt()
        XCTAssertEqual(m.memory.read(0x8004), 0x81)
        XCTAssertEqual(m.r.b, 0x81)
    }

    func testEDMiscellaneous() {
        let m = TestMachine { a in
            a.ldA(0x01); a.db(0xED, 0x44)             // NEG -> FF, C
            a.db(0x47)                                // LD B,A
            a.ldHL(0x8000); a.ldA(0x12)
            a.db(0xED, 0x6F)                          // RLD: (HL)=34 -> 42, A=13
            a.halt()
        }
        m.memory.write(0x8000, value: 0x34)
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0xFF)
        XCTAssertEqual(m.r.a, 0x13)
        XCTAssertEqual(m.memory.read(0x8000), 0x42)
    }

    func testLDAIReflectsIFF2() {
        let m = TestMachine { a in a.ei(); a.db(0xED, 0x57); a.halt() }
        m.runUntilHalt()
        XCTAssertTrue(m.r.flag(Flag.pv))
    }

    // MARK: Block instructions

    func testLDIR() {
        let m = TestMachine { a in
            a.ldHL(0x8000); a.ldDE(0x9000); a.ldBC(5)
            a.db(0xED, 0xB0)                          // LDIR
            a.halt()
        }
        m.memory.load([1, 2, 3, 4, 5], at: 0x8000)
        m.runUntilHalt()
        XCTAssertEqual((0..<5).map { m.memory.read(0x9000 + $0) }, [1, 2, 3, 4, 5])
        XCTAssertEqual(m.r.bc, 0)
        XCTAssertFalse(m.r.flag(Flag.pv))
        XCTAssertEqual(m.r.hl, 0x8005)
    }

    func testCPIRFindsByte() {
        let m = TestMachine { a in
            a.ldHL(0x8000); a.ldBC(10); a.ldA(0x33)
            a.db(0xED, 0xB1)                          // CPIR
            a.halt()
        }
        m.memory.load([0x11, 0x22, 0x33, 0x44], at: 0x8000)
        m.runUntilHalt()
        XCTAssertTrue(m.r.flag(Flag.z))
        XCTAssertEqual(m.r.hl, 0x8003)
        XCTAssertEqual(m.r.bc, 7)
    }

    func testOTIRWritesPorts() {
        let m = TestMachine { a in
            a.ldHL(0x8000); a.ldB(3); a.ldC(0x11)
            a.db(0xED, 0xB3)                          // OTIR
            a.halt()
        }
        m.memory.load([0xAA, 0xBB, 0xCC], at: 0x8000)
        m.runUntilHalt()
        XCTAssertEqual(m.ports.writes.map(\.value), [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(m.ports.writes.map(\.port), [0x11, 0x11, 0x11])
        XCTAssertTrue(m.r.flag(Flag.z))
    }

    func testIOInstructions() {
        let m = TestMachine { a in
            a.inA(0x42)
            a.db(0x47)                                // LD B,A
            a.ldC(0x43); a.db(0xED, 0x50)             // IN D,(C)
            a.ldA(0x99); a.out(0x10)
            a.halt()
        }
        m.ports.inputs[0x42] = 0x5A
        m.ports.inputs[0x43] = 0x00
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0x5A)
        XCTAssertEqual(m.r.d, 0x00)
        XCTAssertTrue(m.r.flag(Flag.z))
        XCTAssertEqual(m.ports.writes.last?.port, 0x10)
        XCTAssertEqual(m.ports.writes.last?.value, 0x99)
    }

    // MARK: Interrupts

    func testIM1InterruptAfterEIDelay() {
        var asm = Asm(origin: 0)
        asm.ldSP(0x9000)
        asm.im1()
        asm.ei()
        asm.ldA(0x01)            // executes before the interrupt is taken
        asm.ldA(0x02)
        asm.halt()
        while asm.pc < 0x38 { asm.nop() }
        asm.ldB(0xAA)            // ISR
        asm.halt()
        let m = TestMachine(program: asm.assembled())
        m.cpu.step()             // LD SP
        m.cpu.step()             // IM 1
        m.cpu.step()             // EI
        m.cpu.irqLine = true
        m.cpu.step()             // LD A,1 (interrupt inhibited after EI)
        XCTAssertEqual(m.r.a, 0x01)
        XCTAssertNotEqual(m.r.pc, 0x0038)
        m.cpu.step()             // interrupt accepted
        XCTAssertEqual(m.r.pc, 0x0038)
        XCTAssertFalse(m.cpu.iff1)
        XCTAssertEqual(m.memory.read16(m.r.sp), 0x0008, "return address is the instruction after LD A,1")
    }

    func testHaltResumesAfterInterrupt() {
        var asm = Asm(origin: 0)
        asm.ldSP(0x9000)
        asm.im1()
        asm.ei()
        asm.halt()
        asm.ldB(0x55)            // 0x0006
        asm.halt()
        while asm.pc < 0x38 { asm.nop() }
        asm.ei()
        asm.ret()
        let m = TestMachine(program: asm.assembled())
        m.runUntilHalt()
        XCTAssertTrue(m.cpu.halted)
        let before = m.cpu.cycles
        m.cpu.run(until: before + 400)                  // stays halted, time advances
        XCTAssertTrue(m.cpu.halted)
        XCTAssertGreaterThanOrEqual(m.cpu.cycles, before + 400)
        m.cpu.irqLine = true
        m.cpu.step()
        m.cpu.irqLine = false
        XCTAssertFalse(m.cpu.halted)
        m.runUntilHalt()
        XCTAssertEqual(m.r.b, 0x55)
    }

    func testIM2Vector() {
        var asm = Asm(origin: 0)
        asm.ldSP(0x9000)
        asm.ldA(0x80); asm.db(0xED, 0x47)                // LD I,A
        asm.db(0xED, 0x5E)                               // IM 2
        asm.ei()
        asm.halt()
        let m = TestMachine(program: asm.assembled())
        m.memory.write(0x80FF, value: 0x34)              // vector table entry for bus FFh
        m.memory.write(0x8100, value: 0x12)
        m.memory.write(0x1234, value: 0x76)
        m.runUntilHalt()
        m.cpu.irqLine = true
        m.cpu.step()
        XCTAssertEqual(m.r.pc, 0x1234)
    }

    func testNMI() {
        let m = TestMachine { a in a.ldSP(0x9000); a.ei(); a.halt() }
        m.runUntilHalt()
        m.cpu.nmiPending = true
        m.cpu.step()
        XCTAssertEqual(m.r.pc, 0x0066)
        XCTAssertFalse(m.cpu.iff1)
        XCTAssertTrue(m.cpu.iff2)
    }

    func testDisabledInterruptsIgnored() {
        let m = TestMachine { a in a.di(); a.halt() }
        m.runUntilHalt()
        m.cpu.irqLine = true
        m.cpu.step()
        XCTAssertTrue(m.cpu.halted)
    }

    // MARK: Timing & diagnostics

    func testInstructionCycleCounts() {
        func cycles(_ bytes: [UInt8], setup: ((CPU) -> Void)? = nil) -> Int {
            let m = TestMachine(program: bytes)
            setup?(m.cpu)
            return m.cpu.step()
        }
        XCTAssertEqual(cycles([0x00]), 4)                           // NOP
        XCTAssertEqual(cycles([0x3E, 0x00]), 7)                     // LD A,n
        XCTAssertEqual(cycles([0x21, 0, 0]), 10)                    // LD HL,nn
        XCTAssertEqual(cycles([0xCD, 0, 0]), 17)                    // CALL
        XCTAssertEqual(cycles([0xDD, 0x7E, 0x00]), 19)              // LD A,(IX+d)
        XCTAssertEqual(cycles([0xDD, 0x36, 0x00, 0x00]), 19)        // LD (IX+d),n
        XCTAssertEqual(cycles([0xDD, 0x34, 0x00]), 23)              // INC (IX+d)
        XCTAssertEqual(cycles([0xDD, 0xCB, 0x00, 0x46]), 20)        // BIT 0,(IX+d)
        XCTAssertEqual(cycles([0xDD, 0xCB, 0x00, 0xC6]), 23)        // SET 0,(IX+d)
        XCTAssertEqual(cycles([0xCB, 0x46]), 12)                    // BIT 0,(HL)
        XCTAssertEqual(cycles([0xED, 0xB0]) { $0.registers.bc = 2 }, 21)  // LDIR repeating
        XCTAssertEqual(cycles([0xED, 0xB0]) { $0.registers.bc = 1 }, 16)  // LDIR last
        XCTAssertEqual(cycles([0x20, 0x00]) { $0.registers.f = 0 }, 12)   // JR NZ taken
        XCTAssertEqual(cycles([0x20, 0x00]) { $0.registers.f = Flag.z }, 7)
        XCTAssertEqual(cycles([0xC0]) { $0.registers.f = Flag.z }, 5)     // RET NZ not taken
        XCTAssertEqual(cycles([0xE3]), 19)                          // EX (SP),HL
    }

    func testRefreshRegisterIncrements() {
        let m = TestMachine(program: [0x00, 0x00, 0xDD, 0x00, 0xCB, 0x00, 0x76])
        m.cpu.registers.r = 0x7E
        m.runUntilHalt()
        // NOP, NOP, DD+NOP (2), CB+RLC B (2), HALT = 7 M1 cycles; bit 7 preserved.
        XCTAssertEqual(m.r.r, 0x05)
    }

    func testUndefinedEDOpcodeIsReported() {
        let m = TestMachine(program: [0xED, 0x00, 0x76])
        var reports: [CPUDiagnostic] = []
        m.cpu.diagnosticHandler = { reports.append($0) }
        XCTAssertEqual(m.cpu.step(), 8)
        XCTAssertEqual(reports, [.undefinedEDOpcode(opcode: 0x00, pc: 0x0000)])
        XCTAssertTrue(reports[0].description.contains("PC: 0x0000"))
    }

    func testCPUStateRoundTrip() throws {
        let m = TestMachine { a in a.ldBC(0x1234); a.ei(); a.halt() }
        m.runUntilHalt()
        let data = try JSONEncoder().encode(m.cpu.state)
        let decoded = try JSONDecoder().decode(CPUState.self, from: data)
        XCTAssertEqual(decoded, m.cpu.state)
    }

    // MARK: Disassembler

    func testDisassembler() {
        let bytes: [UInt8] = [0xDD, 0x36, 0xFE, 0x5A, 0xED, 0xB0, 0xCB, 0x7E, 0xC3, 0x34, 0x12, 0xFD, 0xCB, 0x02, 0xC6]
        let listing = Disassembler.disassemble(from: 0, count: 5) { bytes[Int($0) % bytes.count] }
        XCTAssertEqual(listing.map(\.text), ["LD (IX-$02),$5A", "LDIR", "BIT 7,(HL)", "JP $1234", "SET 0,(IY+$02)"])
        XCTAssertEqual(listing.map(\.length), [4, 2, 2, 3, 4])
    }
}
