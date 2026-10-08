// Page logic: builds the keypad, forwards input to the emulation runner (in a
// Web Worker when possible), draws frames and drives the menus. The calculator
// itself lives entirely in core/; nothing here interprets what a key "means".

import { validateROM, findVersion } from './core/emulator.js';
import * as storage from './storage.js';

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------- key layout
// Legends are labels only; the ROM decides what each key does.

const K = (key, label, style, second, alpha) => ({ key, label, style, second, alpha });

const GRAPH_ROW = [
  K('yEquals', 'y=', 'graphRow', 'stat plot', 'f1'),
  K('window', 'window', 'graphRow', 'tblset', 'f2'),
  K('zoom', 'zoom', 'graphRow', 'format', 'f3'),
  K('trace', 'trace', 'graphRow', 'calc', 'f4'),
  K('graph', 'graph', 'graphRow', 'table', 'f5'),
];

const CONTROL_ROWS = [
  [K('second', '2nd', 'second'), K('mode', 'mode', 'function', 'quit'), K('del', 'del', 'function', 'ins')],
  [K('alpha', 'alpha', 'alpha', 'A-lock'), K('xton', 'X,T,θ,n', 'function small', 'link'), K('stat', 'stat', 'function', 'list')],
];

const MAIN_ROWS = [
  [K('math', 'math', 'function', 'test', 'A'), K('apps', 'apps', 'function', 'angle', 'B'), K('prgm', 'prgm', 'function', 'draw', 'C'),
    K('vars', 'vars', 'function', 'distr'), K('clear', 'clear', 'function')],
  [K('inverse', 'x⁻¹', 'function', 'matrix', 'D'), K('sin', 'sin', 'function', 'sin⁻¹', 'E'), K('cos', 'cos', 'function', 'cos⁻¹', 'F'),
    K('tan', 'tan', 'function', 'tan⁻¹', 'G'), K('power', '^', 'function', 'π', 'H')],
  [K('square', 'x²', 'function', '√', 'I'), K('comma', ',', 'function', 'EE', 'J'), K('leftParen', '(', 'function', '{', 'K'),
    K('rightParen', ')', 'function', '}', 'L'), K('divide', '÷', 'function', 'e', 'M')],
  [K('log', 'log', 'function', '10ˣ', 'N'), K('k7', '7', 'number', 'u', 'O'), K('k8', '8', 'number', 'v', 'P'),
    K('k9', '9', 'number', 'w', 'Q'), K('multiply', '×', 'function', '[', 'R')],
  [K('ln', 'ln', 'function', 'eˣ', 'S'), K('k4', '4', 'number', 'L4', 'T'), K('k5', '5', 'number', 'L5', 'U'),
    K('k6', '6', 'number', 'L6', 'V'), K('subtract', '−', 'function', ']', 'W')],
  [K('sto', 'sto→', 'function', 'rcl', 'X'), K('k1', '1', 'number', 'L1', 'Y'), K('k2', '2', 'number', 'L2', 'Z'),
    K('k3', '3', 'number', 'L3', 'θ'), K('add', '+', 'function', 'mem', '"')],
  [K('on', 'on', 'function', 'off'), K('k0', '0', 'number', 'catalog', '␣'), K('decimal', '.', 'number', 'i', ':'),
    K('negate', '(−)', 'number', 'ans', '?'), K('enter', 'enter', 'enter', 'entry', 'solve')],
];

const keyElements = new Map();   // key name → element that shows the pressed state

