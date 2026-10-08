// Drives the emulator in real time and talks to the UI through messages.
// Runs inside a Web Worker (worker.js) or, if workers are unavailable, on the page.
//
//   UI → runner: start, key, pause, resume, speed, battery, reset, resetRAM, eraseAll,
//                autosave, saveSlot, loadSlot, exportState, importState, debug, step,
//                breakpoints
//   runner → UI: ready, frame, status, notice, slots, exported, debug, error

import { Emulator } from './core/emulator.js';
import { BASE_HZ } from './core/scheduler.js';
import * as storage from './storage.js';

const SLICE_MS = 8;
// Emulated seconds. A tap is held until the OS has read it, and the next press
// waits until the OS has polled after the release; the OS only samples the
// keypad between tasks, so a quick touch could otherwise fall between samples.
const MIN_KEY_HOLD = 0.03;
const MIN_KEY_GAP = 0.02;
const MAX_KEY_WAIT = 0.5;             // give up waiting (calculator off, busy program)

export class Runner {
  constructor(post) {
    this.post = post;
    this.emu = new Emulator();
    this.started = false;
    this.paused = true;
    this.userPaused = false;
    this.speed = 1;
    this.lastSerial = -1;
    this.lastTick = 0;
    this.timer = null;
    this.pressedAt = new Map();
    this.keyQueue = [];
    this.lastReleaseAt = -Infinity;
    this.windowStart = 0;
    this.windowEmulated = 0;
    this.emu.cpu.onUnsupported = (msg) => this.post({ type: 'notice', text: msg });
  }

  async handle(msg) {
    try {
      switch (msg.type) {
        case 'start': await this.start(msg.rom, msg.battery); break;
        case 'key': this.applyKey(msg.name, msg.down); break;
        case 'pause': this.userPaused = true; this.setPaused(true); break;
        case 'resume': this.userPaused = false; this.emu.cpu.ignoreBreakpointOnce = true; this.setPaused(false); break;
        case 'background': this.setPaused(true); await this.autosave(); break;
        case 'foreground': if (!this.userPaused) this.setPaused(false); break;
        case 'speed': this.speed = msg.value; break;
        case 'battery': this.emu.control.batteryLevel = msg.value; break;
        case 'reset': this.emu.reset(); this.notice('Calculator reset.'); break;
        case 'resetRAM': this.emu.powerOn(true); await storage.del('autosave'); this.notice('RAM cleared.'); break;
        case 'eraseAll': this.emu.eraseAll(); await storage.del('autosave'); this.notice('Archive and RAM erased.'); break;
        case 'autosave': await this.autosave(); break;
        case 'saveSlot': await this.saveSlot(msg.slot); break;
        case 'loadSlot': await this.loadSlot(msg.slot); break;
        case 'slots': await this.sendSlots(); break;
        case 'exportState': this.post({ type: 'exported', state: this.emu.saveState() }); break;
        case 'importState': this.emu.loadState(msg.state); this.notice('State restored.'); break;
        case 'debug': this.post({ type: 'debug', info: this.debugInfo() }); break;
        case 'step':
          this.emu.cpu.ignoreBreakpointOnce = true;
          this.emu.step();
          this.emu.lcd.render();
          this.sendFrame();
          this.post({ type: 'debug', info: this.debugInfo() });
          break;
        case 'breakpoints': this.emu.cpu.setBreakpoints(msg.list); break;
        default: break;
      }
    } catch (err) {
      this.post({ type: 'error', text: String(err && err.message ? err.message : err) });
    }
  }

  notice(text) { this.post({ type: 'notice', text }); }

  async start(romBytes, battery) {
    const emu = this.emu;
    emu.loadROM(romBytes);
    if (battery !== undefined) emu.control.batteryLevel = battery;
    const saved = await storage.get('autosave');
    if (saved && saved.romHash === emu.romHash) {
      try { emu.loadState(saved); } catch (e) {
        emu.powerOn(true);
        this.notice('Saved calculator memory could not be restored; starting fresh.');
      }
    }
    this.started = true;
    this.post({ type: 'ready', boot: emu.bootVersion, os: emu.osVersion, persistent: await storage.persistent() });
    this.lastSerial = -1;
    emu.lcd.invalidate();
    emu.lcd.render();
    this.sendFrame();
    this.setPaused(false);
  }

