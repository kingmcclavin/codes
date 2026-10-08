// LCD pipeline (port of Hardware/LCD.swift): PL111 controller streaming VRAM into
// an ST7789-class panel model configured over a 3-wire 9-bit SPI command stream.

import { EV_LCD, BASE_HZ } from './scheduler.js';
import { byteOf, setByte, INT } from './devices.js';
import { RAM_SIZE, RAM_BASE } from './memory.js';

export const LCD_WIDTH = 320;
export const LCD_HEIGHT = 240;
const PIXELS = LCD_WIDTH * LCD_HEIGHT;
const BLACK = 0xFF000000;

const rgba = (r, g, b) => (0xFF000000 | (b << 16) | (g << 8) | r) >>> 0;

/** Panel controller: window (CASET/RASET), MADCTL addressing, sleep/on/invert. */
export class LCDPanel {
  constructor() {
    this.gram = new Uint32Array(PIXELS).fill(0xFFFFFFFF);
    this.contentChanged = true;
    this.reset();
  }

  reset() {
    this.sleeping = true; this.displayOn = false; this.inverted = false;
    this.madctl = 0; this.colmod = 0x66; this.command = 0; this.params = [];
    this.columnStart = 0; this.columnEnd = LCD_WIDTH - 1;
    this.rowStart = 0; this.rowEnd = LCD_HEIGHT - 1;
    this.shiftIn = 0; this.bitCount = 0; this.readBits = [];
    this.curCol = 0; this.curRow = 0;
    this.contentChanged = true;
  }

  get displayVisible() { return !this.sleeping && this.displayOn; }

  get isIdentityMapping() {
    return (this.madctl & 0xE0) === 0 && this.columnStart === 0 && this.rowStart === 0
      && this.columnEnd === LCD_WIDTH - 1 && this.rowEnd === LCD_HEIGHT - 1;
  }

  /** Clocks one bit in; returns the bit driven out. */
  clock(bit) {
    const out = this.readBits.length ? this.readBits.shift() : false;
    this.shiftIn = ((this.shiftIn << 1) | (bit ? 1 : 0)) & 0xFFFF;
    if (++this.bitCount === 9) {
      const word = this.shiftIn & 0x1FF;
      this.shiftIn = 0;
      this.bitCount = 0;
      if (word & 0x100) this.writeData(word & 0xFF); else this.writeCommand(word & 0xFF);
    }
    return out;
  }

  writeCommand(c) {
    this.contentChanged = true;
    this.command = c;
    this.params = [];
    this.readBits = [];
    let reply = [];
    switch (c) {
      case 0x01: this.reset(); break;
      case 0x10: this.sleeping = true; break;
      case 0x11: this.sleeping = false; break;
      case 0x20: this.inverted = false; break;
      case 0x21: this.inverted = true; break;
      case 0x28: this.displayOn = false; break;
      case 0x29: this.displayOn = true; break;
      case 0x2C: this.beginFrame(); break;
      case 0x04: reply = [0x85, 0x85, 0x52]; break;
      case 0xDA: reply = [0x85]; break;
      case 0xDB: reply = [0x85]; break;
      case 0xDC: reply = [0x52]; break;
      default: break;
    }
    if (reply.length) {
      const bits = reply.length > 1 ? [false] : [];
      for (const b of reply) for (let i = 0; i < 8; i++) bits.push((b & (0x80 >> i)) !== 0);
      this.readBits = bits;
    }
  }

  writeData(d) {
    this.params.push(d);
    this.contentChanged = true;
    const n = this.params.length, p = this.params;
    if (this.command === 0x36 && n === 1) this.madctl = d;
    else if (this.command === 0x3A && n === 1) this.colmod = d;
    else if (this.command === 0x2A && n === 4) { this.columnStart = (p[0] << 8) | p[1]; this.columnEnd = (p[2] << 8) | p[3]; }
    else if (this.command === 0x2B && n === 4) { this.rowStart = (p[0] << 8) | p[1]; this.rowEnd = (p[2] << 8) | p[3]; }
  }

