// TI-84 Plus CE peripherals (port of EmulatorCore/Hardware): control ports, flash
// controller, SHA-256 accelerator, USB/link port, interrupt controller, watchdog,
// general purpose timers, RTC, keypad and backlight.

import { BASE_HZ, TICKS_32K, TICKS_6MHZ, EV_GPT, EV_KEYPAD } from './scheduler.js';

export const byteOf = (v, i) => (v >>> ((i & 3) * 8)) & 0xFF;
export const setByte = (v, i, b) => {
  const s = (i & 3) * 8;
  return ((v & ~(0xFF << s)) | ((b & 0xFF) << s)) >>> 0;
};

export const INT = {
  ON: 1 << 0, TIMER1: 1 << 1, TIMER2: 1 << 2, TIMER3: 1 << 3, OSTIMER: 1 << 4,
  KEYPAD: 1 << 10, LCD: 1 << 11, RTC: 1 << 12, USB: 1 << 13,
};

// ---------------------------------------------------------------------------

/** System control ports (0xxx): power, CPU speed, battery comparator, ... */
export class ControlPorts {
  constructor() {
    this.ports = new Uint8Array(0x100);
    this.batteryLevel = 4;
    this.onCPUSpeedChange = null;
  }
  reset() { this.ports.fill(0); }

  batteryComparator() {
    const p9 = this.ports[0x09], p0 = this.ports[0x00];
    if (p9 & 0x30) return this.batteryLevel > 0;
    const hi9 = (p9 & 0x80) !== 0, hi0 = (p0 & 0x80) !== 0;
    const rank = hi9 ? (hi0 ? 1 : 2) : (hi0 ? 3 : 4);
    return this.batteryLevel >= rank;
  }

  read(o) {
    const i = o & 0xFF;
    switch (i) {
      case 0x02: return (this.ports[i] & ~0x01) | (this.batteryComparator() ? 1 : 0);
      case 0x03: return 0x00;
      case 0x0B: return this.ports[i] & ~0x02;
      case 0x0F: return this.ports[i] & 0x03;
      default: return this.ports[i];
    }
  }
  peek(o) { return this.read(o); }

  write(o, v) {
    const i = o & 0xFF;
    switch (i) {
      case 0x01:
        this.ports[i] = v & 0x13;
        if (this.onCPUSpeedChange) this.onCPUSpeedChange(v & 3);
        break;
      case 0x02: break;
      case 0x06: this.ports[i] = v & 0x07; break;
      case 0x0D: this.ports[i] = ((v & 0x0F) << 4) | (v & 0x0F); break;
      case 0x0F: this.ports[i] = v & 0x03; break;
      case 0x3D: this.ports[i] = 0; break;
      default: this.ports[i] = v;
    }
  }
}

/** Parallel-flash controller (1xxx): wait states. */
export class FlashController {
  constructor(bus) { this.bus = bus; this.ports = new Uint8Array(0x100); this.reset(); }
  reset() {
    this.ports.fill(0);
    this.ports[0x00] = 0x01; this.ports[0x02] = 0x06; this.ports[0x05] = 0x04; this.ports[0x07] = 0xFF;
    this.apply();
  }
  apply() { this.bus.flashReadCycles = this.ports[0x05] + 6; }
  read(o) { return this.ports[o & 0xFF]; }
  peek(o) { return this.read(o); }
  write(o, v) { const i = o & 0xFF; this.ports[i] = v; if (i === 0x05) this.apply(); }
}

// ---------------------------------------------------------------------------

const SHA_K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);
const SHA_INIT = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
const rotr = (x, n) => (x >>> n) | (x << (32 - n));

export function shaCompress(h, block) {
  const w = new Uint32Array(64);
  for (let i = 0; i < 16; i++) w[i] = block[i];
  for (let i = 16; i < 64; i++) {
    const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
    const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
  }
  let [a, b, c, d, e, f, g, hh] = h;
  for (let i = 0; i < 64; i++) {
    const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    const ch = (e & f) ^ (~e & g);
    const t1 = (hh + s1 + ch + SHA_K[i] + w[i]) >>> 0;
    const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    const maj = (a & b) ^ (a & c) ^ (b & c);
    const t2 = (s0 + maj) >>> 0;
    hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
  }
  h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
  h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0;
}

