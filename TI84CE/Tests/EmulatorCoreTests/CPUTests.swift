import XCTest
@testable import EmulatorCore

final class CPUTests: XCTestCase {

    // MARK: Loads and register pairs

    func testLoad24BitImmediateInADLMode() {
        let m = TestMachine([0x21, 0x56, 0x34, 0x12,         // ld hl,$123456
                             0x01, 0x03, 0x02, 0x01,         // ld bc,$010203
                             0x7C])                          // ld a,h
        m.step(3)
        XCTAssertEqual(m.r.hl, 0x123456)
        XCTAssertEqual(m.r.bc, 0x010203)
        XCTAssertEqual(m.r.a, 0x34)
        XCTAssertEqual(m.r.pc, TestMachine.origin + 9)
    }

    func testZ80ModeUses16BitRegistersAndMBASE() {
        // Z80 mode: immediates are 16-bit and memory addresses are {MBASE, addr16}.
        let m = TestMachine([0x21, 0x00, 0x20,               // ld hl,$2000
                             0x3E, 0x5A,                     // ld a,$5A
                             0x77], adl: false)              // ld (hl),a
        m.step(3)
        XCTAssertEqual(m.r.hl, 0x2000)
        XCTAssertEqual(m.peek(0xD02000), 0x5A, "store must land at MBASE:HL")
    }

    func testSixteenBitWritesZeroExtend() {
        // ld.sis de,($0010) in ADL mode reads a 16-bit value and clears DEU.
        let m = TestMachine([0x11, 0xFF, 0xFF, 0xFF,         // ld de,$FFFFFF
                             0x40, 0xED, 0x5B, 0x10, 0x00])  // ld.sis de,($0010)
        m.load([0x34, 0x12], at: 0xD00010)
        m.step(2)
        XCTAssertEqual(m.r.de, 0x001234)
    }

    func testEightBitWritesPreserveUpperByte() {
        let m = TestMachine([0x21, 0x56, 0x34, 0x12, 0x2E, 0xAA]) // ld hl,$123456 / ld l,$AA
        m.step(2)
        XCTAssertEqual(m.r.hl, 0x1234AA)
    }

    // MARK: Arithmetic and flags

    func testAddSetsOverflowHalfCarryAndSign() {
        let m = TestMachine([0x3E, 0x7F, 0x06, 0x01, 0x80]) // ld a,$7F / ld b,1 / add a,b
        m.step(3)
        XCTAssertEqual(m.r.a, 0x80)
        XCTAssertEqual(m.r.f & Flag.s, Flag.s)
        XCTAssertEqual(m.r.f & Flag.pv, Flag.pv, "signed overflow")
        XCTAssertEqual(m.r.f & Flag.h, Flag.h, "half carry")
        XCTAssertEqual(m.r.f & Flag.c, 0)
        XCTAssertEqual(m.r.f & Flag.n, 0)
    }

    func testSubCompareAndCarry() {
        let m = TestMachine([0x3E, 0x10, 0xFE, 0x20,         // ld a,$10 / cp $20
                             0xD6, 0x10])                    // sub $10
        m.step(2)
        XCTAssertEqual(m.r.a, 0x10, "cp must not modify A")
        XCTAssertEqual(m.r.f & Flag.c, Flag.c)
        XCTAssertEqual(m.r.f & Flag.n, Flag.n)
        m.step()
        XCTAssertEqual(m.r.a, 0)
        XCTAssertEqual(m.r.f & Flag.z, Flag.z)
    }

    func testIncDecPreserveCarry() {
        let m = TestMachine([0x37, 0x3E, 0xFF, 0x3C, 0x3D]) // scf / ld a,$FF / inc a / dec a
        m.step(3)
        XCTAssertEqual(m.r.a, 0)
        XCTAssertEqual(m.r.f & (Flag.z | Flag.c | Flag.h), Flag.z | Flag.c | Flag.h)
        m.step()
        XCTAssertEqual(m.r.a, 0xFF)
        XCTAssertEqual(m.r.f & (Flag.c | Flag.n | Flag.s), Flag.c | Flag.n | Flag.s)
    }

    func testDAAAfterBCDAddition() {
        let m = TestMachine([0x3E, 0x19, 0xC6, 0x28, 0x27]) // ld a,$19 / add a,$28 / daa
        m.step(3)
        XCTAssertEqual(m.r.a, 0x47)
    }

    func test24BitAddAndCarryOut() {
        let m = TestMachine([0x21, 0xFF, 0xFF, 0xFF,         // ld hl,$FFFFFF
                             0x01, 0x01, 0x00, 0x00,         // ld bc,$000001
                             0x09])                          // add hl,bc
        m.step(3)
        XCTAssertEqual(m.r.hl, 0)
        XCTAssertEqual(m.r.f & Flag.c, Flag.c)
    }