  beginFrame() { this.curCol = this.columnStart; this.curRow = this.rowStart; }

  pushPixel(color) {
    let x = this.curCol, y = this.curRow;
    if (this.madctl & 0x20) { const t = x; x = y; y = t; }
    if (this.madctl & 0x40) x = LCD_WIDTH - 1 - x;
    if (this.madctl & 0x80) y = LCD_HEIGHT - 1 - y;
    if (x >= 0 && x < LCD_WIDTH && y >= 0 && y < LCD_HEIGHT) this.gram[y * LCD_WIDTH + x] = color;
    if (++this.curCol > this.columnEnd) {
      this.curCol = this.columnStart;
      if (++this.curRow > this.rowEnd) this.curRow = this.rowStart;
    }
  }

  /** Writes what the glass shows into `out`; returns true if it changed. */
  present(out) {
    let changed = false;
    if (!this.displayVisible) {
      for (let i = 0; i < PIXELS; i++) if (out[i] !== BLACK) { out[i] = BLACK; changed = true; }
      return changed;
    }
    const g = this.gram;
    if (!this.inverted) {
      for (let i = 0; i < PIXELS; i++) if (out[i] !== g[i]) { out.set(g); return true; }
      return false;
    }
    for (let i = 0; i < PIXELS; i++) {
      const c = (g[i] ^ 0x00FFFFFF) >>> 0;
      if (out[i] !== c) { out[i] = c; changed = true; }
    }
    return changed;
  }

  saveState() {
    return { sleeping: this.sleeping, displayOn: this.displayOn, inverted: this.inverted, madctl: this.madctl,
      colmod: this.colmod, command: this.command,
      window: [this.columnStart, this.columnEnd, this.rowStart, this.rowEnd],
      shiftIn: this.shiftIn, bitCount: this.bitCount };
  }
  loadState(s) {
    Object.assign(this, { sleeping: s.sleeping, displayOn: s.displayOn, inverted: s.inverted, madctl: s.madctl,
      colmod: s.colmod, command: s.command, shiftIn: s.shiftIn, bitCount: s.bitCount });
    [this.columnStart, this.columnEnd, this.rowStart, this.rowEnd] = s.window;
    this.readBits = []; this.params = [];
    this.contentChanged = true;
  }
}

/** ARM PL111 controller (4xxx) streaming the framebuffer to the panel. */
export class LCDController {
  constructor(scheduler, interrupts, bus, panel) {
    this.sched = scheduler;
    this.interrupts = interrupts;
    this.bus = bus;
    this.panel = panel;
    this.timing = new Uint32Array(4);
    this.palette = new Uint8Array(0x200);
    this.cursor = new Uint8Array(0x400);
    this.frame = new Uint32Array(PIXELS);     // RGBA (little-endian) as shown on glass
    this.serial = 0;
    this.framesRendered = 0;
    this.onFrame = null;
    this.upbase = 0; this.lpbase = 0; this.control = 0; this.imsc = 0; this.ris = 0;
    this.needsStream = true;
  }

  reset() {
    this.timing.fill(0);
    this.upbase = 0; this.lpbase = 0; this.control = 0; this.imsc = 0; this.ris = 0;
    this.palette.fill(0); this.cursor.fill(0);
    this.sched.cancel(EV_LCD);
    this.updateInterrupt();
    this.updateVRAMWatch();
    this.invalidate();
  }

  get enabled() { return (this.control & 1) !== 0; }
  get powered() { return (this.control & 0x800) !== 0; }
  get bppMode() { return (this.control >>> 1) & 7; }
  get pixelsPerLine() { return (((this.timing[0] >>> 2) & 0x3F) + 1) * 16; }
  get linesPerPanel() { return (this.timing[1] & 0x3FF) + 1; }

