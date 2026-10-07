// Feature flags and Developer Mode.
//
// Features listed here stay hidden until they're released. Unlock Developer
// Mode (tap the version in Settings five times, then enter the password) to
// see and test them on this device.
//
// To gate a feature: add it below, then wrap its UI in `if (feature('id'))`.
// To release it: change its status to 'released' (or remove the check).

import { storage } from './util.js';

export const FEATURES = {
  toolbox: { name: 'Calculator Toolbox', status: 'pro', note: 'Formulas, Unit Converter, Graphs and History. The basic calculator stays free.' },
  // exampleTool: { name: 'Example Tool', status: 'testing', note: 'What it does' },
  //   status: 'testing' (not finished) | 'pro' (paid later) | 'released'
};

// SHA-256 of 'basis-dev:' + password. The password itself isn't in the code.
// To change it, run in a browser console:
//   [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('basis-dev:NEW PASSWORD')))].map((b) => b.toString(16).padStart(2, '0')).join('')
const PASSWORD_HASH = '99fe70f23f9263537581993d7a7ffe9ea99df8d8271e9a40a18f615b31b8b5d0';
const KEY = 'basis.dev';

const state = () => storage.get(KEY, { unlocked: false, off: [] });

export function devUnlocked() { return state().unlocked === true; }

/** Whether a feature is available here: released, or Developer Mode is on and it isn't switched off. */
export function feature(id) {
  const f = FEATURES[id];
  if (!f || f.status === 'released') return true;
  const s = state();
  return s.unlocked === true && !s.off.includes(id);
}

export function setFeatureOn(id, on) {
  const s = state();
  const off = new Set(s.off);
  if (on) off.delete(id); else off.add(id);
  storage.set(KEY, { ...s, off: [...off] });
}

async function sha256(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Unlocks Developer Mode if the password is right. */
export async function unlockDev(password) {
  if (!crypto?.subtle) throw new Error('Developer Mode needs a secure (https) connection.');
  if (await sha256('basis-dev:' + password) !== PASSWORD_HASH) return false;
  storage.set(KEY, { ...state(), unlocked: true });
  return true;
}

export function lockDev() { storage.set(KEY, { ...state(), unlocked: false }); }
