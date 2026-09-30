import Foundation

/// Real-time clock (port range 8xxx, memory-mapped at 0xF30000), clocked by the
/// 32768 Hz crystal.
///
///     +00 seconds  +04 minutes  +08 hours  +0C days (16-bit)
///     +10/+14/+18 alarm sec/min/hour
///     +20 control: bit0 enable, bits1-5 interrupt enables (sec, min, hour, day, alarm),
///                  bit6 load (self-clearing)
///     +24/+28/+2C/+30 load sec/min/hour/day     +34 interrupt status (write 1 to clear)
public final class RealTimeClock: IODevice {
    public struct Time: Codable, Equatable {
        public var seconds: UInt8 = 0
        public var minutes: UInt8 = 0
        public var hours: UInt8 = 0
        public var days: UInt16 = 0
    }

    public private(set) var time = Time()
    public private(set) var alarm = Time()
    public private(set) var load = Time()
    public private(set) var control: UInt32 = 0
    public private(set) var status: UInt8 = 0

    unowned(unsafe) let interrupts: InterruptController

    init(interrupts: InterruptController) { self.interrupts = interrupts }

    public func reset() {
        time = Time(); alarm = Time(); load = Time()
        control = 0; status = 0
        updateInterrupt()
    }

    /// Advances the clock by one second (scheduler callback).
    func tick() {
        guard control & 1 != 0 else { return }
        var s: UInt8 = 1
        time.seconds += 1
        if time.seconds >= 60 {
            time.seconds = 0; time.minutes += 1; s |= 2
            if time.minutes >= 60 {
                time.minutes = 0; time.hours += 1; s |= 4
                if time.hours >= 24 { time.hours = 0; time.days &+= 1; s |= 8 }
            }
        }
        if time.seconds == alarm.seconds && time.minutes == alarm.minutes && time.hours == alarm.hours { s |= 0x10 }
        status |= s
        updateInterrupt()
    }

    private func updateInterrupt() {
        interrupts.set(InterruptSource.rtc, status & UInt8(truncatingIfNeeded: control >> 1) & 0x1F != 0)
    }

    public func read(_ offset: UInt16) -> UInt8 {
        let o = Int(offset)
        switch o {
        case 0x00: return time.seconds
        case 0x04: return time.minutes
        case 0x08: return time.hours
        case 0x0C: return UInt8(truncatingIfNeeded: time.days)
        case 0x0D: return UInt8(truncatingIfNeeded: time.days >> 8)
        case 0x10: return alarm.seconds
        case 0x14: return alarm.minutes
        case 0x18: return alarm.hours
        case 0x20..<0x24: return byteOf(control, o)
        case 0x24: return load.seconds
        case 0x28: return load.minutes
        case 0x2C: return load.hours
        case 0x30: return UInt8(truncatingIfNeeded: load.days)
        case 0x31: return UInt8(truncatingIfNeeded: load.days >> 8)
        case 0x34: return status
        case 0x3C..<0x40: return byteOf(0x0001_0500, o)
        default: return 0
        }
    }

    public func write(_ offset: UInt16, value: UInt8) {
        let o = Int(offset)
        switch o {
        case 0x10: alarm.seconds = value & 0x3F
        case 0x14: alarm.minutes = value & 0x3F
        case 0x18: alarm.hours = value & 0x1F
        case 0x20:
            setByte(&control, o, value)
            if value & 0x40 != 0 {
                // Load completes immediately; the OS polls bit 6 until it clears.
                time = load
                control &= ~0x40
                status |= 0x20
            }
            updateInterrupt()
        case 0x21..<0x24: setByte(&control, o, value)
        case 0x24: load.seconds = value & 0x3F
        case 0x28: load.minutes = value & 0x3F
        case 0x2C: load.hours = value & 0x1F
        case 0x30: load.days = (load.days & 0xFF00) | UInt16(value)
        case 0x31: load.days = (load.days & 0x00FF) | UInt16(value) << 8
        case 0x34:
            status &= ~value
            updateInterrupt()
        default: break
        }
    }

    public struct State: Codable, Equatable { var time, alarm, load: Time; var control: UInt32; var status: UInt8 }
    public var state: State {
        get { State(time: time, alarm: alarm, load: load, control: control, status: status) }
        set { time = newValue.time; alarm = newValue.alarm; load = newValue.load; control = newValue.control; status = newValue.status; updateInterrupt() }
    }
}