/** SHA-256 accelerator (2xxx) used by the boot code. */
export class SHA256Accelerator {
  constructor() { this.reset(); }
  reset() { this.state = new Array(8).fill(0); this.block = new Array(16).fill(0); }
  read(o) {
    if (o < 0x0C) return 0;
    if (o >= 0x10 && o < 0x50) return byteOf(this.block[(o - 0x10) >> 2], o);
    if (o >= 0x60 && o < 0x80) return byteOf(this.state[(o - 0x60) >> 2], o);
    return 0;
  }
  peek(o) { return this.read(o); }
  write(o, v) {
    if (o === 0x00) {
      if (v & 0x10) this.state = new Array(8).fill(0);
      else if ((v & 0x0E) === 0x0A) { this.state = SHA_INIT.slice(); shaCompress(this.state, this.block); }
      else if ((v & 0x0E) === 0x0E) shaCompress(this.state, this.block);
    } else if (o >= 0x10 && o < 0x50) {
      const i = (o - 0x10) >> 2;
      this.block[i] = setByte(this.block[i], o, v);
    }
  }
}

/** USB OTG controller (3xxx) in the "no cable attached" state. */
export class LinkPort {
  constructor() { this.regs = new Uint8Array(0x1000); this.reset(); }
  reset() {
    this.regs.fill(0);
    const put32 = (o, v) => { for (let i = 0; i < 4; i++) this.regs[o + i] = byteOf(v, i); };
    put32(0x00, 0x01000010); put32(0x04, 0x00000001); put32(0x08, 0x00000006);
    put32(0x14, 0x00001000); put32(0x80, 0x00210000);
  }
  read(o) { return this.regs[o & 0xFFF]; }
  peek(o) { return this.read(o); }
  write(o, v) {
    o &= 0xFFF;
    if (o < 0x10) return;
    if ((o >= 0x14 && o < 0x18) || (o >= 0x84 && o < 0x88) || (o >= 0xC0 && o < 0xC4) || (o >= 0x140 && o < 0x148)) {
      this.regs[o] &= ~v;
    } else this.regs[o] = v;
  }
}

/** LCD backlight PWM (Bxxx). Register 0x24: 0 = brightest. */
export class Backlight {
  static DEFAULT_LEVEL = 0x95;
  constructor() { this.regs = new Uint8Array(0x100); }
  reset() { this.regs.fill(0); }
  get brightness() {
    const level = this.regs[0x24];
    if (level <= Backlight.DEFAULT_LEVEL) return 1;
    return 1 - ((level - Backlight.DEFAULT_LEVEL) / (255 - Backlight.DEFAULT_LEVEL)) * 0.75;
  }
  read(o) { return this.regs[o & 0xFF]; }
  peek(o) { return this.read(o); }
  write(o, v) { this.regs[o & 0xFF] = v; }
}

/** Watchdog (6xxx): registers only; the OS leaves it disabled. */
export class Watchdog {
  constructor() { this.reset(); }
  reset() { this.load = 0x03EF1480; this.counter = this.load; this.control = 0; this.status = 0; }
  read(o) {
    if (o < 4) return byteOf(this.counter, o);
    if (o < 8) return byteOf(this.load, o);
    if (o === 0x0C) return this.control;
    if (o === 0x10) return this.status;
    if (o >= 0x1C && o < 0x20) return byteOf(0x00010602, o);
    return 0;
  }
  peek(o) { return this.read(o); }
  write(o, v) {
    if (o >= 4 && o < 8) this.load = setByte(this.load, o, v);
    else if (o === 0x08) { if (v === 0xB9) this.counter = this.load; }
    else if (o === 0x0C) this.control = v;
    else if (o === 0x14) this.status = 0;
  }
  saveState() { return { load: this.load, counter: this.counter, control: this.control, status: this.status }; }
  loadState(s) { Object.assign(this, s); }
}

