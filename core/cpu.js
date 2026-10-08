// Zilog eZ80 CPU core (TI-84 Plus CE). JavaScript port of EmulatorCore/CPU.
//
// The eZ80 runs in Z80 mode (ADL = 0: 16-bit registers and addresses, MBASE
// supplies address bits 23..16) or ADL mode (ADL = 1: 24-bit). The suffix bytes
// .SIS/.LIS/.SIL/.LIL (0x40/0x49/0x52/0x5B) override the data width (L) and
// immediate width (IL) of a single instruction.

export const FC = 0x01, FN = 0x02, FPV = 0x04, FX = 0x08, FH = 0x10, FY = 0x20, FZ = 0x40, FS = 0x80;

// Sign / zero / parity lookup for 8-bit results (includes undocumented bits 3, 5).
export const SZP = new Uint8Array(256);
for (let v = 0; v < 256; v++) {
  let f = v & (FS | FX | FY);
  if (v === 0) f |= FZ;
  let bits = 0;
  for (let b = v; b; b >>= 1) bits += b & 1;
  if ((bits & 1) === 0) f |= FPV;
  SZP[v] = f;
}

const hex2 = (v) => '0x' + v.toString(16).toUpperCase().padStart(2, '0');

export class CPU {
  constructor(bus, scheduler) {
    this.bus = bus;
    this.io = bus.io;
    this.sched = scheduler;
    this.irq = false;               // maskable interrupt line (interrupt controller)
    this.breakpoints = new Set();
    this.ignoreBreakpointOnce = false;
    this.onUnsupported = null;
    this.traceHook = null;
    this.reset();
  }

  reset() {
    this.a = 0; this.f = 0; this.bc = 0; this.de = 0; this.hl = 0;
    this.ix = 0; this.iy = 0; this.sps = 0; this.spl = 0; this.pc = 0;
    this.i = 0; this.r = 0; this.mbase = 0;
    this.a_ = 0; this.f_ = 0; this.bc_ = 0; this.de_ = 0; this.hl_ = 0;
    this.halted = false; this.adl = false; this.madl = false;
    this.ief1 = false; this.ief2 = false; this.iefWait = false; this.im = 0;
    this.nmi = false;
    this.L = false; this.IL = false; this.suffixed = false; this.prefix = 0;
    this.instructionPC = 0;
    this.breakpointHit = false;
    this.lastUnsupported = null;
    this.unsupportedCount = 0;
  }

  setBreakpoints(list) {
    this.breakpoints = new Set(list);
  }

  triggerBreak() { this.breakpointHit = true; }

  // ---- Execution -----------------------------------------------------------

  /** Executes until the scheduler's stop point, a breakpoint, or HALT. */
  execute() {
    this.breakpointHit = false;
    const s = this.sched;
    const checkBreakpoints = this.breakpoints.size > 0;
    while (s.cycles < s.stopCycles) {
      const blockIRQ = this.iefWait;
      this.iefWait = false;
      if (this.nmi) {
        this.nmi = false;
        this.serviceNMI();
      } else if (this.irq && this.ief1 && !blockIRQ) {
        this.serviceIRQ();
      }
      if (this.halted) {
        s.cycles = s.stopCycles;      // fast-forward to the next event
        return;
      }
      if (checkBreakpoints) {
        if (!this.ignoreBreakpointOnce && this.breakpoints.has(this.pc)) {
          this.breakpointHit = true;
          return;
        }
        this.ignoreBreakpointOnce = false;
      }
      if (this.traceHook) {
        this.traceHook(this);
        if (this.breakpointHit) return;
      }
      this.step();
    }
  }

  step() {
    this.instructionPC = this.pc;
    this.L = this.adl; this.IL = this.adl; this.suffixed = false; this.prefix = 0;
    this.sched.cycles += 1;
    let op = this.fetchOpcode();
    for (;;) {
      if (op === 0xDD) { this.prefix = 2; op = this.fetchOpcode(); continue; }
      if (op === 0xFD) { this.prefix = 3; op = this.fetchOpcode(); continue; }
      if (this.prefix === 0) {
        if (op === 0x40) { this.L = false; this.IL = false; this.suffixed = true; op = this.fetchOpcode(); continue; }
        if (op === 0x49) { this.L = true; this.IL = false; this.suffixed = true; op = this.fetchOpcode(); continue; }
        if (op === 0x52) { this.L = false; this.IL = true; this.suffixed = true; op = this.fetchOpcode(); continue; }
        if (op === 0x5B) { this.L = true; this.IL = true; this.suffixed = true; op = this.fetchOpcode(); continue; }
      }
      break;
    }
    this.executeMain(op);
  }

  /** Debugger single step: services a due interrupt, else one instruction. */
  debugStep() {
    const blockIRQ = this.iefWait;
    this.iefWait = false;
    if (this.nmi) { this.nmi = false; this.serviceNMI(); return; }
    if (this.irq && this.ief1 && !blockIRQ) { this.serviceIRQ(); return; }
    if (this.halted) return;
    this.step();
  }

  // ---- Interrupts ----------------------------------------------------------

  serviceIRQ() {
    this.halted = false;
    this.ief1 = false;
    this.ief2 = false;
    this.sched.cycles += 2;
    let vector;
    if (this.im === 2) {
      this.L = this.adl || this.madl;
      vector = this.readWordAt(((this.i << 8) | 0xFF) >>> 0);
    } else {
      vector = 0x38;
    }
    this.interruptCall(vector);
  }

  serviceNMI() {
    this.halted = false;
    this.ief2 = this.ief1;
    this.ief1 = false;
    this.sched.cycles += 2;
    this.interruptCall(0x66);
  }

  interruptCall(vector) {
    this.suffixed = false; this.prefix = 0;
    if (this.madl) {
      this.L = true; this.IL = true;
      this.mixedCall(vector);
    } else {
      this.L = this.adl; this.IL = this.adl;
      this.push(this.pc);
      this.pc = this.mask(vector, this.adl);
    }
  }