  get framePeriod() {
    const [t0, t1, t2] = this.timing;
    const ppl = this.pixelsPerLine;
    const hsw = ((t0 >>> 8) & 0xFF) + 1, hfp = ((t0 >>> 16) & 0xFF) + 1, hbp = (t0 >>> 24) + 1;
    const lpp = this.linesPerPanel;
    const vsw = ((t1 >>> 10) & 0x3F) + 1, vfp = (t1 >>> 16) & 0xFF, vbp = t1 >>> 24;
    const pcd = (t2 & 0x1F) | ((t2 >>> 27) << 5);
    const divider = ((t2 >>> 26) & 1) ? 1 : pcd + 2;
    const ticks = (ppl + hsw + hfp + hbp) * (lpp + vsw + vfp + vbp) * divider * 64;
    const minT = BASE_HZ / 120, maxT = BASE_HZ / 20;
    return (ticks < minT || ticks > maxT) ? BASE_HZ / 60 : ticks;
  }

  updateInterrupt() { this.interrupts.set(INT.LCD, (this.ris & this.imsc & 0x1E) !== 0); }

  scheduleFrame() {
    if (this.enabled) {
      if (!this.sched.isScheduled(EV_LCD)) this.sched.scheduleAfter(EV_LCD, this.framePeriod);
    } else this.sched.cancel(EV_LCD);
  }

  handleEvent() {
    if (!this.enabled) return;
    this.ris |= 0x04 | 0x08;
    this.updateInterrupt();
    this.render();
    this.sched.scheduleAfter(EV_LCD, this.framePeriod);
  }

  render() {
    if (this.enabled && this.powered && (this.bus.vramDirty || this.needsStream)) {
      this.bus.vramDirty = false;
      this.needsStream = false;
      this.stream();
      this.panel.contentChanged = true;
    }
    this.framesRendered++;
    if (!this.panel.contentChanged) return;
    this.panel.contentChanged = false;
    if (!this.panel.present(this.frame)) return;
    this.serial++;
    if (this.onFrame) this.onFrame(this.frame, this.serial);
  }

  invalidate() {
    this.needsStream = true;
    this.bus.vramDirty = true;
    this.panel.contentChanged = true;
  }

  updateVRAMWatch() {
    const base = this.upbase & 0xFFFFF8;
    this.bus.vramWatch = (base >= RAM_BASE && base < 0xE00000) ? (base - RAM_BASE) & 0x7FFFF : 0;
    this.needsStream = true;
  }

  paletteColor(index, bgr) {
    const v = this.palette[index * 2] | (this.palette[index * 2 + 1] << 8);
    let lo = v & 0x1F, hi = (v >> 10) & 0x1F;
    const g = (v >> 5) & 0x1F;
    if (bgr) { const t = lo; lo = hi; hi = t; }
    const i = (v >> 15) & 1;
    const r6 = (lo << 1) | i, g6 = (g << 1) | i, b6 = (hi << 1) | i;
    return rgba((r6 << 2) | (r6 >> 4), (g6 << 2) | (g6 >> 4), (b6 << 2) | (b6 >> 4));
  }