function buildKeypad() {
  const pad = $('keypad');
  const cell = (def, row, col) => {
    const el = document.createElement('div');
    el.className = 'key ' + def.style.split(' ').map((s) => 'k-' + s).join(' ');
    el.style.gridRow = String(row);
    el.style.gridColumn = String(col);
    const legend = document.createElement('div');
    legend.className = 'legend' + (def.second && !def.alpha ? ' center' : '');
    if (def.second) legend.insertAdjacentHTML('beforeend', `<span class="s"></span>`), legend.lastChild.textContent = def.second;
    if (def.alpha) legend.insertAdjacentHTML('beforeend', `<span class="a"></span>`), legend.lastChild.textContent = def.alpha;
    const cap = document.createElement('button');
    cap.type = 'button';
    cap.className = 'cap';
    cap.textContent = def.label;
    cap.dataset.key = def.key;
    cap.setAttribute('aria-label', def.label);
    el.append(legend, cap);
    pad.append(el);
    keyElements.set(def.key, el);
  };
  GRAPH_ROW.forEach((d, i) => cell(d, 1, i + 1));
  CONTROL_ROWS.forEach((row, r) => row.forEach((d, i) => cell(d, r + 2, i + 1)));
  MAIN_ROWS.forEach((row, r) => row.forEach((d, i) => cell(d, r + 4, i + 1)));

  const arrows = document.createElement('div');
  arrows.className = 'arrows';
  for (const [key, glyph, label] of [['up', '▲', 'up'], ['left', '◀', 'left'], ['right', '▶', 'right'], ['down', '▼', 'down']]) {
    const cap = document.createElement('button');
    cap.type = 'button';
    cap.className = 'cap ' + key;
    cap.textContent = glyph;
    cap.dataset.key = key;
    cap.setAttribute('aria-label', label);
    arrows.append(cap);
    keyElements.set(key, cap);
  }
  pad.append(arrows);

  // Pointer input: each pointer holds one key until it lifts, so chords work.
  const held = new Map();
  const release = (e) => {
    const name = held.get(e.pointerId);
    if (!name) return;
    held.delete(e.pointerId);
    setKey(name, false);
  };
  pad.addEventListener('pointerdown', (e) => {
    const cap = e.target.closest('.cap');
    if (!cap) return;
    e.preventDefault();
    try { cap.setPointerCapture(e.pointerId); } catch { /* ignore */ }
    held.set(e.pointerId, cap.dataset.key);
    setKey(cap.dataset.key, true);
  });
  pad.addEventListener('pointerup', release);
  pad.addEventListener('pointercancel', release);
  pad.addEventListener('lostpointercapture', release);
  pad.addEventListener('contextmenu', (e) => e.preventDefault());
}

const down = new Map();          // key name → number of sources holding it

function setKey(name, pressed) {
  const n = (down.get(name) || 0) + (pressed ? 1 : -1);
  if (n < 0) return;
  const was = down.get(name) > 0;
  down.set(name, n);
  const now = n > 0;
  if (was === now) return;
  keyElements.get(name)?.classList.toggle('pressed', now);
  if (now && settings.haptics) { try { navigator.vibrate?.(8); } catch { /* ignore */ } }
  backend?.post({ type: 'key', name, down: now });
  // Save soon after typing stops, so closing the tab right away loses nothing.
  clearTimeout(keySaveTimer);
  keySaveTimer = setTimeout(() => { if (started) backend?.post({ type: 'autosave' }); }, 1500);
}
let keySaveTimer = null;

// ---------------------------------------------------------------- hardware keyboard

const KEYBOARD = {
  Enter: 'enter', NumpadEnter: 'enter', Backspace: 'del', Delete: 'del', Escape: 'clear',
  ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
  F1: 'yEquals', F2: 'window', F3: 'zoom', F4: 'trace', F5: 'graph', F6: 'on',
};
const CHARS = {
  0: 'k0', 1: 'k1', 2: 'k2', 3: 'k3', 4: 'k4', 5: 'k5', 6: 'k6', 7: 'k7', 8: 'k8', 9: 'k9',
  '.': 'decimal', ',': 'comma', '+': 'add', '-': 'subtract', '*': 'multiply', '/': 'divide', '^': 'power',
  '(': 'leftParen', ')': 'rightParen', '`': 'negate', '~': 'negate',
  m: 'math', a: 'apps', p: 'prgm', v: 'vars', s: 'sin', c: 'cos', t: 'tan', l: 'log', n: 'ln',
  x: 'xton', k: 'sto', d: 'mode', e: 'stat',
};
const keyboardHeld = new Map();  // event.code → key name

function keyFor(e) {
  if (KEYBOARD[e.code]) return KEYBOARD[e.code];
  if (e.ctrlKey || e.metaKey) return null;
  const ch = e.key.length === 1 ? e.key.toLowerCase() : null;
  return (ch && CHARS[ch]) || null;
}

// Shift and Alt act as 2nd and alpha when tapped on their own, so typing a shifted
// character such as * or ( doesn't also press 2nd.
const MODIFIERS = { ShiftLeft: 'second', ShiftRight: 'second', AltLeft: 'alpha', AltRight: 'alpha' };
let pendingModifier = null;