    func test24BitSbcSetsZeroAndSign() {
        let m = TestMachine([0x21, 0x00, 0x00, 0x80,         // ld hl,$800000
                             0x11, 0x01, 0x00, 0x00,         // ld de,1
                             0xB7,                           // or a (clear carry)
                             0xED, 0x52])                    // sbc hl,de
        m.step(4)
        XCTAssertEqual(m.r.hl, 0x7FFFFF)
        XCTAssertEqual(m.r.f & Flag.pv, Flag.pv, "24-bit signed overflow")
        XCTAssertEqual(m.r.f & Flag.s, 0)
    }

    func testMLTAndTST() {
        let m = TestMachine([0x01, 0x0C, 0x0B, 0x00,         // ld bc,$000B0C
                             0xED, 0x4C,                     // mlt bc
                             0x3E, 0xF0,                     // ld a,$F0
                             0xED, 0x64, 0x0F])              // tst a,$0F
        m.step(2)
        XCTAssertEqual(m.r.bc, 11 * 12)
        m.step(2)
        XCTAssertEqual(m.r.a, 0xF0, "TST must not modify A")
        XCTAssertEqual(m.r.f & Flag.z, Flag.z)
    }

    // MARK: Stack, calls and branches

    func testPushPopUsesSPLInADLMode() {
        let m = TestMachine([0x21, 0x56, 0x34, 0x12, 0xE5, 0xD1]) // ld hl / push hl / pop de
        m.step(2)
        XCTAssertEqual(m.r.spl, 0xD0FFFD, "three bytes pushed")
        XCTAssertEqual(m.peek(0xD0FFFD), 0x56)
        XCTAssertEqual(m.peek(0xD0FFFF), 0x12)
        m.step()
        XCTAssertEqual(m.r.de, 0x123456)
        XCTAssertEqual(m.r.spl, 0xD10000)
    }

    func testPushPopUsesSPSInZ80Mode() {
        let m = TestMachine([0x21, 0x34, 0x12, 0xE5], adl: false) // ld hl,$1234 / push hl
        m.step(2)
        XCTAssertEqual(m.r.sps, 0xEFFE)
        XCTAssertEqual(m.peek(0xD0EFFE), 0x34, "SPS is addressed through MBASE")
        XCTAssertEqual(m.r.spl, 0xD10000, "SPL untouched in Z80 mode")
    }

    func testCallAndReturn() {
        let o = TestMachine.origin
        let m = TestMachine([0xCD, 0x10, 0x01, 0xD0,         // call $D00110
                             0x76])                          // halt
        m.load([0x3E, 0x42, 0xC9], at: o + 0x10)             // ld a,$42 / ret
        m.step()
        XCTAssertEqual(m.r.pc, o + 0x10)
        XCTAssertEqual(m.r.spl, 0xD0FFFD)
        m.step(2)
        XCTAssertEqual(m.r.pc, o + 4)
        XCTAssertEqual(m.r.a, 0x42)
        XCTAssertEqual(m.r.spl, 0xD10000)
    }

    func testConditionalBranchesAndDJNZ() {
        let o = TestMachine.origin
        let m = TestMachine([0x06, 0x05,                     // ld b,5
                             0xAF,                           // xor a
                             0x3C,                           // loop: inc a
                             0x10, 0xFD,                     // djnz loop
                             0xFE, 0x05,                     // cp 5
                             0x28, 0x02,                     // jr z,+2
                             0x3E, 0xEE,                     // ld a,$EE (skipped)
                             0x76])                          // halt
        m.run(until: o + 12)
        XCTAssertEqual(m.r.a, 5)
        XCTAssertEqual(m.r.b, 0)
    }

    func testMixedModeCallFromZ80IntoADLAndBack() {
        // Z80-mode code at D0:0100 calls an ADL routine with CALL.LIL, which returns
        // with RET.L; the mode byte on SPL restores Z80 mode.
        let m = TestMachine([0x5B, 0xCD, 0x00, 0x02, 0xD0,   // call.lil $D00200
                             0x76], adl: false)              // halt
        m.load([0x21, 0x56, 0x34, 0x12,                      // ld hl,$123456
                0x49, 0xC9], at: 0xD00200)                   // ret.l
        m.step()
        XCTAssertTrue(m.cpu.adl, "CALL.LIL switches to ADL mode")
        XCTAssertEqual(m.r.pc, 0xD00200)
        m.step(2)
        XCTAssertFalse(m.cpu.adl, "RET.L restores Z80 mode")
        XCTAssertEqual(m.r.pc, 0x0105)
        XCTAssertEqual(m.r.hl, 0x123456)
        XCTAssertEqual(m.r.spl, 0xD10000, "SPL balanced")
    }