// ---------------------------------------------------------------------------

/** Interrupt controller (5xxx): two banks of status/enable/latch/invert. */
export class InterruptController {
  constructor(cpu) {
    this.cpu = cpu;
    this.banks = [this.newBank(), this.newBank()];
    this.raw = 0;
  }
  newBank() { return { status: 0, enabled: 0, latched: 0, inverted: 0 }; }
  reset() { this.banks = [this.newBank(), this.newBank()]; this.raw = 0; this.updateCPU(); }

  set(source, level) {
    this.raw = (level ? this.raw | source : this.raw & ~source) >>> 0;
    for (const b of this.banks) {
      const active = ((level ? source : 0) ^ (b.inverted & source)) >>> 0;
      if (active) b.status = (b.status | source) >>> 0;
      else b.status = (b.status & (~source | b.latched)) >>> 0;
    }
    this.updateCPU();
  }

  pulse(source) { this.set(source, true); this.set(source, false); }

  updateCPU() {
    const [b0, b1] = this.banks;
    this.cpu.irq = ((b0.status & b0.enabled) | (b1.status & b1.enabled)) !== 0;
  }

  read(o) {
    if (o < 0x40) {
      const b = this.banks[(o >> 5) & 1];
      let v;
      switch ((o >> 2) & 7) {
        case 0: v = b.status; break;
        case 1: v = b.enabled; break;
        case 3: v = b.latched; break;
        case 4: v = b.inverted; break;
        case 5: v = b.status & b.enabled; break;
        default: v = 0;
      }
      return byteOf(v, o);
    }
    switch (o & ~3) {
      case 0x50: return byteOf(0x00010900, o);
      case 0x54: return byteOf(0x16, o);
      default: return 0;
    }
  }
  peek(o) { return this.read(o); }

  write(o, v) {
    if (o >= 0x40) return;
    const b = this.banks[(o >> 5) & 1];
    switch ((o >> 2) & 7) {
      case 1: b.enabled = setByte(b.enabled, o, v); break;
      case 2: {
        const ack = (v << ((o & 3) * 8)) >>> 0;
        b.status = (b.status & ~(ack & b.latched)) >>> 0;
        break;
      }
      case 3:
        b.latched = setByte(b.latched, o, v);
        b.status = ((b.status & b.latched) | ((this.raw ^ b.inverted) & ~b.latched)) >>> 0;
        break;
      case 4:
        b.inverted = setByte(b.inverted, o, v);
        b.status = ((b.status & b.latched) | ((this.raw ^ b.inverted) & ~b.latched)) >>> 0;
        break;
      default: break;
    }
    this.updateCPU();
  }

  saveState() { return { banks: this.banks.map((b) => ({ ...b })), raw: this.raw }; }
  loadState(s) { this.banks = s.banks.map((b) => ({ ...b })); this.raw = s.raw; this.updateCPU(); }
}

// ---------------------------------------------------------------------------

/**
 * Three 32-bit general purpose timers (7xxx), evaluated lazily from emulated time.
 * Each match/overflow pulses the timer's interrupt line; the mask register uses
 * 1 = masked.
 */
export class GeneralPurposeTimers {
  constructor(scheduler, interrupts) {
    this.sched = scheduler;
    this.interrupts = interrupts;
    this.channels = [this.newChannel(), this.newChannel(), this.newChannel()];
    this.control = 0; this.status = 0; this.mask = 0;
    this.lastSync = 0; this.fired = 0;
  }
  newChannel() { return { counter: 0, reload: 0, match1: 0, match2: 0, residue: 0 }; }

  reset() {
    this.channels = [this.newChannel(), this.newChannel(), this.newChannel()];
    this.control = 0; this.status = 0; this.mask = 0;
    this.lastSync = this.sched.now;
    this.sched.cancel(EV_GPT);
    this.updateInterrupts();
  }