window.addEventListener('keydown', (e) => {
  if (!running() || sheetOpen()) return;
  if (e.target.closest?.('input, select, textarea')) return;
  if (MODIFIERS[e.code]) {
    if (!e.repeat) pendingModifier = e.code;
    if (e.code.startsWith('Alt')) e.preventDefault();
    return;
  }
  pendingModifier = null;
  const name = keyFor(e);
  if (!name) return;
  e.preventDefault();
  if (e.repeat || keyboardHeld.has(e.code)) return;
  keyboardHeld.set(e.code, name);
  setKey(name, true);
});
window.addEventListener('keyup', (e) => {
  if (MODIFIERS[e.code]) {
    if (pendingModifier === e.code && running() && !sheetOpen()) {
      setKey(MODIFIERS[e.code], true);
      setKey(MODIFIERS[e.code], false);
    }
    pendingModifier = null;
    return;
  }
  const name = keyboardHeld.get(e.code);
  if (!name) return;
  keyboardHeld.delete(e.code);
  setKey(name, false);
});
window.addEventListener('blur', releaseKeyboard);

function releaseKeyboard() {
  for (const name of keyboardHeld.values()) setKey(name, false);
  keyboardHeld.clear();
}

// ---------------------------------------------------------------- settings

const settings = { speed: 1, haptics: true, battery: 4, debug: false };
try { Object.assign(settings, JSON.parse(localStorage.getItem('ti84ce-settings') || '{}')); } catch { /* ignore */ }
function saveSettings() {
  try { localStorage.setItem('ti84ce-settings', JSON.stringify(settings)); } catch { /* ignore */ }
}

// ---------------------------------------------------------------- backend

let backend = null;
let started = false;
let paused = false;

/** Runs the emulator in a module worker; falls back to the page if that fails. */
function createBackend(onMessage) {
  let worker = null;
  let local = null;
  let heard = false;
  let queue = [];
  let timer = null;

  const goLocal = async () => {
    if (local) return;
    if (worker) { worker.terminate(); worker = null; }
    clearTimeout(timer);
    const { Runner } = await import('./runner.js');
    local = new Runner((msg) => onMessage(msg));
    const pending = queue;
    queue = [];
    for (const m of pending) await local.handle(m);
  };

  try {
    worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
    worker.onmessage = (e) => { heard = true; clearTimeout(timer); queue = []; onMessage(e.data); };
    worker.onerror = (e) => { if (!heard) { e.preventDefault?.(); goLocal(); } };
    worker.onmessageerror = () => { if (!heard) goLocal(); };
  } catch {
    goLocal();
  }

  return {
    post(msg) {
      if (local) { local.handle(msg); return; }
      if (!heard) {
        queue.push(msg);
        if (msg.type === 'start') timer = setTimeout(() => { if (!heard) goLocal(); }, 15000);
      }
      if (worker) worker.postMessage(msg);
    },
    terminate() {
      clearTimeout(timer);
      if (worker) worker.terminate();
      if (local) local.handle({ type: 'pause' });
      worker = null;
      local = null;
    },
  };
}

function onMessage(msg) {
  switch (msg.type) {
    case 'ready': onReady(msg); break;
    case 'frame': latestFrame = msg; scheduleDraw(); break;
    case 'status':
      paused = msg.paused;
      $('mPause').textContent = paused ? 'Resume' : 'Pause';
      setStatus(msg.breakpoint != null ? `Breakpoint at ${hex(msg.breakpoint, 6)}` : paused ? 'Paused' : '');
      break;
    case 'speed': $('speedOut').textContent = `${Math.round(msg.value * 100)}% of real time`; break;
    case 'notice': toast(msg.text); break;
    case 'error': toast('Error: ' + msg.text, 6000); break;
    case 'slots': renderSlots(msg.slots); break;
    case 'debug': renderDebug(msg.info); break;
    default: break;
  }
}

function running() { return started; }

// ---------------------------------------------------------------- display

const canvas = $('lcd');
const ctx = canvas.getContext('2d', { alpha: false });
let latestFrame = null;
let drawPending = false;

function scheduleDraw() {
  if (drawPending) return;
  drawPending = true;
  requestAnimationFrame(() => {
    drawPending = false;
    const f = latestFrame;
    if (!f) return;
    latestFrame = null;
    ctx.putImageData(new ImageData(new Uint8ClampedArray(f.pixels), 320, 240), 0, 0);
    $('dim').style.opacity = String(Math.max(0, Math.min(0.9, 1 - f.brightness)));
  });
}

// ---------------------------------------------------------------- layout

function layout() {
  const root = document.documentElement;
  const cs = getComputedStyle(root);
  const h = root.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
  const w = root.clientWidth;
  // LCD (3:4 of the width) plus a keypad about 1.2× as tall as the calculator is wide.
  const cw = Math.max(260, Math.min(w, (h - 44) / 2.0));
  root.style.setProperty('--cw', `${Math.floor(cw)}px`);
}
window.addEventListener('resize', layout);
window.visualViewport?.addEventListener('resize', layout);

