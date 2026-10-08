// A complete TI-84 Plus CE (port of EmulatorCore/Emulator.swift + EmulatorState).

import { Scheduler, BASE_HZ, TICKS_32K, EV_OS_TIMER, EV_RTC, EV_LCD, EV_KEYPAD, EV_GPT } from './scheduler.js';
import { Flash, MemoryBus, IOBus, RegisterFileDevice, FLASH_SIZE, RAM_SIZE } from './memory.js';
import { CPU } from './cpu.js';
import {
  ControlPorts, FlashController, SHA256Accelerator, LinkPort, InterruptController, Watchdog,
  GeneralPurposeTimers, RealTimeClock, Keypad, Backlight, INT,
} from './devices.js';
import { LCDController, LCDPanel, SPIController } from './lcd.js';

const CPU_CLOCKS = [6000000, 12000000, 24000000, 48000000];
const OS_TIMER_PERIODS = [74, 154, 218, 314];

/** Matrix positions [group, bit] of the physical keys (bit 0xFF = ON). */
export const KEYS = {
  graph: [1, 0], trace: [1, 1], zoom: [1, 2], window: [1, 3], yEquals: [1, 4], second: [1, 5], mode: [1, 6], del: [1, 7],
  sto: [2, 1], ln: [2, 2], log: [2, 3], square: [2, 4], inverse: [2, 5], math: [2, 6], alpha: [2, 7],
  k0: [3, 0], k1: [3, 1], k4: [3, 2], k7: [3, 3], comma: [3, 4], sin: [3, 5], apps: [3, 6], xton: [3, 7],
  decimal: [4, 0], k2: [4, 1], k5: [4, 2], k8: [4, 3], leftParen: [4, 4], cos: [4, 5], prgm: [4, 6], stat: [4, 7],
  negate: [5, 0], k3: [5, 1], k6: [5, 2], k9: [5, 3], rightParen: [5, 4], tan: [5, 5], vars: [5, 6],
  enter: [6, 0], add: [6, 1], subtract: [6, 2], multiply: [6, 3], divide: [6, 4], power: [6, 5], clear: [6, 6],
  down: [7, 0], left: [7, 1], right: [7, 2], up: [7, 3],
  on: [0, 0xFF],
};

export class ROMError extends Error {}

/** Validates a ROM dump; short dumps are padded with erased flash (0xFF). */
export function validateROM(bytes) {
  if (bytes.length < 0x20000 || bytes.length > FLASH_SIZE) {
    throw new ROMError(`Unexpected ROM size ${bytes.length} bytes (a TI-84 Plus CE dump is 4 MB).`);
  }
  if (bytes[0] !== 0xF3) throw new ROMError('This does not look like a TI-84 Plus CE ROM (no eZ80 boot code).');
  const image = new Uint8Array(FLASH_SIZE).fill(0xFF);
  image.set(bytes);
  return image;
}

/** Finds the "d.d.d.dddd" version string in a range of the image. The OS also
 *  embeds older compatibility versions, so the highest one found is reported. */
export function findVersion(image, start, end) {
  const isDigit = (b) => b >= 0x30 && b <= 0x39;
  let best = null;
  for (let i = start; i + 10 <= end; i++) {
    if (isDigit(image[i]) && image[i + 1] === 0x2E && isDigit(image[i + 2]) && image[i + 3] === 0x2E
        && isDigit(image[i + 4]) && image[i + 5] === 0x2E && isDigit(image[i + 6]) && isDigit(image[i + 7])
        && isDigit(image[i + 8]) && isDigit(image[i + 9])) {
      const v = String.fromCharCode(...image.subarray(i, i + 10));
      if (best === null || v > best) best = v;
    }
  }
  return best;
}

