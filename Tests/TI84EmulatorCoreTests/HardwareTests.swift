import XCTest
@testable import TI84EmulatorCore

final class HardwareTests: XCTestCase {

    private func idleEmulator() throws -> Emulator {
        var rom = SyntheticROM()
        rom.place(page: 0x3F, logicalBank: 2) { a in a.di(); a.halt() }
        return Emulator(rom: try rom.image())
    }

    // MARK: LCD

    func testLCDCommandsAndStatus() throws {
        let emu = try idleEmulator()
        let lcd = emu.io
        XCTAssertEqual(lcd.read(port: 0x10) & 0x20, 0, "display starts off")
        lcd.write(port: 0x10, value: 0x03)
        lcd.write(port: 0x10, value: 0x01)
        lcd.write(port: 0x10, value: 0x05)
        XCTAssertEqual(lcd.read(port: 0x10) & 0x63, 0x61)   // on, 8-bit, row-increment
        lcd.write(port: 0x10, value: 0xC0 + 0x2A)
        XCTAssertEqual(emu.lcd.contrast, 0x2A)
        lcd.write(port: 0x12, value: 0x02)                   // mirror port, display off
        XCTAssertFalse(emu.lcd.displayOn)
    }

    func testLCDEightBitWriteWithAutoIncrement() throws {
        let emu = try idleEmulator()
        let io = emu.io
        for c: UInt8 in [0x01, 0x05, 0x80, 0x20] { io.write(port: 0x10, value: c) }  // row++ mode
        for _ in 0..<3 { io.write(port: 0x11, value: 0x81) }
        XCTAssertTrue(emu.lcd.pixel(x: 0, y: 0))
        XCTAssertTrue(emu.lcd.pixel(x: 7, y: 2))
        XCTAssertFalse(emu.lcd.pixel(x: 1, y: 1))
        XCTAssertFalse(emu.lcd.pixel(x: 0, y: 3))
        XCTAssertEqual(emu.lcd.row, 3)
    }

    func testLCDDummyRead() throws {
        let emu = try idleEmulator()
        let io = emu.io
        for c: UInt8 in [0x01, 0x07, 0x85, 0x22] { io.write(port: 0x10, value: c) }
        io.write(port: 0x11, value: 0x5A)
        io.write(port: 0x11, value: 0xC3)
        for c: UInt8 in [0x85, 0x22] { io.write(port: 0x10, value: c) }
        _ = io.read(port: 0x11)                               // dummy read
        XCTAssertEqual(io.read(port: 0x11), 0x5A)
        XCTAssertEqual(io.read(port: 0x11), 0xC3)
    }

    func testLCDSixBitMode() throws {
        let emu = try idleEmulator()
        let io = emu.io
        for c: UInt8 in [0x00, 0x07, 0x80, 0x21] { io.write(port: 0x10, value: c) }  // 6-bit, column 1
        io.write(port: 0x11, value: 0x3F)
        XCTAssertEqual((0..<16).map { emu.lcd.pixel(x: $0, y: 0) },
                       (0..<16).map { (6...11).contains($0) })
        XCTAssertEqual(emu.lcd.column, 2)
    }

    func testLCDRowShiftAndFrame() throws {
        let emu = try idleEmulator()
        let io = emu.io
        for c: UInt8 in [0x03, 0x01, 0x07, 0x80, 0x20] { io.write(port: 0x10, value: c) }
        io.write(port: 0x11, value: 0x80)                    // pixel (0,0)
        io.write(port: 0x10, value: 0x41)                    // Z address 1: memory row 1 at top
        XCTAssertFalse(emu.lcd.pixel(x: 0, y: 0))
        XCTAssertTrue(emu.lcd.pixel(x: 0, y: 63))
        emu.run(seconds: 0.05)
        XCTAssertTrue(emu.frame.isDisplayOn)
        XCTAssertEqual(emu.frame[0, 63], 255)
        XCTAssertEqual(emu.frame.pixels.filter { $0 > 0 }.count, 1)
    }

