#!/usr/bin/env node
// ROM-free checks for the JavaScript core, run in CI: a synthetic boot program,
// ROM validation, keypad bookkeeping and save-state determinism.
//
//   node Web/tools/selftest.mjs

import assert from 'node:assert/strict';
import { Emulator, validateROM, findVersion } from '../core/emulator.js';
import { FLASH_SIZE } from '../core/memory.js';

function syntheticROM(program) {
  const image = new Uint8Array(FLASH_SIZE).fill(0xFF);
  image.set([0xF3, 0x5B, 0xC3, 0x00, 0x01, 0x00]);          // di / jp.lil $000100
  image.set(program, 0x100);
  return image;
}

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log('ok - ' + name);
}

test('rejects files that are not CE ROMs', () => {
  assert.throws(() => validateROM(new Uint8Array(10)));
  assert.throws(() => validateROM(new Uint8Array(0x20000)));
  assert.equal(validateROM(syntheticROM([0x00])).length, FLASH_SIZE);
});

test('reports the highest embedded version string', () => {
  const image = syntheticROM([0x00]);
  image.set(new TextEncoder().encode('5.0.0.0089'), 0x30000);
  image.set(new TextEncoder().encode('5.3.0.0037'), 0x40000);
  assert.equal(findVersion(image, 0x20000, 0x100000), '5.3.0.0037');
});

test('runs a program that increments RAM', () => {
  // ld hl, $D00000 / inc (hl) / jr -3
  const emu = new Emulator();
  emu.loadROM(syntheticROM([0x21, 0x00, 0x00, 0xD0, 0x34, 0x18, 0xFD]));
  emu.run(10000);
  assert.ok(emu.ram[0] > 0, 'RAM byte was incremented');
  assert.ok(emu.cpu.adl);
});

test('keypad tracks what the program has read', () => {
  const emu = new Emulator();
  emu.loadROM(syntheticROM([0x18, 0xFE]));
  const k = emu.keypad;
  k.write(0x04, 8); k.write(0x05, 8); k.write(0x01, 0x01); k.write(0x00, 0x03);
  emu.setKey('k5', true);
  assert.equal(emu.keySeen('k5'), false);
  emu.runSeconds(0.01);
  k.peek(0x10 + 2 * 4);
  assert.equal(emu.keySeen('k5'), false, 'debugger reads do not count');
  assert.equal(k.read(0x10 + 2 * 4), 0x04);
  assert.equal(emu.keySeen('k5'), true);
  emu.setKey('k5', false);
  assert.equal(k.releaseSeen, false);
  k.write(0x00, 0x01); k.write(0x08, 0xFF);
  assert.equal(k.read(0x08) & 4, 0);
  assert.equal(k.releaseSeen, true);
});

test('save states restore an identical machine', () => {
  const rom = syntheticROM([0x21, 0x00, 0x00, 0xD0, 0x34, 0x23, 0x18, 0xFC]);   // ld hl / inc (hl) / inc hl / jr
  const a = new Emulator();
  a.loadROM(rom);
  a.run(50000);
  const state = structuredClone(a.saveState());
  a.run(50000);
  const b = new Emulator();
  b.loadROM(rom);
  b.loadState(state);
  b.run(50000);
  assert.equal(b.scheduler.cycles, a.scheduler.cycles);
  assert.equal(b.cpu.pc, a.cpu.pc);
  assert.deepEqual(b.ram, a.ram);
});

console.log(`${passed} tests passed`);