// ---------------------------------------------------------------- startup

async function boot() {
  buildKeypad();
  layout();
  applySettingsToControls();
  wireUI();
  let rom = null;
  try { rom = await storage.get('rom'); } catch { /* ignore */ }
  if (rom) start(new Uint8Array(rom));
  else showSetup();
}

function showSetup(error) {
  $('setup').hidden = false;
  $('calc').hidden = true;
  const err = $('setupError');
  err.hidden = !error;
  err.textContent = error || '';
}

async function useROMFile(file) {
  if (!file) return;
  let bytes;
  try {
    bytes = new Uint8Array(await file.arrayBuffer());
    validateROM(bytes);
  } catch (e) {
    showSetup(e.message || String(e));
    return;
  }
  await storage.put('rom', bytes);
  if (backend) { backend.post({ type: 'background' }); backend.terminate(); backend = null; started = false; }
  start(bytes);
}

function start(bytes) {
  $('setup').hidden = true;
  $('calc').hidden = false;
  layout();
  setStatus('Starting…');
  backend = createBackend(onMessage);
  backend.post({ type: 'speed', value: settings.speed });
  backend.post({ type: 'start', rom: bytes, battery: settings.battery });
  const image = new Uint8Array(4 * 1024 * 1024).fill(0xFF);
  image.set(bytes.subarray(0, image.length));
  $('romInfo').textContent = `boot ${findVersion(image, 0, 0x20000) || '?'} · ${Math.round(bytes.length / 1024)} KB`;
}

function onReady(msg) {
  started = true;
  setStatus('');
  $('romInfo').textContent = `boot ${msg.boot || '?'} · OS ${msg.os || '?'}`;
  $('storageNote').hidden = msg.persistent;
  backend.post({ type: 'slots' });
  if (settings.debug) backend.post({ type: 'breakpoints', list: breakpoints });
}

// Keep memory when the page is hidden or closed.
document.addEventListener('visibilitychange', () => {
  if (!backend || !started) return;
  if (document.hidden) { releaseKeyboard(); backend.post({ type: 'background' }); }
  else backend.post({ type: 'foreground' });
});
window.addEventListener('pagehide', () => { if (backend && started) backend.post({ type: 'background' }); });
setInterval(() => { if (backend && started && !document.hidden) backend.post({ type: 'autosave' }); }, 20000);

// ---------------------------------------------------------------- UI wiring

let statusText = '';
function setStatus(text) { statusText = text; $('status').textContent = text; }

let toastTimer = null;
function toast(text, ms = 3000) {
  const t = $('toast');
  t.textContent = text;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, ms);
}

function sheetOpen() { return !$('settings').hidden || !$('debugger').hidden || !$('setup').hidden; }

function openSheet(id) {
  closeMenu();
  releaseKeyboard();
  $(id).hidden = false;
  $(id).querySelector('[data-close]')?.focus();
}
function closeSheets() {
  for (const id of ['settings', 'debugger']) $(id).hidden = true;
  clearInterval(debugTimer);
  debugTimer = null;
}

function openMenu() {
  const menu = $('menu');
  const r = $('menuBtn').getBoundingClientRect();
  menu.hidden = false;
  menu.style.top = `${r.bottom + 4}px`;
  menu.style.right = `${Math.max(8, document.documentElement.clientWidth - r.right)}px`;
  $('menuBtn').setAttribute('aria-expanded', 'true');
  menu.querySelector('button:not([hidden])')?.focus();
}
function closeMenu() {
  $('menu').hidden = true;
  $('menuBtn').setAttribute('aria-expanded', 'false');
}

function applySettingsToControls() {
  $('speedSel').value = String(settings.speed);
  $('hapticsChk').checked = settings.haptics;
  $('batterySel').value = String(settings.battery);
  $('debugChk').checked = settings.debug;
  $('mDebugger').hidden = !settings.debug;
}