    func testJPLILFromZ80ModeEntersADL() {
        let m = TestMachine([0x5B, 0xC3, 0x00, 0x02, 0xD0], adl: false) // jp.lil $D00200
        m.step()
        XCTAssertTrue(m.cpu.adl)
        XCTAssertEqual(m.r.pc, 0xD00200)
    }

    // MARK: Prefixes

    func testIndexedAddressingAndEZ80IndexLoads() {
        let m = TestMachine([0xDD, 0x21, 0x00, 0x30, 0xD0,   // ld ix,$D03000
                             0xDD, 0x36, 0x05, 0x99,         // ld (ix+5),$99
                             0xDD, 0x7E, 0x05,               // ld a,(ix+5)
                             0xDD, 0x27, 0xFE,               // ld hl,(ix-2)
                             0xED, 0x22, 0x10])              // lea hl,ix+16
        m.load([0x11, 0x22, 0x33], at: 0xD02FFE)
        m.step(3)
        XCTAssertEqual(m.r.a, 0x99)
        XCTAssertEqual(m.peek(0xD03005), 0x99)
        m.step()
        XCTAssertEqual(m.r.hl, 0x332211, "eZ80 LD HL,(IX+d) loads 24 bits")
        m.step()
        XCTAssertEqual(m.r.hl, 0xD03010)
    }

    func testIXHalvesViaPrefix() {
        let m = TestMachine([0xDD, 0x21, 0x34, 0x12, 0x00,   // ld ix,$001234
                             0xDD, 0x7C])                    // ld a,ixh
        m.step(2)
        XCTAssertEqual(m.r.a, 0x12)
    }

    func testCBBitSetResAndRotate() {
        let m = TestMachine([0x21, 0x00, 0x30, 0xD0,         // ld hl,$D03000
                             0xCB, 0xFE,                     // set 7,(hl)
                             0xCB, 0x7E,                     // bit 7,(hl)
                             0xCB, 0x06,                     // rlc (hl)
                             0xCB, 0xBE])                    // res 7,(hl)
        m.step(3)
        XCTAssertEqual(m.peek(0xD03000), 0x80)
        XCTAssertEqual(m.r.f & Flag.z, 0)
        m.step()
        XCTAssertEqual(m.peek(0xD03000), 0x01)
        XCTAssertEqual(m.r.f & Flag.c, Flag.c)
        m.step()
        XCTAssertEqual(m.peek(0xD03000), 0x01)
    }

    func testIndexedCBWithDisplacement() {
        let m = TestMachine([0xFD, 0x21, 0x00, 0x30, 0xD0,   // ld iy,$D03000
                             0xFD, 0xCB, 0x02, 0xC6])        // set 0,(iy+2)
        m.step(2)
        XCTAssertEqual(m.peek(0xD03002), 0x01)
    }

    func testLDIRCopies24BitCount() {
        let m = TestMachine([0x21, 0x00, 0x30, 0xD0,         // ld hl,$D03000
                             0x11, 0x00, 0x40, 0xD0,         // ld de,$D04000
                             0x01, 0x04, 0x00, 0x00,         // ld bc,4
                             0xED, 0xB0,                     // ldir
                             0x76])
        m.load([1, 2, 3, 4], at: 0xD03000)
        m.run(until: TestMachine.origin + 14)
        XCTAssertEqual((0..<4).map { m.peek(0xD04000 + $0) }, [1, 2, 3, 4])
        XCTAssertEqual(m.r.bc, 0)
        XCTAssertEqual(m.r.f & Flag.pv, 0)
    }

    func testExchangeInstructions() {
        let m = TestMachine([0x11, 0x01, 0x00, 0x00, 0x21, 0x02, 0x00, 0x00, // ld de,1 / ld hl,2
                             0xEB,                                           // ex de,hl
                             0xD9,                                           // exx
                             0x08])                                          // ex af,af'
        m.step(3)
        XCTAssertEqual(m.r.de, 2)
        XCTAssertEqual(m.r.hl, 1)
        m.step()
        XCTAssertEqual(m.r.hl, 0)
        XCTAssertEqual(m.r.hl_, 1)
    }