  // ---- Width helpers -------------------------------------------------------

  mask(v, wide) { return wide ? v & 0xFFFFFF : v & 0xFFFF; }
  address(v, wide) { return wide ? v & 0xFFFFFF : (this.mbase << 16) | (v & 0xFFFF); }
  /** Value for a multi-byte register write: 16-bit writes zero the upper byte. */
  put(v) { return this.L ? v & 0xFFFFFF : v & 0xFFFF; }

  // ---- Fetch ---------------------------------------------------------------

  fetch() {
    const pc = this.pc;
    const v = this.bus.read(this.adl ? pc : (this.mbase << 16) | (pc & 0xFFFF));
    this.pc = this.adl ? (pc + 1) & 0xFFFFFF : (pc + 1) & 0xFFFF;
    return v;
  }

  fetchOpcode() {
    this.r = (this.r & 0x80) | ((this.r + 1) & 0x7F);
    return this.fetch();
  }

  fetchWord() {
    let v = this.fetch();
    v |= this.fetch() << 8;
    if (this.IL) v |= this.fetch() << 16;
    return v;
  }

  fetchDisplacement() { return (this.fetch() << 24) >> 24; }

  // ---- Data memory (width L) -----------------------------------------------

  readByte(a) { return this.bus.read(this.address(a, this.L)); }
  writeByte(a, v) { this.bus.write(this.address(a, this.L), v & 0xFF); }

  readWordAt(a) {
    let v = this.readByte(a);
    v |= this.readByte(a + 1) << 8;
    if (this.L) v |= this.readByte(a + 2) << 16;
    return v;
  }

  writeWordAt(a, v) {
    this.writeByte(a, v);
    this.writeByte(a + 1, v >> 8);
    if (this.L) this.writeByte(a + 2, v >> 16);
  }

  // ---- Stack ---------------------------------------------------------------

  pushByte(v, long) {
    if (long) {
      this.spl = (this.spl - 1) & 0xFFFFFF;
      this.bus.write(this.spl, v & 0xFF);
    } else {
      this.sps = (this.sps - 1) & 0xFFFF;
      this.bus.write((this.mbase << 16) | this.sps, v & 0xFF);
    }
  }

  popByte(long) {
    if (long) {
      const v = this.bus.read(this.spl);
      this.spl = (this.spl + 1) & 0xFFFFFF;
      return v;
    }
    const v = this.bus.read((this.mbase << 16) | this.sps);
    this.sps = (this.sps + 1) & 0xFFFF;
    return v;
  }

  push(v) {
    if (this.L) this.pushByte(v >> 16, true);
    this.pushByte(v >> 8, this.L);
    this.pushByte(v, this.L);
  }

  pop() {
    let v = this.popByte(this.L);
    v |= this.popByte(this.L) << 8;
    if (this.L) v |= this.popByte(this.L) << 16;
    return v;
  }

  getSP() { return this.L ? this.spl : this.sps; }
  setSP(v) { if (this.L) this.spl = v & 0xFFFFFF; else this.sps = v & 0xFFFF; }

  // ---- Control flow --------------------------------------------------------

  jump(target, wide) {
    this.adl = wide;
    this.pc = wide ? target & 0xFFFFFF : target & 0xFFFF;
  }

  call(target) {
    if (this.suffixed) {
      this.mixedCall(target);
    } else {
      this.push(this.pc);
      this.jump(target, this.IL);
    }
  }

  /** eZ80 mixed-memory-mode call: return address on SPL or SPS, plus a mode byte. */
  mixedCall(target) {
    const pc = this.pc;
    const longStack = this.IL || (this.L && !this.adl);
    if (this.adl) this.pushByte(pc >> 16, true);
    this.pushByte(pc >> 8, longStack);
    this.pushByte(pc, longStack);
    this.pushByte((this.madl ? 2 : 0) | (this.adl ? 1 : 0), true);
    this.jump(target, this.IL);
  }

  ret() {
    if (this.suffixed) {
      const wasADL = (this.popByte(true) & 1) !== 0;
      let target;
      if (this.adl) {
        target = this.popByte(true);
        target |= this.popByte(true) << 8;
        if (wasADL) target |= this.popByte(true) << 16;
      } else {
        target = this.popByte(false);
        target |= this.popByte(false) << 8;
        if (wasADL) target |= this.popByte(true) << 16;
      }
      this.jump(target, wasADL);
    } else {
      this.jump(this.pop(), this.adl);
    }
  }

  // ---- I/O -----------------------------------------------------------------

  portIn(port) {
    this.sched.cycles += 2;
    return this.io.read(port & 0xFFFF);
  }

  portOut(port, v) {
    this.sched.cycles += 2;
    this.io.write(port & 0xFFFF, v & 0xFF);
  }

  unsupported(bytes) {
    const pc = this.instructionPC.toString(16).toUpperCase().padStart(6, '0');
    const msg = `Unsupported opcode: ${bytes.map(hex2).join(' ')}\nPC: 0x${pc} (ADL=${this.adl ? 1 : 0})`;
    this.lastUnsupported = msg;
    this.unsupportedCount++;
    if (this.onUnsupported) this.onUnsupported(msg);
  }

  // ---- 8-bit register halves -----------------------------------------------

