import XCTest
@testable import EmulatorCore

final class HardwareTests: XCTestCase {

    // MARK: Interrupt controller

    func testInterruptLatchAcknowledgeAndMask() {
        let emu = Emulator()
        let ic = emu.interrupts
        ic.write(0x0C, value: 0x10)                  // OS timer latched
        ic.write(0x04, value: 0x10)                  // enable OS timer
        ic.pulse(InterruptSource.osTimer)
        XCTAssertTrue(emu.cpu.irq, "latched pulse stays pending")
        XCTAssertEqual(ic.read(0x14), 0x10)          // masked status
        ic.write(0x08, value: 0x10)                  // acknowledge
        XCTAssertFalse(emu.cpu.irq)

        ic.write(0x04, value: 0x01)                  // enable ON key (level)
        ic.set(InterruptSource.on, true)
        XCTAssertTrue(emu.cpu.irq)
        ic.set(InterruptSource.on, false)
        XCTAssertFalse(emu.cpu.irq, "unlatched source follows its line")
    }

    func testDisabledSourceDoesNotRaiseIRQ() {
        let emu = Emulator()
        emu.interrupts.set(InterruptSource.keypad, true)
        XCTAssertFalse(emu.cpu.irq)
        XCTAssertEqual(emu.interrupts.read(0x01) & 0x04, 0x04, "raw status still visible")
    }

    // MARK: Timers

    func testGPTMatchInterruptFiresAtExactTime() {
        let emu = Emulator()
        emu.scheduler.setCPUClock(hz: 48_000_000)
        emu.interrupts.write(0x0C, value: 0x08)      // latch timer 3
        emu.interrupts.write(0x04, value: 0x08)      // enable timer 3
        let t = emu.timers
        // Timer 3: count down from 1000 on the CPU clock, match1 at 0.
        for (o, v) in [(0x20, 0xE8), (0x21, 0x03), (0x24, 0xE8), (0x25, 0x03)] { t.write(UInt16(o), value: UInt8(v)) }
        t.write(0x30, value: 0x40)                   // enable timer 3, CPU clock
        emu.run(cycles: 900)
        XCTAssertFalse(emu.cpu.irq, "not yet")
        emu.run(cycles: 200)
        XCTAssertTrue(emu.cpu.irq, "match after 1000 counts")
        XCTAssertEqual(t.read(0x34) & 0xC0, 0xC0, "match1 and match2 (both 0) flagged")
    }

    func testGPT32kClockAndStatusClear() {
        let emu = Emulator()
        emu.scheduler.setCPUClock(hz: 48_000_000)
        let t = emu.timers
        t.write(0x00, value: 10)                     // timer 1 counter = 10
        t.write(0x08, value: 5)                      // match1 = 5
        t.write(0x30, value: 0x03)                   // enable, 32 kHz clock
        emu.run(seconds: 6.0 / 32768.0)
        XCTAssertEqual(t.read(0x34) & 1, 1)
        XCTAssertEqual(t.read(0x00), 4)
        t.write(0x34, value: 1)
        XCTAssertEqual(t.read(0x34) & 1, 0)
    }

    func testOSTimerPulsesPeriodically() {
        let emu = Emulator()
        emu.powerOn(clearRAM: true)
        emu.interrupts.write(0x0C, value: 0x10)
        emu.interrupts.write(0x04, value: 0x10)
        emu.run(seconds: 0.01)
        XCTAssertTrue(emu.cpu.irq)
    }

    // MARK: Keypad

    func testKeypadContinuousScanReportsMatrix() {
        let emu = Emulator()
        let k = emu.keypad
        emu.setKey(.enter, pressed: true)            // group 6, bit 0
        emu.setKey(.up, pressed: true)               // group 7, bit 3
        k.write(0x04, value: 8); k.write(0x05, value: 8)
        k.write(0x01, value: 0x01)                   // row wait
        k.write(0x00, value: 0x03)                   // continuous scan
        emu.run(seconds: 0.01)
        XCTAssertEqual(k.read(0x10 + 2 * 6), 0x01)
        XCTAssertEqual(k.read(0x10 + 2 * 7), 0x08)
        XCTAssertEqual(k.read(0x10 + 2 * 1), 0x00)
        XCTAssertEqual(k.read(0x08) & 0x01, 0x01, "scan-complete status")
        emu.setKey(.enter, pressed: false)
        emu.run(seconds: 0.01)
        XCTAssertEqual(k.read(0x10 + 2 * 6), 0x00, "release seen on the next scan")
    }