    func testLCDFramesOnlyPublishOnChange() throws {
        let emu = try idleEmulator()
        var frames = 0
        emu.onFrame = { _ in frames += 1 }
        emu.run(seconds: 0.5)
        XCTAssertEqual(frames, 0)
        emu.io.write(port: 0x10, value: 0x03)
        emu.run(seconds: 0.5)
        XCTAssertEqual(frames, 1)
    }

    // MARK: Keyboard

    func testKeyboardMatrixScan() {
        let keyboard = KeyboardMatrix()
        keyboard.setKey(.enter, pressed: true)      // group 1 bit 0
        keyboard.setKey(.up, pressed: true)         // group 0 bit 3
        keyboard.write(port: 0x01, value: 0xFD)
        XCTAssertEqual(keyboard.read(port: 0x01), 0xFE)
        keyboard.write(port: 0x01, value: 0xFE)
        XCTAssertEqual(keyboard.read(port: 0x01), 0xF7)
        keyboard.write(port: 0x01, value: 0xFC)     // both groups
        XCTAssertEqual(keyboard.read(port: 0x01), 0xF6)
        keyboard.write(port: 0x01, value: 0xFF)     // no group selected
        XCTAssertEqual(keyboard.read(port: 0x01), 0xFF)
        keyboard.setKey(.enter, pressed: false)
        keyboard.write(port: 0x01, value: 0xFD)
        XCTAssertEqual(keyboard.read(port: 0x01), 0xFF)
    }

    func testKeyboardGhosting() {
        let keyboard = KeyboardMatrix()
        keyboard.setKey(.down, pressed: true)       // (0,0)
        keyboard.setKey(.left, pressed: true)       // (0,1)
        keyboard.setKey(.enter, pressed: true)      // (1,0)
        keyboard.write(port: 0x01, value: 0xFD)     // group 1 only
        XCTAssertEqual(keyboard.read(port: 0x01), 0xFC, "ghost key appears at (1,1)")
    }

    func testEveryKeyHasUniqueMatrixPosition() {
        let positions = Key.allCases.compactMap { $0.matrixPosition.map { $0.group * 8 + $0.bit } }
        XCTAssertEqual(positions.count, Key.allCases.count - 1)
        XCTAssertEqual(Set(positions).count, positions.count)
        XCTAssertEqual(Key.enter.scanCode, 0x09)
        XCTAssertEqual(Key.delete.scanCode, 0x38)
    }

