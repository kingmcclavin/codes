// Developer Mode: a log of recent pointer input, for diagnosing Pencil
// problems on a real device (Settings → Developer Mode → Copy Input Log).

import { devUnlocked } from './features.js';

const MAX = 2500;
const entries = [];
let on = null;
const t0 = performance.now();

/** Records a pointer event (or a note about what Basis did with it). Only in Developer Mode. */
export function logInput(e, note = '') {
  if (on === null) on = devUnlocked();
  if (!on) return;
  entries.push([
    Math.round(performance.now() - t0), e ? e.type.replace('pointer', '') : '-', e ? e.pointerType : '', e ? e.pointerId : '',
    e ? Math.round(e.clientX) : '', e ? Math.round(e.clientY) : '', e ? +(+e.pressure || 0).toFixed(2) : '', e ? e.buttons : '', note,
  ].join(' '));
  if (entries.length > MAX) entries.splice(0, entries.length - MAX);
}

/** Records a note with no event (what Basis decided, focus changes…). */
export function logNote(note) { logInput(null, note); }

/** Records a raw touch event: how many touches, and which are the Pencil (stylus) or a finger/palm (direct). */
export function logTouch(e) {
  if (on === null) on = devUnlocked();
  if (!on) return;
  const kinds = (list) => [...list].map((t) => (t.touchType === 'stylus' ? 'S' : 'D')).join('');
  logInput(null, `${e.type} changed=${kinds(e.changedTouches)} down=${kinds(e.touches)}${e.cancelable ? '' : ' uncancelable'}`);
}

let watching = false;
/** Notes when the page loses focus or is hidden (a system overlay can steal the Pencil). */
export function watchFocus() {
  if (watching) return;
  watching = true;
  window.addEventListener('blur', () => logNote('window blur'));
  window.addEventListener('focus', () => logNote('window focus'));
  document.addEventListener('visibilitychange', () => logNote(`visibility ${document.visibilityState}`));
}

export function inputLogText() {
  return `Basis input log (ms type pointer id x y pressure buttons note)\n${navigator.userAgent}\n${entries.join('\n')}`;
}

export const inputLogSize = () => entries.length;