    func testKeypadAnyKeyModeReassertsWhileHeld() {
        let emu = Emulator()
        let k = emu.keypad
        k.write(0x00, value: 0x01)                   // any-key mode
        emu.setKey(.k5, pressed: true)
        XCTAssertEqual(k.read(0x08) & 0x04, 0x04)
        k.write(0x08, value: 0xFF)                   // clear while still held
        XCTAssertEqual(k.read(0x08) & 0x04, 0x04)
        emu.setKey(.k5, pressed: false)
        k.write(0x08, value: 0xFF)
        XCTAssertEqual(k.read(0x08) & 0x04, 0x00)
    }

    func testSimultaneousKeysInSameGroup() {
        let emu = Emulator()
        emu.setKey(.second, pressed: true)
        emu.setKey(.mode, pressed: true)
        XCTAssertEqual(emu.keypad.matrix[1], 0x60)
    }

    func testOnKeyDrivesInterruptLine() {
        let emu = Emulator()
        emu.interrupts.write(0x04, value: 0x01)
        emu.setKey(CalculatorKey.on, pressed: true)
        XCTAssertTrue(emu.cpu.irq)
        emu.setKey(CalculatorKey.on, pressed: false)
        XCTAssertFalse(emu.cpu.irq)
    }

    // MARK: LCD

    /// Programs the LCD like the OS does: 240x320 scan, 16 bpp 5:6:5, BGR, panel window 320x240.
    private func configureLCD(_ emu: Emulator, madctl: UInt8 = 0x08) {
        let lcd = emu.lcd
        func w32(_ o: Int, _ v: UInt32) { for i in 0..<4 { lcd.write(UInt16(o + i), value: UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) } }
        w32(0x00, 0x1F0A_0338)
        w32(0x04, 0x0402_093F)
        w32(0x08, 0x00EF_7802)
        w32(0x10, 0xD4_0000)
        w32(0x18, 0x0000_092D)
        let p = emu.panel
        p.writeCommand(0x11)
        p.writeCommand(0x36); p.writeData(madctl)
        p.writeCommand(0x2A); [0x00, 0x00, 0x01, 0x3F].forEach { p.writeData($0) }
        p.writeCommand(0x2B); [0x00, 0x00, 0x00, 0xEF].forEach { p.writeData($0) }
        p.writeCommand(0x29)
    }