  get b() { return (this.bc >> 8) & 0xFF; }
  set b(v) { this.bc = (this.bc & 0xFF00FF) | ((v & 0xFF) << 8); }
  get c() { return this.bc & 0xFF; }
  set c(v) { this.bc = (this.bc & 0xFFFF00) | (v & 0xFF); }
  get d() { return (this.de >> 8) & 0xFF; }
  set d(v) { this.de = (this.de & 0xFF00FF) | ((v & 0xFF) << 8); }
  get e() { return this.de & 0xFF; }
  set e(v) { this.de = (this.de & 0xFFFF00) | (v & 0xFF); }
  get h() { return (this.hl >> 8) & 0xFF; }
  set h(v) { this.hl = (this.hl & 0xFF00FF) | ((v & 0xFF) << 8); }
  get l() { return this.hl & 0xFF; }
  set l(v) { this.hl = (this.hl & 0xFFFF00) | (v & 0xFF); }
  get af() { return (this.a << 8) | this.f; }
  set af(v) { this.a = (v >> 8) & 0xFF; this.f = v & 0xFF; }

  // ---- Operand helpers -----------------------------------------------------

  /** HL, IX or IY according to the prefix (width L). */
  get index() {
    const v = this.prefix === 0 ? this.hl : (this.prefix === 2 ? this.ix : this.iy);
    return this.L ? v & 0xFFFFFF : v & 0xFFFF;
  }

  setIndex(v) {
    v = this.put(v);
    if (this.prefix === 0) this.hl = v;
    else if (this.prefix === 2) this.ix = v;
    else this.iy = v;
  }

  /** The index register not selected by the prefix (IY for DD, IX for FD). */
  getOtherIndex() { return this.mask(this.prefix === 3 ? this.ix : this.iy, this.L); }
  setOtherIndex(v) { if (this.prefix === 3) this.ix = this.put(v); else this.iy = this.put(v); }

  /** (HL) / (IX+d) / (IY+d) effective address (fetches d when prefixed). */
  indexAddress() {
    if (this.prefix === 0) return this.mask(this.hl, this.L);
    return this.mask(this.index + this.fetchDisplacement(), this.L);
  }

  reg(i) {
    switch (i) {
      case 0: return (this.bc >> 8) & 0xFF;
      case 1: return this.bc & 0xFF;
      case 2: return (this.de >> 8) & 0xFF;
      case 3: return this.de & 0xFF;
      case 4: return ((this.prefix === 0 ? this.hl : this.prefix === 2 ? this.ix : this.iy) >> 8) & 0xFF;
      case 5: return (this.prefix === 0 ? this.hl : this.prefix === 2 ? this.ix : this.iy) & 0xFF;
      default: return this.a;
    }
  }

  setReg(i, v) {
    v &= 0xFF;
    switch (i) {
      case 0: this.b = v; break;
      case 1: this.c = v; break;
      case 2: this.d = v; break;
      case 3: this.e = v; break;
      case 4:
        if (this.prefix === 0) this.hl = (this.hl & 0xFF00FF) | (v << 8);
        else if (this.prefix === 2) this.ix = (this.ix & 0xFF00FF) | (v << 8);
        else this.iy = (this.iy & 0xFF00FF) | (v << 8);
        break;
      case 5:
        if (this.prefix === 0) this.hl = (this.hl & 0xFFFF00) | v;
        else if (this.prefix === 2) this.ix = (this.ix & 0xFFFF00) | v;
        else this.iy = (this.iy & 0xFFFF00) | v;
        break;
      default: this.a = v;
    }
  }

  regPlain(i) {
    switch (i) {
      case 0: return (this.bc >> 8) & 0xFF;
      case 1: return this.bc & 0xFF;
      case 2: return (this.de >> 8) & 0xFF;
      case 3: return this.de & 0xFF;
      case 4: return (this.hl >> 8) & 0xFF;
      case 5: return this.hl & 0xFF;
      default: return this.a;
    }
  }

  setRegPlain(i, v) {
    v &= 0xFF;
    switch (i) {
      case 0: this.b = v; break;
      case 1: this.c = v; break;
      case 2: this.d = v; break;
      case 3: this.e = v; break;
      case 4: this.h = v; break;
      case 5: this.l = v; break;
      default: this.a = v;
    }
  }

  rp(p) {
    switch (p) {
      case 0: return this.mask(this.bc, this.L);
      case 1: return this.mask(this.de, this.L);
      case 2: return this.index;
      default: return this.getSP();
    }
  }

  setRP(p, v) {
    switch (p) {
      case 0: this.bc = this.put(v); break;
      case 1: this.de = this.put(v); break;
      case 2: this.setIndex(v); break;
      default: this.setSP(v);
    }
  }

  rp3(p) {
    switch (p) {
      case 0: return this.mask(this.bc, this.L);
      case 1: return this.mask(this.de, this.L);
      case 2: return this.mask(this.hl, this.L);
      default: return this.index;
    }
  }

  setRP3(p, v) {
    switch (p) {
      case 0: this.bc = this.put(v); break;
      case 1: this.de = this.put(v); break;
      case 2: this.hl = this.put(v); break;
      default: this.setIndex(v);
    }
  }

  condition(y) {
    const f = this.f;
    switch (y) {
      case 0: return (f & FZ) === 0;
      case 1: return (f & FZ) !== 0;
      case 2: return (f & FC) === 0;
      case 3: return (f & FC) !== 0;
      case 4: return (f & FPV) === 0;
      case 5: return (f & FPV) !== 0;
      case 6: return (f & FS) === 0;
      default: return (f & FS) !== 0;
    }
  }

  // ---- ALU -----------------------------------------------------------------

  alu(op, v) {
    switch (op) {
      case 0: this.add8(v, 0); break;
      case 1: this.add8(v, this.f & FC); break;
      case 2: this.a = this.sub8(v, 0); break;
      case 3: this.a = this.sub8(v, this.f & FC); break;
      case 4: this.a &= v; this.f = SZP[this.a] | FH; break;
      case 5: this.a ^= v; this.f = SZP[this.a]; break;
      case 6: this.a |= v; this.f = SZP[this.a]; break;
      default:
        this.sub8(v, 0);
        this.f = (this.f & ~(FX | FY)) | (v & (FX | FY));
    }
  }