function wireUI() {
  $('pickRom').addEventListener('click', () => $('romFile').click());
  $('romFile').addEventListener('change', (e) => { useROMFile(e.target.files[0]); e.target.value = ''; });

  // Drag and drop a ROM anywhere on the setup screen.
  const setup = $('setup');
  document.addEventListener('dragover', (e) => { e.preventDefault(); setup.classList.add('drag'); });
  document.addEventListener('dragleave', (e) => { if (!e.relatedTarget) setup.classList.remove('drag'); });
  document.addEventListener('drop', (e) => {
    e.preventDefault();
    setup.classList.remove('drag');
    const file = e.dataTransfer?.files?.[0];
    if (file) useROMFile(file);
  });

  $('menuBtn').addEventListener('click', (e) => { e.stopPropagation(); $('menu').hidden ? openMenu() : closeMenu(); });
  document.addEventListener('pointerdown', (e) => { if (!$('menu').hidden && !e.target.closest('#menu, #menuBtn')) closeMenu(); });
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('menu').hidden) { closeMenu(); e.preventDefault(); } else if (!$('settings').hidden || !$('debugger').hidden) { closeSheets(); e.preventDefault(); }
  });
  $('lcd').addEventListener('contextmenu', (e) => { e.preventDefault(); openMenu(); });

  $('mPause').addEventListener('click', () => { closeMenu(); backend?.post({ type: paused ? 'resume' : 'pause' }); });
  $('mSettings').addEventListener('click', () => { openSheet('settings'); backend?.post({ type: 'slots' }); });
  $('mDebugger').addEventListener('click', openDebugger);
  $('mReset').addEventListener('click', () => { closeMenu(); backend?.post({ type: 'reset' }); });
  for (const b of document.querySelectorAll('[data-close]')) b.addEventListener('click', closeSheets);

  $('speedSel').addEventListener('change', (e) => {
    settings.speed = Number(e.target.value); saveSettings();
    backend?.post({ type: 'speed', value: settings.speed });
  });
  $('hapticsChk').addEventListener('change', (e) => { settings.haptics = e.target.checked; saveSettings(); });
  $('batterySel').addEventListener('change', (e) => {
    settings.battery = Number(e.target.value); saveSettings();
    backend?.post({ type: 'battery', value: settings.battery });
  });
  $('debugChk').addEventListener('change', (e) => {
    settings.debug = e.target.checked; saveSettings();
    $('mDebugger').hidden = !settings.debug;
  });

  $('sReset').addEventListener('click', () => { backend?.post({ type: 'reset' }); closeSheets(); });
  confirmButton($('sResetRAM'), () => { backend?.post({ type: 'resetRAM' }); closeSheets(); });
  confirmButton($('sErase'), () => { backend?.post({ type: 'eraseAll' }); closeSheets(); });
  $('sNewRom').addEventListener('click', () => $('romFile').click());

  $('dRun').addEventListener('click', () => backend?.post({ type: 'resume' }));
  $('dPause').addEventListener('click', () => { backend?.post({ type: 'pause' }); backend?.post({ type: 'debug' }); });
  $('dStep').addEventListener('click', () => { if (!paused) backend?.post({ type: 'pause' }); backend?.post({ type: 'step' }); });
  $('bpAdd').addEventListener('click', addBreakpoint);
  $('bpInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') addBreakpoint(); });
}

/** Destructive actions need a second tap within a few seconds. */
function confirmButton(button, action) {
  const label = button.textContent;
  let timer = null;
  button.addEventListener('click', () => {
    if (button.classList.contains('armed')) {
      clearTimeout(timer);
      button.classList.remove('armed');
      button.textContent = label;
      action();
      return;
    }
    button.classList.add('armed');
    button.textContent = button.dataset.confirm;
    timer = setTimeout(() => { button.classList.remove('armed'); button.textContent = label; }, 3500);
  });
}

// ---------------------------------------------------------------- slots

function renderSlots(slots) {
  const box = $('slots');
  box.textContent = '';
  slots.forEach((savedAt, i) => {
    const n = i + 1;
    const row = document.createElement('div');
    row.className = 'row slot';
    const name = document.createElement('span');
    name.textContent = `Slot ${n}`;
    const when = document.createElement('span');
    when.className = 'when';
    when.textContent = savedAt === null ? 'empty' : savedAt ? new Date(savedAt).toLocaleString() : 'saved';
    const save = document.createElement('button');
    save.type = 'button';
    save.textContent = 'Save';
    save.addEventListener('click', () => backend?.post({ type: 'saveSlot', slot: n }));
    const load = document.createElement('button');
    load.type = 'button';
    load.textContent = 'Load';
    load.disabled = savedAt === null;
    load.addEventListener('click', () => { backend?.post({ type: 'loadSlot', slot: n }); closeSheets(); });
    row.append(name, when, save, load);
    box.append(row);
  });
}