  enabled(n) { return (this.control & (1 << (3 * n))) !== 0; }
  uses32k(n) { return (this.control & (2 << (3 * n))) !== 0; }
  overflowEnabled(n) { return (this.control & (4 << (3 * n))) !== 0; }
  countsUp(n) { return (this.control & (1 << (9 + n))) !== 0; }
  ticksPerCount(n) { return this.uses32k(n) ? TICKS_32K : this.sched.ticksPerCycle; }

  sync() {
    const now = this.sched.now;
    const elapsed = now - this.lastSync;
    this.lastSync = now;
    if (elapsed <= 0) return;
    for (let n = 0; n < 3; n++) {
      if (!this.enabled(n)) continue;
      const tpc = this.ticksPerCount(n);
      const total = this.channels[n].residue + elapsed;
      this.channels[n].residue = total % tpc;
      this.advance(n, Math.floor(total / tpc));
    }
  }

  flag(bit) { this.status = (this.status | bit) >>> 0; this.fired = (this.fired | bit) >>> 0; }

  advance(n, steps) {
    if (steps <= 0) return;
    const ch = this.channels[n];
    let remaining = steps;
    const up = this.countsUp(n);
    const base = 3 * n;
    while (remaining > 0) {
      const toBoundary = up ? 0xFFFFFFFF - ch.counter : ch.counter;
      if (remaining <= toBoundary) {
        const from = ch.counter;
        ch.counter = (up ? ch.counter + remaining : ch.counter - remaining) >>> 0;
        this.checkMatches(ch, from, ch.counter, up, base);
        remaining = 0;
      } else {
        const edge = up ? 0xFFFFFFFF : 0;
        this.checkMatches(ch, ch.counter, edge, up, base);
        remaining -= toBoundary + 1;
        if (this.overflowEnabled(n)) this.flag(4 << base);
        ch.counter = ch.reload;
        if (ch.counter === ch.match1) this.flag(1 << base);
        if (ch.counter === ch.match2) this.flag(2 << base);
        const period = up ? 0xFFFFFFFF - ch.reload + 1 : ch.reload + 1;
        if (remaining > period) {
          this.checkMatches(ch, ch.counter, edge, up, base);
          remaining %= period;
        }
      }
    }
  }

  checkMatches(ch, from, to, up, base) {
    const hit = (m) => (up ? (m > from && m <= to) : (m < from && m >= to));
    if (hit(ch.match1)) this.flag(1 << base);
    if (hit(ch.match2)) this.flag(2 << base);
  }

  countsToNextEvent(n) {
    const ch = this.channels[n];
    const up = this.countsUp(n);
    let best = Infinity;
    const consider = (c) => { if (c > 0 && c < best) best = c; };
    consider(up ? 0xFFFFFFFF - ch.counter + 1 : ch.counter + 1);
    for (const m of [ch.match1, ch.match2]) {
      if (up && m > ch.counter) consider(m - ch.counter);
      if (!up && m < ch.counter) consider(ch.counter - m);
    }
    return best;
  }

  scheduleNext() {
    let next = Infinity;
    for (let n = 0; n < 3; n++) {
      if (!this.enabled(n) || ((~this.mask >>> (3 * n)) & 7) === 0) continue;
      const counts = this.countsToNextEvent(n);
      if (counts === Infinity) continue;
      const tpc = this.ticksPerCount(n);
      const ticks = counts * tpc - Math.min(this.channels[n].residue, counts * tpc - 1);
      next = Math.min(next, this.lastSync + ticks);
    }
    if (next === Infinity) this.sched.cancel(EV_GPT); else this.sched.scheduleAt(EV_GPT, next);
  }

  updateInterrupts() {
    const events = (this.fired & ~this.mask) >>> 0;
    this.fired = 0;
    if (!events) return;
    for (let n = 0; n < 3; n++) {
      if ((events >>> (3 * n)) & 7) this.interrupts.pulse(INT.TIMER1 << n);
    }
  }