  add8(v, carry) {
    const a = this.a;
    const res = a + v + carry;
    const r8 = res & 0xFF;
    let f = r8 & (FS | FX | FY);
    if (r8 === 0) f |= FZ;
    if ((a ^ v ^ r8) & 0x10) f |= FH;
    if ((a ^ r8) & (v ^ r8) & 0x80) f |= FPV;
    if (res > 0xFF) f |= FC;
    this.a = r8;
    this.f = f;
  }

  sub8(v, carry) {
    const a = this.a;
    const res = a - v - carry;
    const r8 = res & 0xFF;
    let f = (r8 & (FS | FX | FY)) | FN;
    if (r8 === 0) f |= FZ;
    if ((a ^ v ^ r8) & 0x10) f |= FH;
    if ((a ^ v) & (a ^ r8) & 0x80) f |= FPV;
    if (res < 0) f |= FC;
    this.f = f;
    return r8;
  }

  inc8(v) {
    const res = (v + 1) & 0xFF;
    let f = (this.f & FC) | (res & (FS | FX | FY));
    if (res === 0) f |= FZ;
    if ((res & 0x0F) === 0) f |= FH;
    if (v === 0x7F) f |= FPV;
    this.f = f;
    return res;
  }

  dec8(v) {
    const res = (v - 1) & 0xFF;
    let f = (this.f & FC) | FN | (res & (FS | FX | FY));
    if (res === 0) f |= FZ;
    if ((v & 0x0F) === 0) f |= FH;
    if (v === 0x80) f |= FPV;
    this.f = f;
    return res;
  }

  addWide(a, b) {
    const res = a + b;
    const top = this.L ? 0xFFFFFF : 0xFFFF;
    let f = this.f & (FS | FZ | FPV);
    if ((a & 0xFFF) + (b & 0xFFF) > 0xFFF) f |= FH;
    if (res > top) f |= FC;
    f |= (res >> 8) & (FX | FY);
    this.f = f;
    return res & top;
  }

  adcWide(a, b) {
    const c = (this.f & FC) ? 1 : 0;
    const top = this.L ? 0xFFFFFF : 0xFFFF;
    const sign = this.L ? 0x800000 : 0x8000;
    const full = a + b + c;
    const res = full & top;
    let f = 0;
    if (res & sign) f |= FS;
    if (res === 0) f |= FZ;
    if ((a & 0xFFF) + (b & 0xFFF) + c > 0xFFF) f |= FH;
    if ((a ^ res) & (b ^ res) & sign) f |= FPV;
    if (full > top) f |= FC;
    this.f = f;
    return res;
  }

  sbcWide(a, b) {
    const c = (this.f & FC) ? 1 : 0;
    const top = this.L ? 0xFFFFFF : 0xFFFF;
    const sign = this.L ? 0x800000 : 0x8000;
    const full = a - b - c;
    const res = full & top;
    let f = FN;
    if (res & sign) f |= FS;
    if (res === 0) f |= FZ;
    if ((a & 0xFFF) - (b & 0xFFF) - c < 0) f |= FH;
    if ((a ^ b) & (a ^ res) & sign) f |= FPV;
    if (full < 0) f |= FC;
    this.f = f;
    return res;
  }

  rotate(op, v) {
    const cin = this.f & FC;
    let res, cout;
    switch (op) {
      case 0: cout = v >> 7; res = (v << 1) | cout; break;            // RLC
      case 1: cout = v & 1; res = (v >> 1) | (cout << 7); break;      // RRC
      case 2: cout = v >> 7; res = (v << 1) | cin; break;             // RL
      case 3: cout = v & 1; res = (v >> 1) | (cin << 7); break;       // RR
      case 4: cout = v >> 7; res = v << 1; break;                     // SLA
      case 5: cout = v & 1; res = (v >> 1) | (v & 0x80); break;       // SRA
      case 6: cout = v >> 7; res = (v << 1) | 1; break;               // SLL
      default: cout = v & 1; res = v >> 1;                            // SRL
    }
    res &= 0xFF;
    this.f = SZP[res] | cout;
    return res;
  }

  daa() {
    let a = this.a;
    const f = this.f;
    let correction = 0;
    let carry = f & FC;
    if ((f & FH) || (a & 0x0F) > 9) correction |= 0x06;
    if (carry || a > 0x99) { correction |= 0x60; carry = FC; }
    const old = a;
    a = (f & FN) ? (a - correction) & 0xFF : (a + correction) & 0xFF;
    let nf = SZP[a] | carry | (f & FN);
    if ((old ^ a) & 0x10) nf |= FH;
    this.a = a;
    this.f = nf;
  }

  // ---- Main opcode table ---------------------------------------------------

