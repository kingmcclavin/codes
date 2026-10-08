// Memory system of the TI-84 Plus CE: flash chip, RAM, address decoding and the
// I/O port bus. JavaScript port of EmulatorCore/Memory and Hardware/IOBus.
//
//   000000-3FFFFF  flash (4 MiB)
//   D00000-D657FF  RAM + VRAM, mirrored every 512 KiB up to DFFFFF
//   E00000-E3FFFF  memory-mapped I/O (ports 1xxx-4xxx)
//   F00000-FAFFFF  memory-mapped I/O (ports 5xxx-Fxxx)

export const FLASH_SIZE = 0x400000;
export const RAM_SIZE = 0x65800;
export const RAM_BASE = 0xD00000;

/** Converts a memory-mapped I/O address to its I/O port, or -1. */
export function mmioPort(a) {
  const block = a >>> 16;
  const low = a & 0xFFF;
  if (block >= 0xE0 && block <= 0xE3) return ((block - 0xE0 + 1) << 12) | low;
  if (block >= 0xF0 && block <= 0xFA) return ((block - 0xF0 + 5) << 12) | low;
  return -1;
}

const MODE_READ = 0, MODE_AUTOSELECT = 1, MODE_CFI = 2, MODE_ERASE_STATUS = 3;

/**
 * 4 MiB parallel NOR flash. CPU stores are JEDEC/AMD command cycles (program,
 * sector/chip erase, autoselect, CFI); programming only clears bits. Boot sectors
 * (below 0x20000) are protected.
 */
export class Flash {
  static PROTECTED_END = 0x20000;

  constructor() {
    this.bytes = new Uint8Array(FLASH_SIZE).fill(0xFF);
    this.mode = MODE_READ;
    this.step = 0;
    this.programArmed = false;
    this.eraseStatusReads = 0;
    this.dirty = false;
  }

  load(image) {
    this.bytes.set(image.subarray(0, FLASH_SIZE));
    if (image.length < FLASH_SIZE) this.bytes.fill(0xFF, image.length);
    this.resetCommandState();
    this.dirty = false;
  }

  resetCommandState() {
    this.mode = MODE_READ; this.step = 0; this.programArmed = false; this.eraseStatusReads = 0;
  }

  read(offset) {
    const a = offset & (FLASH_SIZE - 1);
    switch (this.mode) {
      case MODE_READ: return this.bytes[a];
      case MODE_AUTOSELECT:
        switch (a & 0xFF) {
          case 0x00: return 0xC2;
          case 0x02: return 0xA8;
          default: return 0x00;
        }
      case MODE_CFI:
        switch (a & 0xFF) {
          case 0x20: return 0x51;
          case 0x22: return 0x52;
          case 0x24: return 0x59;
          case 0x4E: return 0x16;
          default: return 0x00;
        }
      default:
        this.eraseStatusReads--;
        if (this.eraseStatusReads <= 0) this.mode = MODE_READ;
        return 0x80;
    }
  }

  write(offset, value) {
    const a = offset & (FLASH_SIZE - 1);
    const cmd = a & 0xFFF;
    if (this.programArmed) {
      this.programArmed = false;
      this.step = 0;
      this.program(a, value);
      return;
    }
    if (value === 0xF0) { this.resetCommandState(); return; }
    if (value === 0x98 && (a & 0xFF) === 0xAA && this.step === 0) { this.mode = MODE_CFI; return; }
    switch (this.step) {
      case 0: this.step = (cmd === 0xAAA && value === 0xAA) ? 1 : 0; break;
      case 1: this.step = (cmd === 0x555 && value === 0x55) ? 2 : 0; break;
      case 2:
        this.step = 0;
        if (cmd !== 0xAAA) return;
        if (value === 0xA0) this.programArmed = true;
        else if (value === 0x80) this.step = 3;
        else if (value === 0x90) this.mode = MODE_AUTOSELECT;
        break;
      case 3: this.step = (cmd === 0xAAA && value === 0xAA) ? 4 : 0; break;
      case 4: this.step = (cmd === 0x555 && value === 0x55) ? 5 : 0; break;
      case 5:
        this.step = 0;
        if (value === 0x30) this.eraseSector(a);
        else if (value === 0x10 && cmd === 0xAAA) this.eraseChip();
        break;
      default: this.step = 0;
    }
  }

  program(a, value) {
    if (a < Flash.PROTECTED_END) return;
    const old = this.bytes[a];
    const v = old & value;
    if (v !== old) { this.bytes[a] = v; this.dirty = true; }
  }