  setPaused(p) {
    if (!this.started) return;
    this.paused = p;
    this.post({ type: 'status', paused: p, breakpoint: null });
    if (!p) {
      this.lastTick = performance.now();
      this.windowStart = this.lastTick;
      this.windowEmulated = 0;
      this.schedule();
    } else if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  schedule() {
    if (this.timer === null) this.timer = setTimeout(() => { this.timer = null; this.tick(); }, SLICE_MS);
  }

  tick() {
    if (this.paused) return;
    const now = performance.now();
    const elapsed = Math.min((now - this.lastTick) / 1000, 0.1);
    this.lastTick = now;
    let emulated = 0;
    const emu = this.emu;
    if (this.speed === 0) {
      const start = performance.now();
      do {
        emu.runSeconds(1 / 60);
        emulated += 1 / 60;
        this.applyPendingKeys();
      } while (performance.now() - start < 12 && !emu.cpu.breakpointHit);
    } else if (elapsed > 0) {
      emulated = elapsed * this.speed;
      emu.runSeconds(emulated);
    }
    this.applyPendingKeys();
    this.sendFrame();

    if (emu.cpu.breakpointHit) {
      this.paused = true;
      this.userPaused = true;
      this.post({ type: 'status', paused: true, breakpoint: emu.cpu.pc });
      this.post({ type: 'debug', info: this.debugInfo() });
      return;
    }

    this.windowEmulated += emulated;
    if (now - this.windowStart >= 1000) {
      this.post({ type: 'speed', value: this.windowEmulated / ((now - this.windowStart) / 1000) });
      this.windowStart = now;
      this.windowEmulated = 0;
    }
    this.schedule();
  }

  sendFrame() {
    const lcd = this.emu.lcd;
    if (lcd.serial === this.lastSerial) return;
    this.lastSerial = lcd.serial;
    const copy = lcd.frame.slice();
    this.post({ type: 'frame', pixels: copy.buffer, brightness: this.emu.backlight.brightness }, [copy.buffer]);
  }

  // Key events are applied in order. A press waits until the OS has noticed the
  // previous release and a release waits until the OS has read the press, so fast
  // typing never loses taps or merges them; keys held together (chords) still overlap.
  applyKey(name, down) {
    this.keyQueue.push({ name, down });
    this.applyPendingKeys();
  }

  applyPendingKeys() {
    const emu = this.emu;
    while (this.keyQueue.length) {
      const now = emu.scheduler.now;
      const e = this.keyQueue[0];
      if (e.down) {
        const since = now - this.lastReleaseAt;
        if (since < MIN_KEY_GAP * BASE_HZ) return;
        if (!emu.keypad.releaseSeen && since < MAX_KEY_WAIT * BASE_HZ) return;
        this.pressedAt.set(e.name, now);
        emu.setKey(e.name, true);
      } else {
        const held = now - (this.pressedAt.get(e.name) ?? 0);
        if (held < MIN_KEY_HOLD * BASE_HZ) return;
        if (!emu.keySeen(e.name) && held < MAX_KEY_WAIT * BASE_HZ) return;
        this.pressedAt.delete(e.name);
        this.lastReleaseAt = now;
        emu.setKey(e.name, false);
      }
      this.keyQueue.shift();
    }
  }

  async autosave() {
    if (!this.started) return;
    await storage.put('autosave', this.emu.saveState());
  }

  async saveSlot(slot) {
    const state = this.emu.saveState();
    state.savedAt = Date.now();
    await storage.put('slot' + slot, state);
    this.notice(`Saved to slot ${slot}.`);
    await this.sendSlots();
  }

  async loadSlot(slot) {
    const state = await storage.get('slot' + slot);
    if (!state) { this.notice(`Slot ${slot} is empty.`); return; }
    this.emu.loadState(state);
    this.notice(`Restored slot ${slot}.`);
  }

  async sendSlots() {
    const slots = [];
    for (const n of [1, 2, 3]) {
      const s = await storage.get('slot' + n);
      slots.push(s ? s.savedAt || 0 : null);
    }
    this.post({ type: 'slots', slots });
  }

  debugInfo() {
    const emu = this.emu, c = emu.cpu;
    const bytes = [];
    for (let i = 0; i < 6; i++) {
      const a = c.adl ? (c.pc + i) & 0xFFFFFF : (c.mbase << 16) | ((c.pc + i) & 0xFFFF);
      bytes.push(emu.bus.peek(a));
    }
    const stack = [];
    const sp = c.adl ? c.spl : (c.mbase << 16) | c.sps;
    const w = c.adl ? 3 : 2;
    for (let i = 0; i < 6; i++) {
      let v = 0;
      for (let b = 0; b < w; b++) v |= emu.bus.peek(sp + i * w + b) << (8 * b);
      stack.push(v);
    }
    const ic = emu.interrupts.banks[0];
    return {
      regs: { a: c.a, f: c.f, bc: c.bc, de: c.de, hl: c.hl, ix: c.ix, iy: c.iy, sps: c.sps, spl: c.spl, pc: c.pc,
        i: c.i, r: c.r, mbase: c.mbase, af_: (c.a_ << 8) | c.f_, bc_: c.bc_, de_: c.de_, hl_: c.hl_ },
      adl: c.adl, madl: c.madl, ief1: c.ief1, ief2: c.ief2, im: c.im, halted: c.halted,
      cycles: emu.scheduler.cycles, cpuHz: emu.scheduler.cpuHz,
      seconds: emu.scheduler.now / BASE_HZ,
      opcode: bytes, stack,
      interrupts: { enabled: ic.enabled, status: ic.status, latched: ic.latched, raw: emu.interrupts.raw, irq: c.irq },
      lcd: { control: emu.lcd.control, base: emu.lcd.upbase, madctl: emu.panel.madctl, on: emu.panel.displayVisible },
      keypad: { mode: emu.keypad.mode, status: emu.keypad.status, data: Array.from(emu.keypad.data.subarray(0, 8)) },
      timers: { control: emu.timers.control, status: emu.timers.status, counters: emu.timers.channels.map((ch) => ch.counter) },
      lastUnsupported: c.lastUnsupported,
    };
  }
}