  executeMain(op) {
    switch (op) {
      case 0x00: break;
      case 0x08: { const a = this.a, f = this.f; this.a = this.a_; this.f = this.f_; this.a_ = a; this.f_ = f; break; }
      case 0x10: {                                                     // DJNZ
        const d = this.fetchDisplacement();
        this.b = (this.b - 1) & 0xFF;
        if (this.b !== 0) { this.pc = this.mask(this.pc + d, this.adl); this.sched.cycles += 1; }
        break;
      }
      case 0x18: this.jr(true); break;
      case 0x20: case 0x28: case 0x30: case 0x38: this.jr(this.condition((op >> 3) & 3)); break;
      case 0x01: case 0x11: case 0x21: this.setRP(op >> 4, this.fetchWord()); break;
      case 0x31:
        if (this.prefix !== 0) { const a = this.indexAddress(); this.setOtherIndex(this.readWordAt(a)); }
        else this.setSP(this.fetchWord());
        break;
      case 0x09: case 0x19: case 0x29: case 0x39: this.setIndex(this.addWide(this.index, this.rp(op >> 4))); break;
      case 0x02: this.writeByte(this.mask(this.bc, this.L), this.a); break;
      case 0x12: this.writeByte(this.mask(this.de, this.L), this.a); break;
      case 0x22: { const a = this.fetchWord(); this.writeWordAt(a, this.index); break; }
      case 0x32: { const a = this.fetchWord(); this.writeByte(a, this.a); break; }
      case 0x0A: this.a = this.readByte(this.mask(this.bc, this.L)); break;
      case 0x1A: this.a = this.readByte(this.mask(this.de, this.L)); break;
      case 0x2A: this.setIndex(this.readWordAt(this.fetchWord())); break;
      case 0x3A: this.a = this.readByte(this.fetchWord()); break;
      case 0x03: case 0x13: case 0x23: case 0x33: this.setRP(op >> 4, this.rp(op >> 4) + 1); break;
      case 0x0B: case 0x1B: case 0x2B: case 0x3B: this.setRP(op >> 4, this.rp(op >> 4) - 1); break;
      case 0x34: { const a = this.indexAddress(); this.writeByte(a, this.inc8(this.readByte(a))); break; }
      case 0x35: { const a = this.indexAddress(); this.writeByte(a, this.dec8(this.readByte(a))); break; }
      case 0x04: case 0x0C: case 0x14: case 0x1C: case 0x24: case 0x2C: case 0x3C: {
        const y = (op >> 3) & 7; this.setReg(y, this.inc8(this.reg(y))); break;
      }
      case 0x05: case 0x0D: case 0x15: case 0x1D: case 0x25: case 0x2D: case 0x3D: {
        const y = (op >> 3) & 7; this.setReg(y, this.dec8(this.reg(y))); break;
      }
      case 0x36: { const a = this.indexAddress(); this.writeByte(a, this.fetch()); break; }
      case 0x3E:
        if (this.prefix !== 0) { const a = this.indexAddress(); this.writeWordAt(a, this.getOtherIndex()); }
        else this.a = this.fetch();
        break;
      case 0x06: case 0x0E: case 0x16: case 0x1E: case 0x26: case 0x2E: this.setReg((op >> 3) & 7, this.fetch()); break;
      case 0x07: case 0x0F: case 0x17: case 0x1F: case 0x27: case 0x2F: case 0x37: case 0x3F:
        if (this.prefix !== 0) this.indexedWideLoad(op); else this.accumulatorOp(op);
        break;
      case 0x76: this.halted = true; break;
      case 0xC0: case 0xC8: case 0xD0: case 0xD8: case 0xE0: case 0xE8: case 0xF0: case 0xF8:
        this.sched.cycles += 1;
        if (this.condition((op >> 3) & 7)) this.ret();
        break;
      case 0xC1: this.bc = this.put(this.pop()); break;
      case 0xD1: this.de = this.put(this.pop()); break;
      case 0xE1: this.setIndex(this.pop()); break;
      case 0xF1: this.af = this.pop() & 0xFFFF; break;
      case 0xC9: this.ret(); break;
      case 0xD9: {
        const bc = this.bc, de = this.de, hl = this.hl;
        this.bc = this.bc_; this.de = this.de_; this.hl = this.hl_;
        this.bc_ = bc; this.de_ = de; this.hl_ = hl;
        break;
      }
      case 0xE9: this.jump(this.index, this.L); break;
      case 0xF9: this.setSP(this.index); break;
      case 0xC2: case 0xCA: case 0xD2: case 0xDA: case 0xE2: case 0xEA: case 0xF2: case 0xFA: {
        const t = this.fetchWord();
        if (this.condition((op >> 3) & 7)) this.jump(t, this.IL);
        break;
      }
      case 0xC3: this.jump(this.fetchWord(), this.IL); break;
      case 0xCB: this.executeCB(); break;
      case 0xD3: { const n = this.fetch(); this.portOut((this.a << 8) | n, this.a); break; }
      case 0xDB: { const n = this.fetch(); this.a = this.portIn((this.a << 8) | n); break; }
      case 0xE3: {
        const s = this.getSP();
        const v = this.readWordAt(s);
        this.writeWordAt(s, this.index);
        this.setIndex(v);
        break;
      }
      case 0xEB: {
        const d = this.de, h = this.hl;
        if (this.L) { this.de = h; this.hl = d; } else { this.de = this.put(h); this.hl = this.put(d); }
        break;
      }
      case 0xF3: this.ief1 = false; this.ief2 = false; break;
      case 0xFB: this.ief1 = true; this.ief2 = true; this.iefWait = true; break;
      case 0xC4: case 0xCC: case 0xD4: case 0xDC: case 0xE4: case 0xEC: case 0xF4: case 0xFC: {
        const t = this.fetchWord();
        if (this.condition((op >> 3) & 7)) this.call(t);
        break;
      }
      case 0xC5: this.push(this.mask(this.bc, this.L)); break;
      case 0xD5: this.push(this.mask(this.de, this.L)); break;
      case 0xE5: this.push(this.index); break;
      case 0xF5: this.push(this.af); break;
      case 0xCD: this.call(this.fetchWord()); break;
      case 0xED: this.executeED(); break;
      case 0xC6: case 0xCE: case 0xD6: case 0xDE: case 0xE6: case 0xEE: case 0xF6: case 0xFE:
        this.alu((op >> 3) & 7, this.fetch());
        break;
      case 0xC7: case 0xCF: case 0xD7: case 0xDF: case 0xE7: case 0xEF: case 0xF7: case 0xFF:
        this.call(op & 0x38);
        break;
      default:
        if (op >= 0x40 && op <= 0x7F) {                                // LD r,r'
          const y = (op >> 3) & 7, z = op & 7;
          if (z === 6) this.setRegPlain(y, this.readByte(this.indexAddress()));
          else if (y === 6) { const a = this.indexAddress(); this.writeByte(a, this.regPlain(z)); }
          else this.setReg(y, this.reg(z));
        } else if (op >= 0x80 && op <= 0xBF) {                         // ALU A,r
          const z = op & 7;
          this.alu((op >> 3) & 7, z === 6 ? this.readByte(this.indexAddress()) : this.reg(z));
        } else {
          this.unsupported([op]);
        }
    }
  }