  eraseSector(a) {
    if (a < Flash.PROTECTED_END) { this.enterEraseStatus(); return; }
    const size = a < 0x10000 ? 0x2000 : 0x10000;
    const start = a & ~(size - 1);
    this.bytes.fill(0xFF, start, start + size);
    this.enterEraseStatus();
    this.dirty = true;
  }

  eraseChip() {
    this.bytes.fill(0xFF, Flash.PROTECTED_END);
    this.enterEraseStatus();
    this.dirty = true;
  }

  enterEraseStatus() {
    this.mode = MODE_ERASE_STATUS;
    this.eraseStatusReads = 3;
  }
}

/** Placeholder for unpopulated port ranges. */
class NullDevice {
  read() { return 0; }
  write() {}
  peek() { return 0; }
  reset() {}
}

/** A peripheral modelled only as read/write registers (UART, Cxxx, ...). */
export class RegisterFileDevice {
  constructor(size) { this.regs = new Uint8Array(size); }
  read(o) { return this.regs[o % this.regs.length]; }
  write(o, v) { this.regs[o % this.regs.length] = v; }
  peek(o) { return this.read(o); }
  reset() { this.regs.fill(0); }
}

const MIRROR_MASKS = [0xFF, 0xFF, 0xFF, 0xFFF, 0xFFF, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF];

/** The 16-bit I/O space: bits 15..12 pick one of 16 peripherals. */
export class IOBus {
  constructor() {
    this.devices = Array.from({ length: 16 }, () => new NullDevice());
  }
  attach(device, index) { this.devices[index] = device; }
  read(port) { const d = port >> 12; return this.devices[d].read(port & MIRROR_MASKS[d]); }
  write(port, v) { const d = port >> 12; this.devices[d].write(port & MIRROR_MASKS[d], v); }
  peek(port) {
    const d = port >> 12;
    const dev = this.devices[d];
    return dev.peek ? dev.peek(port & MIRROR_MASKS[d]) : dev.read(port & MIRROR_MASKS[d]);
  }
  resetAll() { for (const d of this.devices) d.reset(); }
}

/**
 * Routes CPU accesses to flash, RAM or peripherals and charges wait states to the
 * scheduler's cycle counter.
 */
export class MemoryBus {
  constructor(flash, ram, io, scheduler) {
    this.flash = flash;
    this.ram = ram;                 // Uint8Array(RAM_SIZE)
    this.io = io;
    this.sched = scheduler;
    this.flashReadCycles = 10;
    this.ramReadCycles = 3;
    this.ramWriteCycles = 2;
    this.mmioCycles = 4;
    /** RAM writes at/above this offset mark the framebuffer dirty. */
    this.vramWatch = 0;
    this.vramDirty = true;
  }

  read(address) {
    const a = address & 0xFFFFFF;
    if (a < FLASH_SIZE) {
      this.sched.cycles += this.flashReadCycles;
      return this.flash.mode === 0 ? this.flash.bytes[a] : this.flash.read(a);
    }
    if (a >= RAM_BASE && a < 0xE00000) {
      this.sched.cycles += this.ramReadCycles;
      const o = (a - RAM_BASE) & 0x7FFFF;
      return o < RAM_SIZE ? this.ram[o] : 0;
    }
    const port = mmioPort(a);
    if (port >= 0) {
      this.sched.cycles += this.mmioCycles;
      return this.io.read(port);
    }
    this.sched.cycles += 1;
    return 0;
  }

  write(address, value) {
    const a = address & 0xFFFFFF;
    if (a >= RAM_BASE && a < 0xE00000) {
      this.sched.cycles += this.ramWriteCycles;
      const o = (a - RAM_BASE) & 0x7FFFF;
      if (o < RAM_SIZE) {
        this.ram[o] = value;
        if (o >= this.vramWatch) this.vramDirty = true;
      }
      return;
    }
    if (a < FLASH_SIZE) {
      this.sched.cycles += this.flashReadCycles;
      this.flash.write(a, value);
      return;
    }
    const port = mmioPort(a);
    if (port >= 0) {
      this.sched.cycles += this.mmioCycles;
      this.io.write(port, value);
      return;
    }
    this.sched.cycles += 1;
  }

  /** Debugger read: no wait states, no side effects. */
  peek(address) {
    const a = address & 0xFFFFFF;
    if (a < FLASH_SIZE) return this.flash.mode === 0 ? this.flash.bytes[a] : 0;
    if (a >= RAM_BASE && a < 0xE00000) {
      const o = (a - RAM_BASE) & 0x7FFFF;
      return o < RAM_SIZE ? this.ram[o] : 0;
    }
    const port = mmioPort(a);
    return port >= 0 ? this.io.peek(port) : 0;
  }
}