/** FNV-1a fingerprint of the ROM (identifies which ROM a save state belongs to). */
export function romFingerprint(image) {
  let h = 0x811C9DC5;
  for (let i = 0; i < image.length; i++) { h ^= image[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

export class Emulator {
  constructor() {
    this.scheduler = new Scheduler();
    this.flash = new Flash();
    this.ram = new Uint8Array(RAM_SIZE);
    this.io = new IOBus();
    this.bus = new MemoryBus(this.flash, this.ram, this.io, this.scheduler);
    this.cpu = new CPU(this.bus, this.scheduler);
    this.interrupts = new InterruptController(this.cpu);
    this.control = new ControlPorts();
    this.flashController = new FlashController(this.bus);
    this.sha256 = new SHA256Accelerator();
    this.linkPort = new LinkPort();
    this.panel = new LCDPanel();
    this.lcd = new LCDController(this.scheduler, this.interrupts, this.bus, this.panel);
    this.watchdog = new Watchdog();
    this.timers = new GeneralPurposeTimers(this.scheduler, this.interrupts);
    this.rtc = new RealTimeClock(this.interrupts);
    this.protectedPorts = new RegisterFileDevice(0x100);
    this.keypad = new Keypad(this.scheduler, this.interrupts);
    this.backlight = new Backlight();
    this.cxxx = new RegisterFileDevice(0x100);
    this.spi = new SPIController(this.panel);
    this.uart = new RegisterFileDevice(0x100);
    this.fxxx = new RegisterFileDevice(0x100);

    const devices = [this.control, this.flashController, this.sha256, this.linkPort, this.lcd, this.interrupts,
      this.watchdog, this.timers, this.rtc, this.protectedPorts, this.keypad, this.backlight, this.cxxx,
      this.spi, this.uart, this.fxxx];
    devices.forEach((d, i) => this.io.attach(d, i));
    this.control.onCPUSpeedChange = (i) => this.setCPUSpeed(i);
    this.rom = null;
    this.romHash = null;
  }

  /** Installs a ROM image (validated, padded) and powers on. */
  loadROM(bytes) {
    this.rom = validateROM(bytes);
    this.romHash = romFingerprint(this.rom);
    this.flash.load(this.rom);
    this.powerOn(true);
  }

  get bootVersion() { return this.rom ? findVersion(this.rom, 0, 0x20000) : null; }
  get osVersion() { return this.rom ? findVersion(this.rom, 0x20000, 0x100000) : null; }

  powerOn(clearRAM) {
    this.scheduler.reset();
    if (clearRAM) this.ram.fill(0);
    this.flash.resetCommandState();
    this.panel.reset();
    this.io.resetAll();
    this.cpu.reset();
    this.setCPUSpeed(0);
    this.scheduleOSTimer();
    this.scheduler.scheduleAfter(EV_RTC, BASE_HZ);
  }

  reset() { this.powerOn(false); }

  /** Restores flash to the pristine ROM (erasing the archive) and cold-boots. */
  eraseAll() {
    if (!this.rom) return;
    this.flash.load(this.rom);
    this.powerOn(true);
  }

  setCPUSpeed(index) {
    this.timers.willChangeCPUClock();
    this.scheduler.setCPUClock(CPU_CLOCKS[index & 3]);
    this.timers.didChangeCPUClock();
  }

  scheduleOSTimer() {
    this.scheduler.scheduleAfter(EV_OS_TIMER, OS_TIMER_PERIODS[this.control.ports[0] & 3] * TICKS_32K);
  }

  /** Runs the whole system for `cycles` CPU cycles (or until a breakpoint). */
  run(cycles) {
    const s = this.scheduler;
    const start = s.cycles;
    const limit = start + cycles;
    s.runLimit = limit;
    while (s.cycles < limit) {
      this.processEvents();
      s.runLimit = limit;
      s.updateStop();
      this.cpu.execute();
      if (this.cpu.breakpointHit) break;
    }
    this.processEvents();
    return s.cycles - start;
  }

  /** Runs for an amount of emulated time, independent of CPU clock changes. */
  runSeconds(seconds) {
    const s = this.scheduler;
    const target = s.now + Math.floor(seconds * BASE_HZ);
    let executed = 0;
    while (s.now < target) {
      const remaining = Math.ceil((target - s.now) / s.ticksPerCycle);
      executed += this.run(Math.max(1, remaining));
      if (this.cpu.breakpointHit) break;
    }
    return executed;
  }

  /** Debugger single step. */
  step() {
    this.processEvents();
    this.scheduler.runLimit = this.scheduler.cycles + 1000000;
    this.cpu.debugStep();
    this.processEvents();
  }

  processEvents() {
    let e;
    while ((e = this.scheduler.popDueEvent()) >= 0) {
      switch (e) {
        case EV_OS_TIMER: this.interrupts.pulse(INT.OSTIMER); this.scheduleOSTimer(); break;
        case EV_RTC: this.rtc.tick(); this.scheduler.scheduleAfter(EV_RTC, BASE_HZ); break;
        case EV_LCD: this.lcd.handleEvent(); break;
        case EV_KEYPAD: this.keypad.handleEvent(); break;
        case EV_GPT: this.timers.handleEvent(); break;
        default: break;
      }
    }
  }

  setKey(name, pressed) {
    const pos = KEYS[name];
    if (pos) this.keypad.setKey(pos[0], pos[1], pressed);
  }

  /** Whether the OS has read the key since it was pressed (see Keypad.wasSeen). */
  keySeen(name) {
    const pos = KEYS[name];
    return pos ? this.keypad.wasSeen(pos[0], pos[1]) : true;
  }

  isKeyPressed(name) {
    const pos = KEYS[name];
    return pos ? this.keypad.isPressed(pos[0], pos[1]) : false;
  }

  // ---- Save states ---------------------------------------------------------

  /** Complete machine snapshot (structured-cloneable: plain objects + typed arrays). */
  saveState() {
    if (!this.rom) throw new Error('No ROM loaded');
    const flashDiff = [];
    for (let start = 0; start < FLASH_SIZE; start += 0x10000) {
      const a = this.flash.bytes.subarray(start, start + 0x10000);
      const b = this.rom.subarray(start, start + 0x10000);
      for (let i = 0; i < 0x10000; i++) {
        if (a[i] !== b[i]) { flashDiff.push([start, a.slice()]); break; }
      }
    }
    return {
      format: 'ti84ce-web-1',
      romHash: this.romHash,
      cpu: this.cpu.saveState(),
      ram: this.ram.slice(),
      flashDiff,
      flashMode: this.flash.mode,
      scheduler: this.scheduler.saveState(),
      control: Array.from(this.control.ports),
      flashController: Array.from(this.flashController.ports),
      sha256: { state: this.sha256.state.slice(), block: this.sha256.block.slice() },
      usb: this.linkPort.regs.slice(),
      lcd: this.lcd.saveState(),
      panel: this.panel.saveState(),
      gram: this.panel.gram.slice(),
      interrupts: this.interrupts.saveState(),
      watchdog: this.watchdog.saveState(),
      timers: this.timers.saveState(),
      rtc: this.rtc.saveState(),
      protectedPorts: this.protectedPorts.regs.slice(),
      keypad: this.keypad.saveState(),
      backlight: this.backlight.regs.slice(),
      spi: this.spi.saveState(),
      misc: [this.cxxx.regs.slice(), this.uart.regs.slice(), this.fxxx.regs.slice()],
    };
  }

  loadState(s) {
    if (!this.rom) throw new Error('No ROM loaded');
    if (s.format !== 'ti84ce-web-1') throw new Error('Unsupported save state format');
    if (s.romHash !== this.romHash) throw new Error('This save state was made with a different ROM');
    this.flash.load(this.rom);
    for (const [start, data] of s.flashDiff) this.flash.bytes.set(data, start);
    this.ram.set(s.ram);
    this.control.ports.set(s.control);
    this.flashController.ports.set(s.flashController);
    this.flashController.apply();
    this.sha256.state = s.sha256.state.slice();
    this.sha256.block = s.sha256.block.slice();
    this.linkPort.regs.set(s.usb);
    this.panel.loadState(s.panel);
    if (s.gram) this.panel.gram.set(s.gram);
    this.lcd.loadState(s.lcd);
    this.watchdog.loadState(s.watchdog);
    this.rtc.loadState(s.rtc);
    this.protectedPorts.regs.set(s.protectedPorts);
    this.keypad.loadState(s.keypad);
    this.backlight.regs.set(s.backlight);
    this.spi.loadState(s.spi);
    this.cxxx.regs.set(s.misc[0]); this.uart.regs.set(s.misc[1]); this.fxxx.regs.set(s.misc[2]);
    this.cpu.loadState(s.cpu);
    this.scheduler.loadState(s.scheduler);
    this.timers.loadState(s.timers);
    this.interrupts.loadState(s.interrupts);
    this.keypad.releaseAll();
    this.lcd.render();
  }

  /** One-line register summary (same format as the Swift headless tool). */
  get debugDescription() {
    const c = this.cpu;
    const h = (v, n) => v.toString(16).toUpperCase().padStart(n, '0');
    return `PC=${h(c.pc, 6)} SP=${h(c.adl ? c.spl : c.sps, 6)} AF=${h(c.af, 4)} BC=${h(c.bc, 6)} DE=${h(c.de, 6)} `
      + `HL=${h(c.hl, 6)} IX=${h(c.ix, 6)} IY=${h(c.iy, 6)} ADL=${c.adl ? 1 : 0} IEF=${c.ief1 ? 1 : 0} IM=${c.im}`
      + `${c.halted ? ' HALT' : ''} cyc=${this.scheduler.cycles}`;
  }
}