  jr(taken) {
    const d = this.fetchDisplacement();
    if (taken) { this.pc = this.mask(this.pc + d, this.adl); this.sched.cycles += 1; }
  }

  accumulatorOp(op) {
    const a = this.a;
    const keep = this.f & (FS | FZ | FPV);
    switch (op) {
      case 0x07: { const c = a >> 7; this.a = ((a << 1) | c) & 0xFF; this.f = keep | c | (this.a & (FX | FY)); break; }
      case 0x0F: { const c = a & 1; this.a = ((a >> 1) | (c << 7)) & 0xFF; this.f = keep | c | (this.a & (FX | FY)); break; }
      case 0x17: { const c = a >> 7; this.a = ((a << 1) | (this.f & FC)) & 0xFF; this.f = keep | c | (this.a & (FX | FY)); break; }
      case 0x1F: { const c = a & 1; this.a = ((a >> 1) | ((this.f & FC) << 7)) & 0xFF; this.f = keep | c | (this.a & (FX | FY)); break; }
      case 0x27: this.daa(); break;
      case 0x2F:
        this.a = (~a) & 0xFF;
        this.f = (this.f & (FS | FZ | FPV | FC)) | FH | FN | (this.a & (FX | FY));
        break;
      case 0x37: this.f = keep | FC | (a & (FX | FY)); break;
      default: { const c = this.f & FC; this.f = keep | (c ? FH : FC) | (a & (FX | FY)); }
    }
  }

  indexedWideLoad(op) {
    const y = (op >> 3) & 7;
    const p = y >> 1;
    const a = this.indexAddress();
    if ((y & 1) === 0) this.setRP3(p, this.readWordAt(a));
    else this.writeWordAt(a, this.rp3(p));
  }

  // ---- CB prefix -----------------------------------------------------------

  executeCB() {
    let addr = -1, op;
    if (this.prefix !== 0) {
      addr = this.indexAddress();
      op = this.fetch();
    } else {
      op = this.fetchOpcode();
      if ((op & 7) === 6) addr = this.mask(this.hl, this.L);
    }
    const x = op >> 6, y = (op >> 3) & 7, z = op & 7;
    const pre = this.prefix === 2 ? 0xDD : 0xFD;
    if (this.prefix !== 0 && z !== 6) this.unsupported([pre, 0xCB, op]);
    if (x === 0 && y === 6) this.unsupported(this.prefix !== 0 ? [pre, 0xCB, op] : [0xCB, op]);
    const v = addr >= 0 ? this.readByte(addr) : this.regPlain(z);
    switch (x) {
      case 0: {
        const res = this.rotate(y, v);
        if (addr >= 0) this.writeByte(addr, res); else this.setRegPlain(z, res);
        break;
      }
      case 1: {
        const bit = v & (1 << y);
        let f = (this.f & FC) | FH | (v & (FX | FY));
        if (bit === 0) f |= FZ | FPV;
        if (y === 7 && bit !== 0) f |= FS;
        this.f = f;
        break;
      }
      case 2: {
        const res = v & ~(1 << y) & 0xFF;
        if (addr >= 0) this.writeByte(addr, res); else this.setRegPlain(z, res);
        break;
      }
      default: {
        const res = (v | (1 << y)) & 0xFF;
        if (addr >= 0) this.writeByte(addr, res); else this.setRegPlain(z, res);
      }
    }
  }

  // ---- ED prefix -----------------------------------------------------------

  executeED() {
    const op = this.fetchOpcode();
    this.prefix = 0;
    const x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
    switch (x) {
      case 0: this.executeED0(op, y, z); break;
      case 1: this.executeED1(op, y, z, p, q); break;
      case 2: this.executeBlock(op); break;
      default:
        switch (op) {
          case 0xC2: this.blockIOX(true, 1); break;
          case 0xC3: this.blockIOX(false, 1); break;
          case 0xCA: this.blockIOX(true, -1); break;
          case 0xCB: this.blockIOX(false, -1); break;
          case 0xC7: this.i = this.hl & 0xFFFF; break;                   // LD I,HL
          case 0xD7:                                                     // LD HL,I
            this.hl = this.put(this.i);
            if (this.L) this.hl = (this.mbase << 16) | this.i;
            break;
          default: this.unsupported([0xED, op]);
        }
    }
  }

  executeED0(op, y, z) {
    switch (z) {
      case 0: {                                                          // IN0 r,(n)
        const n = this.fetch();
        const v = this.portIn(n);
        this.f = (this.f & FC) | SZP[v];
        if (y !== 6) this.setRegPlain(y, v);
        break;
      }
      case 1:
        if (y === 6) this.iy = this.put(this.readWordAt(this.mask(this.hl, this.L)));   // LD IY,(HL)
        else { const n = this.fetch(); this.portOut(n, this.regPlain(y)); }            // OUT0 (n),r
        break;
      case 2: case 3:
        if ((y & 1) === 0) {                                             // LEA rr,IX/IY+d
          const base = z === 2 ? this.ix : this.iy;
          const v = this.put(this.mask(base + this.fetchDisplacement(), this.L));
          switch (y >> 1) {
            case 0: this.bc = v; break;
            case 1: this.de = v; break;
            case 2: this.hl = v; break;
            default: if (z === 2) this.ix = v; else this.iy = v;
          }
        } else this.unsupported([0xED, op]);
        break;
      case 4: {                                                          // TST A,r
        const v = y === 6 ? this.readByte(this.mask(this.hl, this.L)) : this.regPlain(y);
        this.f = SZP[this.a & v] | FH;
        break;
      }
      case 6:
        if (y === 7) this.writeWordAt(this.mask(this.hl, this.L), this.mask(this.iy, this.L));   // LD (HL),IY
        else this.unsupported([0xED, op]);
        break;
      case 7: {
        const p = y >> 1;
        const a = this.mask(this.hl, this.L);
        if ((y & 1) === 0) {                                             // LD rr,(HL)
          const v = this.put(this.readWordAt(a));
          switch (p) {
            case 0: this.bc = v; break;
            case 1: this.de = v; break;
            case 2: this.hl = v; break;
            default: this.ix = v;
          }
        } else {                                                         // LD (HL),rr
          const v = p === 0 ? this.bc : p === 1 ? this.de : p === 2 ? this.hl : this.ix;
          this.writeWordAt(a, this.mask(v, this.L));
        }
        break;
      }
      default: this.unsupported([0xED, op]);
    }
  }