    func testMBASEInstructions() {
        let m = TestMachine([0x3E, 0xD1, 0xED, 0x6D, 0xAF, 0xED, 0x6E]) // ld a / ld mb,a / xor a / ld a,mb
        m.step(4)
        XCTAssertEqual(m.r.mbase, 0xD1)
        XCTAssertEqual(m.r.a, 0xD1)
    }

    func testIN0AndOUT0ReachControlPorts() {
        let m = TestMachine([0x3E, 0x03, 0xED, 0x39, 0x01,   // ld a,3 / out0 ($01),a
                             0xED, 0x38, 0x01])              // in0 a,($01)
        m.step(3)
        XCTAssertEqual(m.r.a, 3)
        XCTAssertEqual(m.emu.scheduler.cpuHz, 48_000_000)
    }

    func testRRegisterCountsOpcodeFetches() {
        let m = TestMachine([0x00, 0x00, 0xDD, 0x21, 0, 0, 0])
        let before = m.r.r
        m.step(3)
        XCTAssertEqual(m.r.r &- before, 4, "prefix bytes are M1 cycles too")
    }

    // MARK: Interrupts

    func testIM1InterruptPushesPCAndVectors() {
        let o = TestMachine.origin
        let m = TestMachine([0xED, 0x56,                     // im 1
                             0xFB,                           // ei
                             0x00,                           // nop (EI delay slot)
                             0x00, 0x00, 0x76])
        m.step(2)
        m.cpu.irq = true
        m.step()                                             // nop executes: EI delay
        XCTAssertEqual(m.r.pc, o + 4)
        m.step()                                             // interrupt accepted
        XCTAssertEqual(m.r.pc, 0x38)
        XCTAssertFalse(m.cpu.ief1)
        XCTAssertEqual(m.r.spl, 0xD0FFFD)
        XCTAssertEqual(m.peek(0xD0FFFD), UInt8((o + 4) & 0xFF))
    }

    func testDisabledInterruptsAreIgnored() {
        let m = TestMachine([0xF3, 0x00, 0x00])              // di / nop / nop
        m.cpu.irq = true
        m.step(3)
        XCTAssertEqual(m.r.pc, TestMachine.origin + 3)
    }

    func testHaltWaitsForInterrupt() {
        let m = TestMachine([0xED, 0x56, 0xFB, 0x76, 0x00])  // im 1 / ei / halt
        m.step(3)
        XCTAssertTrue(m.cpu.halted)
        m.step(5)
        XCTAssertTrue(m.cpu.halted, "stays halted without an interrupt")
        m.cpu.irq = true
        m.step()
        XCTAssertFalse(m.cpu.halted)
        XCTAssertEqual(m.r.pc, 0x38)
    }

    func testRETIRestoresInterruptEnable() {
        let m = TestMachine([0xED, 0x4D])                    // reti
        m.load([0x00, 0x20, 0xD0], at: 0xD0FFFD)
        var r = m.r; r.spl = 0xD0FFFD; m.r = r
        m.cpu.ief2 = true
        m.step()
        XCTAssertTrue(m.cpu.ief1)
        XCTAssertEqual(m.r.pc, 0xD02000)
    }

    // MARK: Diagnostics

    func testUnsupportedOpcodeIsReported() {
        let m = TestMachine([0xED, 0x77])
        var reported: String?
        m.cpu.onUnsupported = { reported = $0 }
        m.step()
        XCTAssertEqual(m.cpu.unsupportedCount, 1)
        XCTAssertTrue(reported?.contains("Unsupported opcode: 0xED 0x77") ?? false)
        XCTAssertTrue(reported?.contains("PC: 0xD00100") ?? false)
    }

    func testBreakpointStopsExecution() {
        let o = TestMachine.origin
        let m = TestMachine([0x00, 0x00, 0x00, 0x00, 0x18, 0xFA]) // nops / jr -6
        m.cpu.breakpoints = [o + 3]
        m.emu.run(cycles: 10_000)
        XCTAssertTrue(m.cpu.breakpointHit)
        XCTAssertEqual(m.r.pc, o + 3)
    }

    func testDisassembler() {
        let bytes: [UInt8] = [0x5B, 0xC3, 0x4F, 0x0E, 0x00, 0xED, 0x39, 0x01, 0xDD, 0x7E, 0xFE]
        let d = Disassembler(read: { bytes[Int($0)] })
        let a = d.decode(at: 0, adl: false)
        XCTAssertEqual(a.text, "jp.lil $000E4F")
        XCTAssertEqual(a.length, 5)
        XCTAssertEqual(d.decode(at: 5, adl: true).text, "out0 ($01),a")
        XCTAssertEqual(d.decode(at: 8, adl: true).text, "ld a,(ix-2)")
    }
}