// ---------------------------------------------------------------- debugger

let breakpoints = [];
let debugTimer = null;
const hex = (v, n) => '0x' + (v >>> 0).toString(16).toUpperCase().padStart(n, '0');

function openDebugger() {
  openSheet('debugger');
  backend?.post({ type: 'debug' });
  renderBreakpoints();
  clearInterval(debugTimer);
  debugTimer = setInterval(() => { if (!paused) backend?.post({ type: 'debug' }); }, 500);
}

function addBreakpoint() {
  const text = $('bpInput').value.trim().replace(/^0x/i, '');
  const v = parseInt(text, 16);
  if (!/^[0-9a-f]{1,6}$/i.test(text) || Number.isNaN(v)) { toast('Enter a hex address such as 021A3C.'); return; }
  if (!breakpoints.includes(v)) breakpoints.push(v);
  $('bpInput').value = '';
  backend?.post({ type: 'breakpoints', list: breakpoints });
  renderBreakpoints();
}

function renderBreakpoints() {
  const box = $('bpList');
  box.textContent = '';
  for (const bp of breakpoints) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = `${hex(bp, 6)} ✕`;
    b.title = 'Remove breakpoint';
    b.addEventListener('click', () => {
      breakpoints = breakpoints.filter((x) => x !== bp);
      backend?.post({ type: 'breakpoints', list: breakpoints });
      renderBreakpoints();
    });
    box.append(b);
  }
}

function renderDebug(info) {
  if ($('debugger').hidden) return;
  const r = info.regs;
  const f = r.f;
  const flags = ['S', 'Z', '5', 'H', '3', 'P/V', 'N', 'C'].map((n, i) => ((f >> (7 - i)) & 1 ? n : '·')).join(' ');
  const lines = [
    `PC  ${hex(r.pc, 6)}   ${info.adl ? 'ADL' : 'Z80'} mode   MBASE ${hex(r.mbase, 2)}   ${info.halted ? 'HALT' : ''}`,
    `op  ${info.opcode.map((b) => b.toString(16).toUpperCase().padStart(2, '0')).join(' ')}`,
    '',
    `AF  ${hex((r.a << 8) | r.f, 4)}   AF' ${hex(r.af_, 4)}   flags ${flags}`,
    `BC  ${hex(r.bc, 6)} BC' ${hex(r.bc_, 6)}`,
    `DE  ${hex(r.de, 6)} DE' ${hex(r.de_, 6)}`,
    `HL  ${hex(r.hl, 6)} HL' ${hex(r.hl_, 6)}`,
    `IX  ${hex(r.ix, 6)} IY  ${hex(r.iy, 6)}`,
    `SPL ${hex(r.spl, 6)} SPS ${hex(r.sps, 4)}`,
    `I   ${hex(r.i, 4)}   R ${hex(r.r, 2)}   IM ${info.im}   IEF1 ${info.ief1 ? 1 : 0} IEF2 ${info.ief2 ? 1 : 0}`,
    '',
    `stack ${info.stack.map((v) => hex(v, info.adl ? 6 : 4)).join(' ')}`,
    '',
    `time ${info.seconds.toFixed(3)} s   cycles ${info.cycles}   CPU ${(info.cpuHz / 1e6).toFixed(0)} MHz`,
    `int  enabled ${hex(info.interrupts.enabled, 6)} status ${hex(info.interrupts.status, 6)} raw ${hex(info.interrupts.raw, 6)} irq ${info.interrupts.irq ? 1 : 0}`,
    `lcd  control ${hex(info.lcd.control, 8)} base ${hex(info.lcd.base, 6)} madctl ${hex(info.lcd.madctl, 2)} ${info.lcd.on ? 'on' : 'off'}`,
    `keys mode ${info.keypad.mode} status ${hex(info.keypad.status, 2)} data ${info.keypad.data.map((b) => b.toString(16).padStart(2, '0')).join(' ')}`,
    `gpt  control ${hex(info.timers.control, 8)} status ${hex(info.timers.status, 4)} counters ${info.timers.counters.map((c) => hex(c, 8)).join(' ')}`,
  ];
  if (info.lastUnsupported) lines.push('', info.lastUnsupported);
  $('dbgOut').textContent = lines.join('\n');
}

// ---------------------------------------------------------------- offline support

if ('serviceWorker' in navigator && /^https?:$/.test(location.protocol)) {
  try {
    navigator.serviceWorker.register('sw.js').catch(() => { /* not available here */ });
  } catch { /* ignore */ }
}

boot();