  executeED1(op, y, z, p, q) {
    switch (z) {
      case 0: {                                                          // IN r,(C)
        const v = this.portIn(this.bc & 0xFFFF);
        this.f = (this.f & FC) | SZP[v];
        if (y !== 6) this.setRegPlain(y, v);
        break;
      }
      case 1:                                                            // OUT (C),r
        if (y === 6) { this.unsupported([0xED, op]); return; }
        this.portOut(this.bc & 0xFFFF, this.regPlain(y));
        break;
      case 2: {                                                          // SBC/ADC HL,rp
        const hl = this.mask(this.hl, this.L);
        const v = p === 0 ? this.mask(this.bc, this.L) : p === 1 ? this.mask(this.de, this.L) : p === 2 ? hl : this.getSP();
        this.hl = this.put(q === 0 ? this.sbcWide(hl, v) : this.adcWide(hl, v));
        break;
      }
      case 3: {
        const a = this.fetchWord();
        if (q === 0) {                                                   // LD (nn),rp
          const v = p === 0 ? this.mask(this.bc, this.L) : p === 1 ? this.mask(this.de, this.L)
            : p === 2 ? this.mask(this.hl, this.L) : this.getSP();
          this.writeWordAt(a, v);
        } else {                                                         // LD rp,(nn)
          const v = this.readWordAt(a);
          switch (p) {
            case 0: this.bc = this.put(v); break;
            case 1: this.de = this.put(v); break;
            case 2: this.hl = this.put(v); break;
            default: this.setSP(v);
          }
        }
        break;
      }
      case 4:
        switch (y) {
          case 0: { const a = this.a; this.a = 0; this.a = this.sub8(a, 0); break; }   // NEG
          case 1: case 3: case 5: case 7:                                // MLT rr
            switch (p) {
              case 0: this.bc = this.put(this.b * this.c); break;
              case 1: this.de = this.put(this.d * this.e); break;
              case 2: this.hl = this.put(this.h * this.l); break;
              default: { const s = this.getSP(); this.setSP(((s >> 8) & 0xFF) * (s & 0xFF)); }
            }
            this.sched.cycles += 4;
            break;
          case 2: this.ix = this.put(this.mask(this.iy + this.fetchDisplacement(), this.L)); break;  // LEA IX,IY+d
          case 4: this.f = SZP[this.a & this.fetch()] | FH; break;      // TST A,n
          case 6: {                                                      // TSTIO n
            const n = this.fetch();
            const v = this.portIn(this.c);
            this.f = SZP[v & n] | FH;
            break;
          }
          default: this.unsupported([0xED, op]);
        }
        break;
      case 5:
        switch (y) {
          case 0: this.ret(); this.ief1 = this.ief2; break;              // RETN
          case 1: this.ret(); this.ief1 = this.ief2; break;              // RETI
          case 2: this.iy = this.put(this.mask(this.ix + this.fetchDisplacement(), this.L)); break; // LEA IY,IX+d
          case 4: this.push(this.mask(this.ix + this.fetchDisplacement(), this.L)); break;          // PEA IX+d
          case 5: if (this.adl) this.mbase = this.a; break;              // LD MB,A
          case 7: this.madl = true; break;                               // STMIX
          default: this.unsupported([0xED, op]);
        }
        break;
      case 6:
        switch (y) {
          case 0: this.im = 0; break;
          case 2: this.im = 1; break;
          case 3: this.im = 2; break;
          case 4: this.push(this.mask(this.iy + this.fetchDisplacement(), this.L)); break;          // PEA IY+d
          case 5: this.a = this.mbase; break;                            // LD A,MB
          case 6: this.halted = true; break;                             // SLP
          case 7: this.madl = false; break;                              // RSMIX
          default: this.unsupported([0xED, op]);
        }
        break;
      default:
        switch (y) {
          case 0: this.i = (this.i & 0xFF00) | this.a; break;            // LD I,A
          case 1: this.r = this.a; break;                                // LD R,A
          case 2: case 3:                                                // LD A,I / LD A,R
            this.a = y === 2 ? this.i & 0xFF : this.r;
            this.f = (this.f & FC) | (SZP[this.a] & ~FPV) | (this.ief2 ? FPV : 0);
            break;
          case 4: {                                                      // RRD
            const a = this.mask(this.hl, this.L);
            const m = this.readByte(a);
            this.writeByte(a, ((this.a << 4) | (m >> 4)) & 0xFF);
            this.a = (this.a & 0xF0) | (m & 0x0F);
            this.f = (this.f & FC) | SZP[this.a];
            break;
          }
          case 5: {                                                      // RLD
            const a = this.mask(this.hl, this.L);
            const m = this.readByte(a);
            this.writeByte(a, ((m << 4) | (this.a & 0x0F)) & 0xFF);
            this.a = (this.a & 0xF0) | (m >> 4);
            this.f = (this.f & FC) | SZP[this.a];
            break;
          }
          default: this.unsupported([0xED, op]);
        }
    }
  }