    private func pixel(_ f: LCDFrame, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * f.width + x) * 4
        return (f.pixels[i], f.pixels[i + 1], f.pixels[i + 2])
    }

    func testLCDRendersRowMajorFramebufferThroughPanel() {
        let emu = Emulator()
        configureLCD(emu)
        // VRAM pixel (x: 10, y: 20) = pure red in the OS's BGR 5:6:5 format (0xF800).
        let a = 0xD40000 + UInt32((20 * 320 + 10) * 2)
        emu.bus.write(a, value: 0x00)
        emu.bus.write(a + 1, value: 0xF8)
        emu.lcd.render()
        let f = emu.lcd.frame
        XCTAssertEqual(f.width, 320)
        XCTAssertEqual(f.height, 240)
        XCTAssertEqual(pixel(f, 10, 20).0, 0xFF)
        XCTAssertEqual(pixel(f, 10, 20).2, 0x00)
        XCTAssertEqual(pixel(f, 11, 20).0, 0x00, "neighbour black")
    }

    func testLCDPanelMirroringFollowsMADCTL() {
        let emu = Emulator()
        configureLCD(emu, madctl: 0x48)              // MX: mirror columns
        let a = 0xD40000 + UInt32((5 * 320 + 0) * 2)
        emu.bus.write(a, value: 0xFF)
        emu.bus.write(a + 1, value: 0xFF)
        emu.lcd.render()
        XCTAssertEqual(pixel(emu.lcd.frame, 319, 5).0, 0xFF)
        XCTAssertEqual(pixel(emu.lcd.frame, 0, 5).0, 0x00)
    }

    func testLCDOnlyPublishesChangedFrames() {
        let emu = Emulator()
        configureLCD(emu)
        var published = 0
        emu.lcd.onFrame = { _ in published += 1 }
        emu.lcd.render()
        emu.lcd.render()
        XCTAssertEqual(published, 1, "identical frame not republished")
        emu.bus.write(0xD40000, value: 0x1F)
        emu.lcd.render()
        XCTAssertEqual(published, 2)
    }

    func testLCDDisplayOffShowsBlack() {
        let emu = Emulator()
        configureLCD(emu)
        emu.bus.write(0xD40000, value: 0xFF)
        emu.bus.write(0xD40001, value: 0xFF)
        emu.panel.writeCommand(0x28)                 // display off
        emu.lcd.render()
        XCTAssertEqual(pixel(emu.lcd.frame, 0, 0).0, 0)
    }

    func testSPIThreeBitFramesAssemblePanelCommands() {
        let emu = Emulator()
        let spi = emu.spi
        spi.write(0x06, value: 0x02)                 // CR1: frame length 3 bits
        func send(_ word: UInt16) {                  // 9-bit word as three 3-bit frames
            for shift in [6, 3, 0] { spi.write(0x18, value: UInt8((word >> UInt16(shift)) & 7)) }
        }
        send(0x011)                                  // sleep out (command)
        send(0x036); send(0x1A5)                     // MADCTL = 0xA5 (data bit set)
        send(0x029)                                  // display on
        XCTAssertFalse(emu.panel.sleeping)
        XCTAssertTrue(emu.panel.displayOn)
        XCTAssertEqual(emu.panel.madctl, 0xA5)
        XCTAssertEqual(spi.read(0x0C) & 0x02, 0x02, "TX FIFO never full")
    }

    // MARK: RTC, SHA256, control ports

    func testRTCTicksAndLoads() {
        let emu = Emulator()
        emu.powerOn(clearRAM: true)
        let rtc = emu.rtc
        rtc.write(0x24, value: 58)                   // load 00:00:58, day 3
        rtc.write(0x30, value: 3)
        rtc.write(0x20, value: 0x41)                 // enable + load
        XCTAssertEqual(rtc.read(0x20) & 0x40, 0, "load completes")
        emu.run(seconds: 2.05)
        XCTAssertEqual(rtc.read(0x00), 0)
        XCTAssertEqual(rtc.read(0x04), 1)
        XCTAssertEqual(rtc.read(0x0C), 3)
    }

    func testSHA256AcceleratorMatchesReference() {
        let emu = Emulator()
        let sha = emu.sha256
        // Padded single block for "abc", written as little-endian register words.
        var block = [UInt32](repeating: 0, count: 16)
        block[0] = 0x6162_6380
        block[15] = 24
        for (i, w) in block.enumerated() {
            for b in 0..<4 { sha.write(UInt16(0x10 + i * 4 + b), value: UInt8(truncatingIfNeeded: w >> (8 * UInt32(b)))) }
        }
        sha.write(0x00, value: 0x0A)
        var h0: UInt32 = 0
        for b in 0..<4 { h0 |= UInt32(sha.read(UInt16(0x60 + b))) << (8 * UInt32(b)) }
        XCTAssertEqual(h0, 0xBA78_16BF)
    }

    func testBatteryComparatorLadder() {
        let c = ControlPorts()
        c.batteryLevel = 2
        func measure(p9: UInt8, p0: UInt8) -> Bool {
            c.write(0x09, value: p9); c.write(0x00, value: p0)
            return c.read(0x02) & 1 == 1
        }
        XCTAssertTrue(measure(p9: 0xB0, p0: 0x83), "battery present")
        XCTAssertTrue(measure(p9: 0x80, p0: 0x83))    // threshold 1
        XCTAssertTrue(measure(p9: 0x80, p0: 0x03))    // threshold 2
        XCTAssertFalse(measure(p9: 0x00, p0: 0x83))   // threshold 3
    }

    func testControlPort0DMirrorsNibble() {
        let c = ControlPorts()
        c.write(0x0D, value: 0x0F)
        XCTAssertEqual(c.read(0x0D), 0xFF)
    }

    func testCPUClockChangesTimebase() {
        let emu = Emulator()
        emu.scheduler.setCPUClock(hz: 6_000_000)
        let t0 = emu.scheduler.now
        emu.scheduler.cycles += 6_000_000
        XCTAssertEqual(emu.scheduler.now - t0, Scheduler.baseHz, "6M cycles at 6 MHz = 1 s")
        emu.scheduler.setCPUClock(hz: 48_000_000)
        let t1 = emu.scheduler.now
        emu.scheduler.cycles += 48_000_000
        XCTAssertEqual(emu.scheduler.now - t1, Scheduler.baseHz)
    }
}
