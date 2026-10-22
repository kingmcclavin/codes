// Developer Mode: a log of recent pointer input, for diagnosing Pencil
// problems on a real device (Settings → Developer Mode → Copy Input Log).

import { devUnlocked } from './features.js';

const MAX = 600;
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

export function inputLogText() {
  return `Basis input log (ms type pointer id x y pressure buttons note)\n${navigator.userAgent}\n${entries.join('\n')}`;
}

export const inputLogSize = () => entries.length;