  // ---- Block instructions --------------------------------------------------

  stepHL(d) { this.hl = this.put(d > 0 ? this.hl + 1 : this.hl - 1); }
  stepDE(d) { this.de = this.put(d > 0 ? this.de + 1 : this.de - 1); }

  repeatInstruction() {
    this.pc = this.instructionPC;
    this.sched.cycles += 1;
  }

  executeBlock(op) {
    const d = (op & 0x08) === 0 ? 1 : -1;
    switch (op) {
      case 0xA0: case 0xA8: case 0xB0: case 0xB8: {                      // LDI/LDD/LDIR/LDDR
        const v = this.readByte(this.mask(this.hl, this.L));
        this.writeByte(this.mask(this.de, this.L), v);
        this.stepHL(d); this.stepDE(d);
        this.bc = this.put(this.mask(this.bc, this.L) - 1);
        const nz = this.mask(this.bc, this.L) !== 0;
        const n = (this.a + v) & 0xFF;
        this.f = (this.f & (FS | FZ | FC)) | (nz ? FPV : 0) | (n & FX) | ((n << 4) & FY);
        if (op >= 0xB0 && nz) this.repeatInstruction();
        break;
      }
      case 0xA1: case 0xA9: case 0xB1: case 0xB9: {                      // CPI/CPD/CPIR/CPDR
        const v = this.readByte(this.mask(this.hl, this.L));
        const c = this.f & FC;
        this.sub8(v, 0);
        this.stepHL(d);
        this.bc = this.put(this.mask(this.bc, this.L) - 1);
        const nz = this.mask(this.bc, this.L) !== 0;
        this.f = (this.f & ~(FPV | FC)) | c | (nz ? FPV : 0);
        if (op >= 0xB0 && nz && (this.f & FZ) === 0) this.repeatInstruction();
        break;
      }
      case 0xA2: case 0xAA: case 0xB2: case 0xBA: {                      // INI/IND/INIR/INDR
        const v = this.portIn(this.bc & 0xFFFF);
        this.writeByte(this.mask(this.hl, this.L), v);
        this.stepHL(d);
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0xB0 && this.b !== 0) this.repeatInstruction();
        break;
      }
      case 0xA3: case 0xAB: case 0xB3: case 0xBB: {                      // OUTI/OUTD/OTIR/OTDR
        const v = this.readByte(this.mask(this.hl, this.L));
        this.portOut(this.bc & 0xFFFF, v);
        this.stepHL(d);
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0xB0 && this.b !== 0) this.repeatInstruction();
        break;
      }
      case 0x82: case 0x8A: case 0x92: case 0x9A: {                      // INIM/INDM/INIMR/INDMR
        const v = this.portIn(this.c);
        this.writeByte(this.mask(this.hl, this.L), v);
        this.stepHL(d);
        this.c = (this.c + d) & 0xFF;
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0x90 && this.b !== 0) this.repeatInstruction();
        break;
      }
      case 0x83: case 0x8B: case 0x93: case 0x9B: {                      // OTIM/OTDM/OTIMR/OTDMR
        const v = this.readByte(this.mask(this.hl, this.L));
        this.portOut(this.c, v);
        this.stepHL(d);
        this.c = (this.c + d) & 0xFF;
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0x90 && this.b !== 0) this.repeatInstruction();
        break;
      }
      case 0x84: case 0x8C: case 0x94: case 0x9C: {                      // INI2/IND2/INI2R/IND2R
        const v = this.portIn(this.bc & 0xFFFF);
        this.writeByte(this.mask(this.hl, this.L), v);
        this.stepHL(d);
        this.c = (this.c + d) & 0xFF;
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0x90 && this.b !== 0) this.repeatInstruction();
        break;
      }
      case 0xA4: case 0xAC: case 0xB4: case 0xBC: {                      // OUTI2/OUTD2/OTI2R/OTD2R
        const v = this.readByte(this.mask(this.hl, this.L));
        this.portOut(this.bc & 0xFFFF, v);
        this.stepHL(d);
        this.c = (this.c + d) & 0xFF;
        this.b = (this.b - 1) & 0xFF;
        this.blockIOFlags(v);
        if (op >= 0xB0 && this.b !== 0) this.repeatInstruction();
        break;
      }
      default: this.unsupported([0xED, op]);
    }
  }

  /** INIRX / OTIRX / INDRX / OTDRX: port {D,E}, 24-bit BC counter. */
  blockIOX(input, d) {
    const port = this.de & 0xFFFF;
    if (input) this.writeByte(this.mask(this.hl, this.L), this.portIn(port));
    else this.portOut(port, this.readByte(this.mask(this.hl, this.L)));
    this.stepHL(d);
    this.bc = this.put(this.mask(this.bc, this.L) - 1);
    const done = this.mask(this.bc, this.L) === 0;
    this.f = (this.f & ~(FZ | FN)) | (done ? FZ : 0) | FN;
    if (!done) this.repeatInstruction();
  }

  blockIOFlags(v) {
    let f = this.f & ~(FZ | FN | FS);
    const b = this.b;
    if (b === 0) f |= FZ;
    if (b & 0x80) f |= FS;
    if (v & 0x80) f |= FN;
    this.f = f;
  }

  // ---- State ---------------------------------------------------------------

  static stateKeys = ['a', 'f', 'bc', 'de', 'hl', 'ix', 'iy', 'sps', 'spl', 'pc', 'i', 'r', 'mbase',
    'a_', 'f_', 'bc_', 'de_', 'hl_', 'halted', 'adl', 'madl', 'ief1', 'ief2', 'iefWait', 'im'];

  saveState() {
    const s = {};
    for (const k of CPU.stateKeys) s[k] = this[k];
    return s;
  }

  loadState(s) {
    for (const k of CPU.stateKeys) if (k in s) this[k] = s[k];
  }
}