    func testKeyPressReachesROMThroughMatrix() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.1)
        XCTAssertEqual(emu.memory.peek(SyntheticOS.keyState), 0xFF)
        emu.setKey(.enter, pressed: true)
        emu.run(seconds: 0.05)
        XCTAssertEqual(emu.memory.peek(SyntheticOS.keyState), 0xFE)
        emu.setKey(.enter, pressed: false)
        emu.run(seconds: 0.1)
        XCTAssertEqual(emu.memory.peek(SyntheticOS.keyState), 0xFF)
    }

    func testQuickTapIsHeldLongEnoughToBeSeen() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.1)
        emu.setKey(.clear, pressed: true)
        emu.setKey(.clear, pressed: false)           // released immediately
        XCTAssertTrue(emu.keyboard.isPressed(.clear))
        emu.run(seconds: 0.03)
        XCTAssertEqual(emu.memory.peek(SyntheticOS.keyState), 0xBF, "CLEAR = group 1 bit 6")
        emu.run(seconds: 0.1)
        XCTAssertFalse(emu.keyboard.isPressed(.clear))
    }

    func testOnKeyInterrupt() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.1)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x08, 0x08, "ON not pressed")
        emu.setKey(.on, pressed: true)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x08, 0x00)
        emu.run(seconds: 0.01)
        XCTAssertEqual(emu.memory.peek(SyntheticOS.onFlag), 1)
    }

    // MARK: Timers & interrupts

    func testHardwareTimerInterruptRate() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 1.0)
        let count = Int(emu.memory.peek(SyntheticOS.counter)) | Int(emu.memory.peek(SyntheticOS.counter + 1)) << 8
        // Port 04h = 06h selects the 9277 µs period: ~107.8 interrupts/s.
        XCTAssertEqual(Double(count), 1_000_000 / 9277, accuracy: 2)
        XCTAssertEqual(emu.cpu.interruptMode, 1)
    }

    func testTimerRateIsIndependentOfCPUSpeed() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.01)
        emu.io.write(port: 0x20, value: 0x01)
        XCTAssertEqual(emu.clock.speed, .mhz15)
        let cyclesBefore = emu.cpu.cycles
        emu.run(seconds: 1.0)
        let count = Int(emu.memory.peek(SyntheticOS.counter)) | Int(emu.memory.peek(SyntheticOS.counter + 1)) << 8
        XCTAssertEqual(Double(count), 1_000_000 / 9277, accuracy: 3)
        XCTAssertEqual(Double(emu.cpu.cycles - cyclesBefore), 15_000_000, accuracy: 100)
    }

    func testTimerFrequencySelection() throws {
        let emu = try idleEmulator()
        emu.io.write(port: 0x03, value: 0x02)            // timer 1 only
        emu.io.write(port: 0x04, value: 0x00)            // fastest: 1953 µs
        var fired = 0
        for _ in 0..<1000 {
            emu.run(seconds: 0.001)
            if emu.interrupts.pending.contains(.timer1) {
                fired += 1
                emu.io.write(port: 0x03, value: 0x00)    // acknowledge
                emu.io.write(port: 0x03, value: 0x02)
            }
        }
        XCTAssertEqual(Double(fired), 1_000_000 / 1953, accuracy: 3)
    }

    func testInterruptMaskAndStatus() throws {
        let emu = try idleEmulator()
        emu.io.write(port: 0x03, value: 0x00)            // everything disabled
        emu.run(seconds: 0.05)
        XCTAssertTrue(emu.interrupts.pending.isEmpty)
        XCTAssertFalse(emu.cpu.irqLine)
        emu.io.write(port: 0x03, value: 0x06)
        emu.run(seconds: 0.02)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x06, 0x06)
        XCTAssertTrue(emu.cpu.irqLine)
        emu.io.write(port: 0x02, value: 0x04)            // ack timer 1 only (84+ port 02h)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x06, 0x04)
        emu.io.write(port: 0x03, value: 0x00)
        XCTAssertFalse(emu.cpu.irqLine)
    }

    func testCrystalTimerExpiry() throws {
        let emu = try idleEmulator()
        emu.io.write(port: 0x30, value: 0x44)            // 32768 Hz
        emu.io.write(port: 0x31, value: 0x02)            // no loop, interrupt
        emu.io.write(port: 0x32, value: 64)              // 64 ticks ≈ 1.95 ms
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x20, 0)
        emu.run(seconds: 0.0015)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x20, 0)
        emu.run(seconds: 0.001)
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x20, 0x20)
        XCTAssertTrue(emu.interrupts.pending.contains(.crystal1))
        emu.io.write(port: 0x31, value: 0x00)            // writing the mode acknowledges
        XCTAssertEqual(emu.io.read(port: 0x04) & 0x20, 0)
        XCTAssertFalse(emu.interrupts.pending.contains(.crystal1))
    }

    func testCrystalTimerCountsDown() throws {
        let emu = try idleEmulator()
        emu.io.write(port: 0x33, value: 0x45)            // 2048 Hz
        emu.io.write(port: 0x34, value: 0x00)
        emu.io.write(port: 0x35, value: 200)
        emu.run(seconds: 50.0 / 2048)
        XCTAssertEqual(Double(emu.io.read(port: 0x35)), 150, accuracy: 2)
    }

    // MARK: System ports

    func testStatusAndIdentificationPorts() throws {
        let emu = try idleEmulator()
        let status = emu.io.read(port: 0x02)
        XCTAssertEqual(status & 0xE1, 0xE1, "TI-84 Plus, batteries good")
        XCTAssertEqual(status & 0x04, 0, "Flash locked")
        XCTAssertEqual(emu.io.read(port: 0x15), 0x45)
        XCTAssertEqual(emu.io.read(port: 0x4C), 0x22, "no USB cable")
        XCTAssertEqual(emu.io.read(port: 0x21), 0x00)
        emu.io.write(port: 0x21, value: 0x01)
        XCTAssertEqual(emu.io.read(port: 0x21), 0x00, "protected while Flash is locked")
    }

    func testMD5Accelerator() throws {
        let emu = try idleEmulator()
        func load(_ port: UInt8, _ value: UInt32) {
            for i in 0..<4 { emu.io.write(port: port, value: UInt8(truncatingIfNeeded: value >> UInt32(i * 8))) }
        }
        let a: UInt32 = 0x67452301, b: UInt32 = 0xEFCDAB89, c: UInt32 = 0x98BADCFE, d: UInt32 = 0x10325476
        let x: UInt32 = 0x80, t: UInt32 = 0xD76AA478
        load(0x18, a); load(0x19, b); load(0x1A, c); load(0x1B, d); load(0x1C, x); load(0x1D, t)
        emu.io.write(port: 0x1E, value: 7)
        emu.io.write(port: 0x1F, value: 0)
        let f = (b & c) | (~b & d)
        let sum = f &+ a &+ x &+ t
        let expected = ((sum << 7) | (sum >> 25)) &+ b
        var result: UInt32 = 0
        for i in 0..<4 {
            let byte = UInt32(emu.io.read(port: UInt8(0x1C + i)))
            result |= byte << UInt32(i * 8)
        }
        XCTAssertEqual(result, expected)
    }

    func testRealTimeClock() throws {
        let emu = try idleEmulator()
        for (i, byte) in [UInt8(0x10), 0x20, 0x30, 0x40].enumerated() { emu.io.write(port: UInt8(0x41 + i), value: byte) }
        emu.io.write(port: 0x40, value: 0x01)
        emu.io.write(port: 0x40, value: 0x03)            // load + run
        emu.run(seconds: 2.5)
        XCTAssertEqual(emu.io.read(port: 0x45), 0x12)
        XCTAssertEqual(emu.io.read(port: 0x48), 0x40)
    }

    func testLinkPortLines() throws {
        final class Peer: LinkPeer {
            var linesPulledLow: UInt8 = 0
            var seen: UInt8 = 0
            func calculatorLinesChanged(_ pulledLow: UInt8) { seen = pulledLow }
        }
        let emu = try idleEmulator()
        XCTAssertEqual(emu.io.read(port: 0x00), 0x03, "idle lines float high")
        emu.io.write(port: 0x00, value: 0x01)
        XCTAssertEqual(emu.io.read(port: 0x00), 0x12)
        let peer = Peer()
        emu.link.peer = peer
        emu.io.write(port: 0x00, value: 0x02)
        XCTAssertEqual(peer.seen, 0x02)
        peer.linesPulledLow = 0x01
        XCTAssertEqual(emu.io.read(port: 0x00) & 0x03, 0x00)
    }

    // MARK: Emulator-level behaviour

    func testDeterministicExecution() throws {
        let a = try SyntheticOS.emulator()
        let b = try SyntheticOS.emulator()
        for emu in [a, b] {
            emu.run(seconds: 0.2)
            emu.setKey(.five, pressed: true)
            emu.run(seconds: 0.1)
            emu.setKey(.five, pressed: false)
            emu.run(seconds: 0.2)
        }
        XCTAssertEqual(a.cpu.state, b.cpu.state)
        XCTAssertEqual(a.ram.bytes, b.ram.bytes)
    }

    func testSaveStateRoundTripResumesExactly() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.3)
        let saved = try EmulatorStateCoder.encode(emu.saveState())
        emu.run(seconds: 0.4)
        let expectedCPU = emu.cpu.state
        let expectedRAM = emu.ram.bytes

        let restored = try SyntheticOS.emulator()
        try restored.loadState(EmulatorStateCoder.decode(saved), advanceClock: false)
        restored.run(seconds: 0.4)
        XCTAssertEqual(restored.cpu.state, expectedCPU)
        XCTAssertEqual(restored.ram.bytes, expectedRAM)
        XCTAssertEqual(restored.frame.pixels, emu.frame.pixels)
    }

    func testSaveStateRejectsDifferentROM() throws {
        let emu = try SyntheticOS.emulator()
        let state = emu.saveState()
        let other = try idleEmulator()
        XCTAssertThrowsError(try other.loadState(state))
    }

    func testPersistentStorage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ti84-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = PersistentStorage(directory: dir)

        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.2)
        emu.ram[physical: 0x2000] = 0x5A
        try storage.autosave(emu)
        try storage.saveRAM(emu)

        let fresh = try SyntheticOS.emulator()
        XCTAssertTrue(try storage.restoreAutosave(into: fresh))
        XCTAssertEqual(fresh.ram[physical: 0x2000], 0x5A)
        XCTAssertEqual(fresh.cpu.state, emu.cpu.state)

        let other = try SyntheticOS.emulator()
        XCTAssertTrue(try storage.loadRAM(into: other))
        XCTAssertEqual(other.ram[physical: 0x2000], 0x5A)

        try storage.resetRAM(other)
        XCTAssertEqual(other.ram[physical: 0x2000], 0x00)
        XCTAssertFalse(try storage.restoreAutosave(into: try SyntheticOS.emulator()))
    }

    func testBreakpointPausesExecution() throws {
        let emu = try SyntheticOS.emulator()
        emu.debugger.addBreakpoint(0x0038)
        let result = emu.run(seconds: 1)
        XCTAssertEqual(result, .breakpoint(0x0038))
        XCTAssertEqual(emu.cpu.registers.pc, 0x0038)
        // Resuming continues past the breakpoint and stops at the next hit.
        XCTAssertEqual(emu.run(seconds: 1), .breakpoint(0x0038))
        emu.debugger.clearBreakpoints()
        XCTAssertEqual(emu.run(seconds: 0.1), .completed)
    }

    func testDebugSnapshot() throws {
        let emu = try SyntheticOS.emulator()
        emu.run(seconds: 0.05)
        let snapshot = emu.debugSnapshot()
        XCTAssertEqual(snapshot.interruptMode, 1)
        XCTAssertTrue(snapshot.summary.contains("PC="))
        XCTAssertEqual(snapshot.banks.first, .flash(0))
        XCTAssertFalse(snapshot.upcoming.isEmpty)
    }

    func testRunnerExecutesInRealTimeOnItsOwnThread() throws {
        let runner = EmulatorRunner(emulator: try SyntheticOS.emulator())
        let frameSeen = expectation(description: "frame")
        frameSeen.assertForOverFulfill = false
        runner.onFrame = { frame in if frame.isDisplayOn { frameSeen.fulfill() } }
        runner.start()
        wait(for: [frameSeen], timeout: 2)
        runner.setKey(.enter, pressed: true)
        Thread.sleep(forTimeInterval: 0.3)
        let key = runner.sync { $0.memory.peek(SyntheticOS.keyState) }
        XCTAssertEqual(key, 0xFE)
        let seconds = runner.sync { $0.emulatedSeconds }
        XCTAssertGreaterThan(seconds, 0.2)
        XCTAssertLessThan(seconds, 2.0, "paced to real time")
        runner.stop()
        XCTAssertEqual(runner.status, .stopped)
    }
}