  stream() {
    const total = this.pixelsPerLine * this.linesPerPanel;
    const bgr = (this.control & 0x100) !== 0;
    const bepo = (this.control & 0x400) !== 0;
    let addr = this.upbase & 0xFFFFF8;
    const mode = this.bppMode;
    const ram = this.bus.ram;
    const panel = this.panel;
    const byte = (a) => {
      const o = a - RAM_BASE;
      return (o >= 0 && o < RAM_SIZE) ? ram[o] : this.bus.peek(a);
    };

    panel.beginFrame();

    // Fast path: the OS configuration (16 bpp 5:6:5 from RAM, full window, natural order).
    if (mode === 6 && panel.isIdentityMapping && total === PIXELS
        && addr >= RAM_BASE && addr - RAM_BASE + total * 2 <= RAM_SIZE) {
      const dst = panel.gram;
      const sr = bgr ? 11 : 0, sb = bgr ? 0 : 11;
      let o = addr - RAM_BASE;
      for (let i = 0; i < total; i++, o += 2) {
        const v = ram[o] | (ram[o + 1] << 8);
        const r5 = (v >> sr) & 0x1F, g6 = (v >> 5) & 0x3F, b5 = (v >> sb) & 0x1F;
        dst[i] = (0xFF000000 | (((b5 << 3) | (b5 >> 2)) << 16) | (((g6 << 2) | (g6 >> 4)) << 8) | ((r5 << 3) | (r5 >> 2))) >>> 0;
      }
      return;
    }

    if (mode === 4 || mode === 6 || mode === 7) {
      for (let n = 0; n < total; n++) {
        const v = byte(addr) | (byte(addr + 1) << 8);
        addr += 2;
        let r, g, b;
        if (mode === 6) {
          r = v & 0x1F; g = (v >> 5) & 0x3F; b = (v >> 11) & 0x1F;
          if (bgr) { const t = r; r = b; b = t; }
          r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
        } else if (mode === 4) {
          r = v & 0x1F; g = (v >> 5) & 0x1F; b = (v >> 10) & 0x1F;
          if (bgr) { const t = r; r = b; b = t; }
          r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
        } else {
          r = v & 0xF; g = (v >> 4) & 0xF; b = (v >> 8) & 0xF;
          if (bgr) { const t = r; r = b; b = t; }
          r *= 17; g *= 17; b *= 17;
        }
        panel.pushPixel(rgba(r, g, b));
      }
    } else if (mode === 5) {
      for (let n = 0; n < total; n++) {
        let r = byte(addr), g = byte(addr + 1), b = byte(addr + 2);
        addr += 4;
        if (bgr) { const t = r; r = b; b = t; }
        panel.pushPixel(rgba(r, g, b));
      }
    } else {
      const bpp = 1 << mode;
      const perByte = 8 / bpp;
      const pmask = (1 << bpp) - 1;
      const lut = new Uint32Array(1 << bpp);
      for (let i = 0; i < lut.length; i++) lut[i] = this.paletteColor(i, bgr);
      let n = 0;
      while (n < total) {
        const v = byte(addr++);
        for (let k = 0; k < perByte && n < total; k++, n++) {
          const slot = bepo ? perByte - 1 - k : k;
          panel.pushPixel(lut[(v >> (slot * bpp)) & pmask]);
        }
      }
    }
  }

  read(o) {
    if (o < 0x010) return byteOf(this.timing[o >> 2], o);
    if (o < 0x014) return byteOf(this.upbase, o);
    if (o < 0x018) return byteOf(this.lpbase, o);
    if (o < 0x01C) return byteOf(this.control, o);
    if (o < 0x020) return byteOf(this.imsc, o);
    if (o < 0x024) return byteOf(this.ris, o);
    if (o < 0x028) return byteOf(this.ris & this.imsc, o);
    if (o >= 0x02C && o < 0x030) return byteOf(this.upbase, o);
    if (o >= 0x030 && o < 0x034) return byteOf(this.lpbase, o);
    if (o >= 0x200 && o < 0x400) return this.palette[o - 0x200];
    if (o >= 0x800 && o < 0xC00) return this.cursor[o - 0x800];
    if (o >= 0xFE0 && o < 0x1000) {
      const id = [0x11, 0x11, 0x14, 0x00, 0x0D, 0xF0, 0x05, 0xB1];
      return (o & 3) === 0 ? id[(o - 0xFE0) >> 2] : 0;
    }
    return 0;
  }
  peek(o) { return this.read(o); }

  write(o, v) {
    if (o < 0x010) { this.timing[o >> 2] = setByte(this.timing[o >> 2], o, v); this.needsStream = true; }
    else if (o < 0x014) { this.upbase = setByte(this.upbase, o, v) & 0xFFFFF8; this.updateVRAMWatch(); }
    else if (o < 0x018) { this.lpbase = setByte(this.lpbase, o, v) & 0xFFFFF8; }
    else if (o < 0x01C) { this.control = setByte(this.control, o, v); this.needsStream = true; this.scheduleFrame(); }
    else if (o < 0x020) { this.imsc = setByte(this.imsc, o, v) & 0x1E; this.updateInterrupt(); }
    else if (o >= 0x028 && o < 0x02C) { this.ris = (this.ris & ~(v << ((o & 3) * 8))) >>> 0; this.updateInterrupt(); }
    else if (o >= 0x200 && o < 0x400) { this.palette[o - 0x200] = v; this.needsStream = true; }
    else if (o >= 0x800 && o < 0xC00) this.cursor[o - 0x800] = v;
  }