  handleEvent() { this.sync(); this.updateInterrupts(); this.scheduleNext(); }
  willChangeCPUClock() { this.sync(); }
  didChangeCPUClock() { this.scheduleNext(); }

  read(o) { this.sync(); return this.peek(o); }
  peek(o) {
    if (o < 0x30) {
      const ch = this.channels[o >> 4];
      switch ((o >> 2) & 3) {
        case 0: return byteOf(ch.counter, o);
        case 1: return byteOf(ch.reload, o);
        case 2: return byteOf(ch.match1, o);
        default: return byteOf(ch.match2, o);
      }
    }
    if (o < 0x34) return byteOf(this.control, o);
    if (o < 0x38) return byteOf(this.status, o);
    if (o < 0x3C) return byteOf(this.mask, o);
    if (o < 0x40) return byteOf(0x00010801, o);
    return 0;
  }

  write(o, v) {
    this.sync();
    if (o < 0x30) {
      const ch = this.channels[o >> 4];
      switch ((o >> 2) & 3) {
        case 0: ch.counter = setByte(ch.counter, o, v); break;
        case 1: ch.reload = setByte(ch.reload, o, v); break;
        case 2: ch.match1 = setByte(ch.match1, o, v); break;
        default: ch.match2 = setByte(ch.match2, o, v);
      }
    } else if (o < 0x34) this.control = setByte(this.control, o, v);
    else if (o < 0x38) this.status = (this.status & ~(v << ((o & 3) * 8))) >>> 0;
    else if (o < 0x3C) this.mask = setByte(this.mask, o, v);
    this.updateInterrupts();
    this.scheduleNext();
  }

  saveState() {
    return { channels: this.channels.map((c) => ({ ...c })), control: this.control, status: this.status,
      mask: this.mask, lastSync: this.lastSync };
  }
  loadState(s) {
    this.channels = s.channels.map((c) => ({ ...c }));
    this.control = s.control; this.status = s.status; this.mask = s.mask; this.lastSync = s.lastSync;
    this.updateInterrupts();
  }
}

// ---------------------------------------------------------------------------

const newTime = () => ({ seconds: 0, minutes: 0, hours: 0, days: 0 });

/** Real-time clock (8xxx), ticking once per emulated second. */
export class RealTimeClock {
  constructor(interrupts) { this.interrupts = interrupts; this.reset(); }
  reset() {
    this.time = newTime(); this.alarm = newTime(); this.load = newTime();
    this.control = 0; this.status = 0;
    this.updateInterrupt();
  }
  tick() {
    if (!(this.control & 1)) return;
    const t = this.time;
    let s = 1;
    t.seconds = (t.seconds + 1) & 0xFF;
    if (t.seconds >= 60) {
      t.seconds = 0; t.minutes++; s |= 2;
      if (t.minutes >= 60) {
        t.minutes = 0; t.hours++; s |= 4;
        if (t.hours >= 24) { t.hours = 0; t.days = (t.days + 1) & 0xFFFF; s |= 8; }
      }
    }
    if (t.seconds === this.alarm.seconds && t.minutes === this.alarm.minutes && t.hours === this.alarm.hours) s |= 0x10;
    this.status |= s;
    this.updateInterrupt();
  }
  updateInterrupt() {
    this.interrupts.set(INT.RTC, (this.status & (this.control >>> 1) & 0x1F) !== 0);
  }
  read(o) {
    switch (o) {
      case 0x00: return this.time.seconds;
      case 0x04: return this.time.minutes;
      case 0x08: return this.time.hours;
      case 0x0C: return this.time.days & 0xFF;
      case 0x0D: return this.time.days >> 8;
      case 0x10: return this.alarm.seconds;
      case 0x14: return this.alarm.minutes;
      case 0x18: return this.alarm.hours;
      case 0x24: return this.load.seconds;
      case 0x28: return this.load.minutes;
      case 0x2C: return this.load.hours;
      case 0x30: return this.load.days & 0xFF;
      case 0x31: return this.load.days >> 8;
      case 0x34: return this.status;
      default:
        if (o >= 0x20 && o < 0x24) return byteOf(this.control, o);
        if (o >= 0x3C && o < 0x40) return byteOf(0x00010500, o);
        return 0;
    }
  }
  peek(o) { return this.read(o); }
  write(o, v) {
    switch (o) {
      case 0x10: this.alarm.seconds = v & 0x3F; break;
      case 0x14: this.alarm.minutes = v & 0x3F; break;
      case 0x18: this.alarm.hours = v & 0x1F; break;
      case 0x20:
        this.control = setByte(this.control, o, v);
        if (v & 0x40) {
          this.time = { ...this.load };
          this.control = (this.control & ~0x40) >>> 0;
          this.status |= 0x20;
        }
        this.updateInterrupt();
        break;
      case 0x21: case 0x22: case 0x23: this.control = setByte(this.control, o, v); break;
      case 0x24: this.load.seconds = v & 0x3F; break;
      case 0x28: this.load.minutes = v & 0x3F; break;
      case 0x2C: this.load.hours = v & 0x1F; break;
      case 0x30: this.load.days = (this.load.days & 0xFF00) | v; break;
      case 0x31: this.load.days = (this.load.days & 0x00FF) | (v << 8); break;
      case 0x34: this.status &= ~v; this.updateInterrupt(); break;
      default: break;
    }
  }
  saveState() {
    return { time: { ...this.time }, alarm: { ...this.alarm }, load: { ...this.load }, control: this.control, status: this.status };
  }
  loadState(s) {
    this.time = { ...s.time }; this.alarm = { ...s.alarm }; this.load = { ...s.load };
    this.control = s.control; this.status = s.status;
    this.updateInterrupt();
  }
}