final class LCDRendererTests: XCTestCase {
    func testContrastAndDisplayOff() {
        var frame = LCDFrame()
        frame.pixels[0] = 255
        frame.isDisplayOn = true
        frame.contrast = 40
        let renderer = LCDRenderer()
        let on = renderer.rgba(frame)
        XCTAssertLessThan(on[0], on[4], "set pixel is darker than a clear one")
        frame.contrast = 10
        let faint = renderer.rgba(frame)
        XCTAssertGreaterThan(faint[0], on[0], "lower contrast washes pixels out")
        frame.isDisplayOn = false
        let off = renderer.rgba(frame)
        XCTAssertEqual(off[0], off[4], "nothing visible with the display off")
        XCTAssertEqual(renderer.ppm(frame, scale: 2).count, "P6\n192 128\n255\n".utf8.count + 192 * 128 * 3)
    }

    func testPersistenceBlendsFrames() throws {
        var config = EmulatorConfiguration()
        config.lcdPersistence = 0.5
        let emu = Emulator(rom: try SyntheticOS.rom().image(), configuration: config)
        emu.run(seconds: 0.02)
        // Partially faded in right after the OS draws, then converges.
        emu.run(seconds: 0.5)
        XCTAssertGreaterThan(emu.frame[0, 0], 250)
        XCTAssertEqual(emu.frame[10, 30], 0)
    }
}