  saveState() {
    return { timing: Array.from(this.timing), upbase: this.upbase, lpbase: this.lpbase, control: this.control,
      imsc: this.imsc, ris: this.ris, palette: Array.from(this.palette), cursor: Array.from(this.cursor) };
  }
  loadState(s) {
    this.timing.set(s.timing); this.upbase = s.upbase; this.lpbase = s.lpbase; this.control = s.control;
    this.imsc = s.imsc; this.ris = s.ris; this.palette.set(s.palette); this.cursor.set(s.cursor);
    this.updateInterrupt();
    this.updateVRAMWatch();
    this.invalidate();
    this.scheduleFrame();
  }
}

/** PL022-style SPI port (Dxxx) carrying the panel's command stream. */
export class SPIController {
  constructor(panel) { this.panel = panel; this.reset(); }
  reset() { this.cr0 = 0; this.cr1 = 0; this.cr2 = 0; this.intCtrl = 0; this.rx = []; this.txShift = 0; }
  get frameBits() { return ((this.cr1 >>> 16) & 0x1F) + 1; }

  transfer(v) {
    const bits = this.frameBits;
    let rx = 0;
    for (let i = bits - 1; i >= 0; i--) {
      const out = this.panel.clock(((v >>> i) & 1) !== 0);
      rx = ((rx << 1) | (out ? 1 : 0)) >>> 0;
    }
    if ((this.cr2 & 0x100) && this.rx.length < 16) this.rx.push(rx);
  }

  read(o) {
    if (o < 0x04) return byteOf(this.cr0, o);
    if (o < 0x08) return byteOf(this.cr1, o);
    if (o < 0x0C) return byteOf(this.cr2, o);
    if (o < 0x10) {
      const n = this.rx.length;
      return byteOf((n << 4) | 0x2 | (n === 16 ? 1 : 0), o);
    }
    if (o < 0x14) return byteOf(this.intCtrl, o);
    if (o >= 0x18 && o < 0x1C) {
      if (o === 0x18) this.txShift = this.rx.length ? this.rx.shift() : 0;
      return byteOf(this.txShift, o);
    }
    if (o >= 0x60 && o < 0x64) return byteOf(0x00012100, o);
    if (o >= 0x64 && o < 0x68) return byteOf(0x0E0F0F1F, o);
    return 0;
  }
  peek(o) { return (o >= 0x18 && o < 0x1C) ? byteOf(this.txShift, o) : this.read(o); }

  write(o, v) {
    if (o < 0x04) this.cr0 = setByte(this.cr0, o, v);
    else if (o < 0x08) this.cr1 = setByte(this.cr1, o, v);
    else if (o < 0x0C) {
      this.cr2 = setByte(this.cr2, o, v);
      if (this.cr2 & 0x04) { this.rx = []; this.cr2 = (this.cr2 & ~0x04) >>> 0; }
      this.cr2 = (this.cr2 & ~0x08) >>> 0;
    } else if (o >= 0x10 && o < 0x14) this.intCtrl = setByte(this.intCtrl, o, v);
    else if (o >= 0x18 && o < 0x1C) {
      this.txShift = setByte(this.txShift, o, v);
      if (o - 0x18 === ((this.frameBits - 1) >> 3)) {
        this.transfer(this.txShift);
        this.txShift = 0;
      }
    }
  }

  saveState() { return { cr0: this.cr0, cr1: this.cr1, cr2: this.cr2, intCtrl: this.intCtrl, rx: this.rx.slice() }; }
  loadState(s) { this.cr0 = s.cr0; this.cr1 = s.cr1; this.cr2 = s.cr2; this.intCtrl = s.intCtrl; this.rx = s.rx.slice(); }
}