// ---------------------------------------------------------------------------

/**
 * Keypad controller (Axxx) scanning the 8x8 key matrix with the programmed row
 * timing; the ROM's driver reads the scanned data registers. ON has its own
 * interrupt line.
 */
export class Keypad {
  constructor(scheduler, interrupts) {
    this.sched = scheduler;
    this.interrupts = interrupts;
    this.matrix = new Uint16Array(16);
    this.onKeyDown = false;
    this.data = new Uint16Array(16);
    // Input bookkeeping only (not machine state): which pressed keys the OS has
    // read back, and whether it has polled since the last release. The front end
    // uses this to hold short taps until the OS has seen them.
    this.seen = new Uint16Array(16);
    this.releaseSeen = true;
    this.reset();
  }

  reset() {
    this.control = 0; this.rows = 8; this.columns = 8; this.status = 0; this.enable = 0;
    this.data.fill(0);
    this.gpioEnable = 0;
    this.scanRow = 0;
    this.scanChanged = false;
    this.sched.cancel(EV_KEYPAD);
    this.updateInterrupt();
  }

  get mode() { return this.control & 3; }
  get rowWait() { return (this.control >>> 2) & 0x3FFF; }
  get scanWait() { return this.control >>> 16; }

  /** group 0 / bit 0xFF is the ON key. */
  setKey(group, bit, pressed) {
    if (bit === 0xFF) {
      this.onKeyDown = pressed;
      this.interrupts.set(INT.ON, pressed);
      return;
    }
    const m = 1 << bit;
    if (pressed) { this.matrix[group] |= m; this.seen[group] &= ~m; } else { this.matrix[group] &= ~m; this.releaseSeen = false; }
    if (this.mode === 1) this.anyKeyCheck();
  }

  /** Whether the OS has read this key as pressed since it went down. */
  wasSeen(group, bit) {
    return bit === 0xFF || (this.seen[group] & (1 << bit)) !== 0;
  }

  isPressed(group, bit) {
    return bit === 0xFF ? this.onKeyDown : (this.matrix[group] & (1 << bit)) !== 0;
  }

  releaseAll() {
    this.matrix.fill(0);
    if (this.onKeyDown) { this.onKeyDown = false; this.interrupts.set(INT.ON, false); }
  }

