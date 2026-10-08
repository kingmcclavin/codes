// Deterministic emulation clock (port of EmulatorCore/Scheduler.swift).
//
// Time is counted in base ticks of 1.536 GHz so every CE clock divides it exactly:
// 48/24/12/6 MHz CPU = 32/64/128/256 ticks, 32768 Hz crystal = 46875 ticks.
// JavaScript numbers are exact up to 2^53 ticks (about 68 days of emulated time).

export const BASE_HZ = 1536000000;
export const TICKS_32K = 46875;
export const TICKS_6MHZ = 256;

export const EV_OS_TIMER = 0, EV_RTC = 1, EV_LCD = 2, EV_KEYPAD = 3, EV_GPT = 4, EV_WATCHDOG = 5;
const EVENT_COUNT = 6;

export class Scheduler {
  constructor() {
    this.deadlines = new Float64Array(EVENT_COUNT);
    this.reset();
  }

  reset() {
    this.cycles = 0;          // total CPU cycles since power-on
    this.stopCycles = 0;      // the CPU yields once cycles >= stopCycles
    this.anchorTicks = 0;
    this.anchorCycles = 0;
    this.ticksPerCycle = 256;
    this.runLimit = 0;
    this.deadlines.fill(Infinity);
  }

  get now() { return this.anchorTicks + (this.cycles - this.anchorCycles) * this.ticksPerCycle; }
  get cpuHz() { return BASE_HZ / this.ticksPerCycle; }

  setCPUClock(hz) {
    const t = this.now;
    this.anchorTicks = t;
    this.anchorCycles = this.cycles;
    this.ticksPerCycle = Math.max(1, Math.floor(BASE_HZ / hz));
    this.updateStop();
  }

  isScheduled(e) { return this.deadlines[e] !== Infinity; }
  scheduleAt(e, ticks) { this.deadlines[e] = ticks; this.updateStop(); }
  scheduleAfter(e, ticks) { this.scheduleAt(e, this.now + ticks); }
  cancel(e) { this.deadlines[e] = Infinity; }

  updateStop() {
    let next = Infinity;
    for (let i = 0; i < EVENT_COUNT; i++) if (this.deadlines[i] < next) next = this.deadlines[i];
    let stop = this.runLimit;
    if (next !== Infinity) {
      const t = this.now;
      if (next <= t) stop = this.cycles;
      else {
        const delta = Math.ceil((next - t) / this.ticksPerCycle);
        stop = Math.min(stop, this.cycles + delta);
      }
    }
    this.stopCycles = stop;
  }

  /** Returns the earliest due event (and unschedules it), or -1. */
  popDueEvent() {
    const t = this.now;
    let best = -1, bestTime = Infinity;
    for (let i = 0; i < EVENT_COUNT; i++) {
      const d = this.deadlines[i];
      if (d <= t && d < bestTime) { best = i; bestTime = d; }
    }
    if (best >= 0) this.deadlines[best] = Infinity;
    return best;
  }

  saveState() {
    return {
      cycles: this.cycles, anchorTicks: this.anchorTicks, anchorCycles: this.anchorCycles,
      ticksPerCycle: this.ticksPerCycle,
      deadlines: Array.from(this.deadlines, (d) => (d === Infinity ? null : d)),
    };
  }

  loadState(s) {
    this.cycles = s.cycles; this.anchorTicks = s.anchorTicks; this.anchorCycles = s.anchorCycles;
    this.ticksPerCycle = s.ticksPerCycle;
    s.deadlines.forEach((d, i) => { if (i < EVENT_COUNT) this.deadlines[i] = d === null ? Infinity : d; });
    this.updateStop();
  }
}
