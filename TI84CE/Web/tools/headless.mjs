#!/usr/bin/env node
// Headless runner for the JavaScript core (mirrors Tools/ce-headless in Swift, with
// the same 10 ms slices and key timing, so the two implementations can be compared).
//
//   node Web/tools/headless.mjs --rom ti84ce.rom [--seconds 12] [--hold 0.2]
//        [--keys "9.0:clear,10.0:k2"] [--screenshot out.ppm] [--hash] [--bench]

import { readFileSync, writeFileSync } from 'node:fs';
import { Emulator } from '../core/emulator.js';

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 && i + 1 < args.length ? args[i + 1] : def; };
const flag = (name) => args.includes(name);

const romPath = opt('--rom');
if (!romPath) { console.error('usage: headless.mjs --rom <file> [--seconds N] [--keys t:key,...] [--hash]'); process.exit(2); }

const emu = new Emulator();
emu.loadROM(new Uint8Array(readFileSync(romPath)));
console.log(`ROM boot ${emu.bootVersion}, OS ${emu.osVersion}, fingerprint ${emu.romHash}`);
emu.cpu.onUnsupported = (m) => console.log('!! ' + m.replace('\n', ' '));

const seconds = Number(opt('--seconds', '5'));
const hold = Number(opt('--hold', '0.15'));
const events = [];
for (const item of (opt('--keys', '') || '').split(',').filter(Boolean)) {
  const [t, k] = item.split(':');
  events.push({ time: Number(t), key: k, down: true }, { time: Number(t) + hold, key: k, down: false });
}
events.sort((a, b) => a.time - b.time);

const start = performance.now();
let emulated = 0;
const slice = 0.01;
while (emulated < seconds) {
  while (events.length && events[0].time <= emulated) {
    const e = events.shift();
    emu.setKey(e.key, e.down);
  }
  emu.runSeconds(slice);
  emulated += slice;
}
const wall = (performance.now() - start) / 1000;
console.log(`Emulated ${emulated.toFixed(2)} s in ${wall.toFixed(2)} s wall (${Math.round((emulated / wall) * 100)}% speed), ${emu.lcd.framesRendered} frames`);
console.log(emu.debugDescription);

const fnv = (bytes) => {
  let h = 0x811C9DC5;
  for (let i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
};
if (flag('--hash')) {
  console.log(`HASH ram=${fnv(emu.ram)} frame=${fnv(new Uint8Array(emu.lcd.frame.buffer))} flash=${fnv(emu.flash.bytes)}`);
}

const shot = opt('--screenshot');
if (shot) {
  const f = new Uint8Array(emu.lcd.frame.buffer);
  const out = Buffer.alloc(15 + 320 * 240 * 3);
  const header = 'P6\n320 240\n255\n';
  out.write(header);
  let o = header.length;
  for (let i = 0; i < 320 * 240; i++) { out[o++] = f[i * 4]; out[o++] = f[i * 4 + 1]; out[o++] = f[i * 4 + 2]; }
  writeFileSync(shot, out.subarray(0, o));
  console.log('Screenshot written to ' + shot);
}