  anyKeyCheck() {
    if (this.matrix.some((v) => v !== 0)) { this.status |= 4; this.updateInterrupt(); }
  }

  startScan() {
    this.scanRow = 0;
    this.scanChanged = false;
    this.sched.scheduleAfter(EV_KEYPAD, Math.max(1, this.rowWait) * TICKS_6MHZ);
  }

  handleEvent() {
    const m = this.mode;
    if (m < 2) return;
    const rowCount = Math.min(this.rows, 16);
    if (this.scanRow < rowCount) {
      const colMask = this.columns >= 16 ? 0xFFFF : (1 << this.columns) - 1;
      const v = this.matrix[this.scanRow] & colMask;
      if (this.data[this.scanRow] !== v) { this.data[this.scanRow] = v; this.scanChanged = true; }
      this.scanRow++;
      this.sched.scheduleAfter(EV_KEYPAD, Math.max(1, this.rowWait) * TICKS_6MHZ);
      return;
    }
    this.status |= 1;
    if (this.scanChanged) this.status |= 2;
    if (this.data.some((v) => v !== 0)) this.status |= 4;
    this.scanRow = 0;
    this.scanChanged = false;
    if (m === 3) this.sched.scheduleAfter(EV_KEYPAD, Math.max(1, this.scanWait + this.rowWait) * TICKS_6MHZ);
    else this.control = (this.control & ~3) >>> 0;
    this.updateInterrupt();
  }

  updateInterrupt() { this.interrupts.set(INT.KEYPAD, (this.status & this.enable & 7) !== 0); }

  read(o) {
    const v = this.peek(o);
    if (o >= 0x10 && o < 0x30) {
      const row = (o - 0x10) >> 1;
      this.seen[row] |= this.data[row];
      if (this.data.every((d) => d === 0) && this.matrix.every((d) => d === 0)) this.releaseSeen = true;
    } else if (o === 0x08 && (v & 4) === 0) {
      this.releaseSeen = true;
    }
    return v;
  }

  peek(o) {
    if (o < 4) return byteOf(this.control, o);
    if (o === 0x04) return this.rows;
    if (o === 0x05) return this.columns;
    if (o === 0x08) return this.status;
    if (o === 0x0C) return this.enable;
    if (o >= 0x10 && o < 0x30) {
      const row = (o - 0x10) >> 1;
      return (o & 1) === 0 ? this.data[row] & 0xFF : this.data[row] >> 8;
    }
    if (o >= 0x40 && o < 0x44) return byteOf(this.gpioEnable, o);
    return 0;
  }

  write(o, v) {
    if (o < 4) {
      const oldMode = this.mode;
      this.control = setByte(this.control, o, v);
      if (o === 0) {
        const m = this.mode;
        if (m >= 2 && (oldMode < 2 || !this.sched.isScheduled(EV_KEYPAD))) this.startScan();
        if (m < 2) this.sched.cancel(EV_KEYPAD);
        if (m === 1) this.anyKeyCheck();
      }
    } else if (o === 0x04) this.rows = v;
    else if (o === 0x05) this.columns = v;
    else if (o === 0x08) {
      this.status &= ~v;
      if (this.mode === 1) this.anyKeyCheck();
      this.updateInterrupt();
    } else if (o === 0x0C) {
      this.enable = v & 7;
      this.updateInterrupt();
    } else if (o >= 0x40 && o < 0x44) this.gpioEnable = setByte(this.gpioEnable, o, v);
  }

  saveState() {
    return { control: this.control, rows: this.rows, columns: this.columns, status: this.status,
      enable: this.enable, data: Array.from(this.data), gpioEnable: this.gpioEnable, scanRow: this.scanRow };
  }
  loadState(s) {
    this.control = s.control; this.rows = s.rows; this.columns = s.columns; this.status = s.status;
    this.enable = s.enable; this.data.set(s.data); this.gpioEnable = s.gpioEnable; this.scanRow = s.scanRow;
    this.updateInterrupt();
  }
}

export { BASE_HZ };
