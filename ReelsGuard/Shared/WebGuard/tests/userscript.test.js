// End to end: the assembled userscript in a simulated instagram.com page.
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { JSDOM } = require('jsdom');

const ROOT = path.join(__dirname, '..', '..', '..');
const SCRIPT = fs.readFileSync(path.join(ROOT, 'Userscript', 'reels-guard.user.js'), 'utf8');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const open = [];
after(() => open.forEach((d) => d.window.close()));

function makePage(url) {
  const dom = new JSDOM('<!doctype html><body></body>', { url, runScripts: 'outside-only', pretendToBeVisual: true });
  open.push(dom);
  const w = dom.window;
  w.HTMLElement.prototype.getBoundingClientRect = () => ({ left: 0, top: 0, right: 300, bottom: 600, width: 300, height: 600 });
  w.HTMLMediaElement.prototype.pause = function () { this.__paused = true; };
  w.eval(SCRIPT);
  return w;
}

function addReel(w, creator) {
  const section = w.document.createElement('section');
  section.innerHTML = `<a href="/${creator}/">${creator}</a><div><video></video></div>`;
  w.document.body.appendChild(section);
  return section.querySelector('video');
}

test('the userscript file is up to date with its sources', () => {
  execFileSync('python3', [path.join(ROOT, 'scripts', 'build-userscript.py'), '--check']);
});

test('opening the Reels tab shows the blocking screen', async () => {
  const w = makePage('https://www.instagram.com/reels/');
  await sleep(100);
  assert.ok(w.document.querySelector('reels-guard-block'), 'blocking screen shown');
});

test('a Reel from DMs plays, and swiping past it shows the blocking screen', async () => {
  const w = makePage('https://www.instagram.com/direct/t/5/');
  await sleep(50);
  addReel(w, 'friend');
  w.history.pushState({}, '', '/reel/AAA/');
  await sleep(500);
  assert.equal(w.document.querySelector('reels-guard-block'), null, 'the sent Reel plays');

  w.document.body.innerHTML = '';
  const next = addReel(w, 'brand');
  w.document.dispatchEvent(new w.Event('touchmove'));
  next.dispatchEvent(new w.Event('play'));
  await sleep(100);
  assert.ok(w.document.querySelector('reels-guard-block'), 'blocked after scrolling past it');
  assert.equal(next.__paused, true, 'the next Reel is paused');
});

test('normal Instagram pages are left alone', async () => {
  const w = makePage('https://www.instagram.com/');
  for (const p of ['/direct/inbox/', '/some.friend/', '/explore/']) {
    w.history.pushState({}, '', p);
    await sleep(350);
  }
  assert.equal(w.document.querySelector('reels-guard-block'), null);
});

function touch(w, type, y, x = 150) {
  const event = new w.Event(type, { bubbles: true });
  const point = [{ clientX: x, clientY: y }];
  Object.defineProperty(event, 'touches', { value: type === 'touchend' ? [] : point });
  Object.defineProperty(event, 'changedTouches', { value: point });
  w.document.body.dispatchEvent(event);
}

test('swiping up on a Reel from DMs is blocked even when nothing else on the page changes', async () => {
  // Instagram's viewer here changes neither the URL nor the <video> element.
  const w = makePage('https://www.instagram.com/direct/t/5/');
  await sleep(50);
  addReel(w, 'friend');
  w.history.pushState({}, '', '/reel/AAA/');
  await sleep(500);
  assert.equal(w.document.querySelector('reels-guard-block'), null, 'the sent Reel plays');

  touch(w, 'touchstart', 600);
  touch(w, 'touchmove', 400);
  touch(w, 'touchend', 200);
  await sleep(50);
  assert.ok(w.document.querySelector('reels-guard-block'), 'blocked on the swipe itself');
});

test('a Reel opened full screen over the DM thread is blocked on swipe too, even before it plays', async () => {
  const w = makePage('https://www.instagram.com/direct/t/5/');
  await sleep(50);
  addReel(w, 'friend');            // full-size player appears, paused (autoplay off)
  await sleep(700);                // viewer noticed by size alone
  touch(w, 'touchstart', 600);
  touch(w, 'touchend', 150);
  await sleep(50);
  assert.ok(w.document.querySelector('reels-guard-block'));
});

test('small taps, sideways swipes and comment scrolling are not swipes', async () => {
  const w = makePage('https://www.instagram.com/direct/t/5/');
  await sleep(50);
  addReel(w, 'friend');
  w.history.pushState({}, '', '/reel/AAA/');
  await sleep(500);
  touch(w, 'touchstart', 400); touch(w, 'touchend', 380);                 // a tap
  touch(w, 'touchstart', 400, 20); touch(w, 'touchend', 300, 290);        // mostly sideways
  await sleep(50);
  assert.equal(w.document.querySelector('reels-guard-block'), null);
});

test('the script announces itself once per tab', async () => {
  const w = makePage('https://www.instagram.com/');
  await sleep(50);
  const badge = w.document.querySelector('reels-guard-badge');
  assert.ok(badge && badge.textContent === 'Reels Guard is on');
});

test('#reelsguard-debug shows the diagnostic panel', async () => {
  const w = makePage('https://www.instagram.com/direct/t/5/#reelsguard-debug');
  await sleep(700);
  const panels = [...w.document.querySelectorAll('reels-guard-badge')].map((b) => b.textContent);
  assert.ok(panels.some((t) => t.startsWith('Reels Guard (diagnostics)') && t.includes('page: direct')), panels.join('|'));
});
