// Run with: npm install && npm test   (from Shared/WebGuard)
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'reels-observer.js'), 'utf8');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Objects created inside jsdom have another realm's prototypes.
const plain = (o) => (o === undefined ? o : JSON.parse(JSON.stringify(o)));
const open = [];

function makePage(url, decide) {
  const dom = new JSDOM('<!doctype html><body></body>', { url, runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window;
  // jsdom has no layout: pretend every element fills the viewport.
  w.HTMLElement.prototype.getBoundingClientRect = () => ({ left: 0, top: 0, right: 300, bottom: 500, width: 300, height: 500 });
  w.HTMLMediaElement.prototype.pause = function () { this.__paused = true; };
  w.eval(SOURCE);
  const sent = [];
  const events = { blocked: 0, allowed: 0 };
  w.ReelsGuardObserver.start(
    { send: (m) => { sent.push(m); return Promise.resolve(decide ? decide(m) : { decision: 'allow' }); } },
    { onBlock: () => events.blocked++, onAllow: () => events.allowed++ }
  );
  open.push(dom);
  const navigate = (p) => w.history.pushState({}, '', p);
  return { dom, w, sent, events, navigate };
}

function reelMarkup(w, { creator, button, reelId }) {
  const root = w.document.createElement('section');
  root.innerHTML = `
    <div class="header">
      <a href="/${creator}/">${creator}</a>
      ${button ? `<div role="button">${button}</div>` : ''}
      ${reelId ? `<a href="/reel/${reelId}/">permalink</a>` : ''}
    </div>
    <div><video></video></div>`;
  w.document.body.appendChild(root);
  return root.querySelector('video');
}

after(() => open.forEach((d) => d.window.close()));

test('parsePath mirrors the Swift classifier', () => {
  const { w, dom } = makePage('https://www.instagram.com/');
  const p = w.ReelsGuardObserver._internal.parsePath;
  assert.deepEqual(plain(p('/')), { kind: 'home' });
  assert.deepEqual(plain(p('/reels/')), { kind: 'reelsFeed' });
  assert.deepEqual(plain(p('/reels/C1/')), { kind: 'reel', id: 'C1', author: null });
  assert.deepEqual(plain(p('/reel/C1/')), { kind: 'reel', id: 'C1', author: null });
  assert.deepEqual(plain(p('/Friend/reel/C1/')), { kind: 'reel', id: 'C1', author: 'friend' });
  assert.deepEqual(plain(p('/reels/audio/9/')), { kind: 'other' });
  assert.deepEqual(plain(p('/direct/t/1/')), { kind: 'direct' });
  assert.deepEqual(plain(p('/friend/')), { kind: 'profile', username: 'friend' });
  assert.deepEqual(plain(p('/friend/reels/')), { kind: 'profile', username: 'friend' });
  assert.deepEqual(plain(p('/explore/')), { kind: 'other' });
  assert.deepEqual(plain(p('/accounts/edit/')), { kind: 'other' });
  dom.window.close();
});

test('reports DM page, then the opened Reel with its creator and follow hint', async () => {
  const { dom, w, sent, navigate } = makePage('https://www.instagram.com/direct/t/42/');
  await sleep(50);
  assert.deepEqual(plain(sent[0]), { type: 'page', url: 'https://www.instagram.com/direct/t/42/' });

  reelMarkup(w, { creator: 'pal', button: 'Follow' });
  navigate('/reel/AAA/');
  await sleep(450);
  const reel = sent.find((m) => m.type === 'reel');
  assert.equal(reel.reelID, 'AAA');
  assert.equal(reel.creator, 'pal');
  assert.equal(reel.followHint, 'notFollowing');
  dom.window.close();
});

test('a swipe to a different video is reported as a new Reel and blocked', async () => {
  const decide = (m) => (m.type === 'reel' && m.reelID === 'BBB' ? { decision: 'block', block: { title: 'Reels Blocked' } } : { decision: 'allow' });
  const { dom, w, sent, events, navigate } = makePage('https://www.instagram.com/friend/', decide);
  const first = reelMarkup(w, { creator: 'friend', button: null });
  navigate('/reel/AAA/');
  await sleep(450);
  first.dispatchEvent(new w.Event('play'));

  // Instagram swaps in the next video without necessarily changing the URL.
  w.document.body.innerHTML = '';
  const next = reelMarkup(w, { creator: 'brand', button: 'Follow', reelId: 'BBB' });
  w.document.dispatchEvent(new w.Event('touchmove')); // the user swiped
  next.dispatchEvent(new w.Event('play'));
  await sleep(50);

  const reels = sent.filter((m) => m.type === 'reel');
  assert.deepEqual(plain(reels.map((m) => m.reelID)), ['AAA', 'BBB']);
  assert.equal(reels[0].followHint, 'noFollowButton');
  assert.equal(reels[1].creator, 'brand');
  assert.equal(events.blocked, 1);
  assert.equal(next.__paused, true, 'blocked video is paused');

  // While blocked, any video that starts playing is paused again.
  const sneaky = reelMarkup(w, { creator: 'x', button: 'Follow' });
  sneaky.dispatchEvent(new w.Event('play'));
  assert.equal(sneaky.__paused, true);

  // Leaving to a normal page unblocks.
  navigate('/');
  await sleep(400);
  assert.equal(events.allowed, 1);
  dom.window.close();
});

test('profile visits report the header follow state', async () => {
  const { dom, w, sent } = makePage('https://www.instagram.com/about/');
  w.document.body.innerHTML = '<header><a href="/pal/">pal</a><button>Following</button></header>';
  w.history.pushState({}, '', '/pal/');
  await sleep(450);
  assert.deepEqual(plain(sent.find((m) => m.type === 'profile')), { type: 'profile', username: 'pal', following: true });
  dom.window.close();
});

test('direct-message pages are never scraped', async () => {
  const { dom, w, sent } = makePage('https://www.instagram.com/direct/t/1/');
  w.document.body.innerHTML = '<header><button>Following</button></header><video></video>';
  w.document.querySelector('video').dispatchEvent(new w.Event('play'));
  await sleep(400);
  assert.deepEqual(plain(sent.map((m) => m.type)), ['page']);
  dom.window.close();
});

test('the copy embedded in the app (ObserverScript.swift) is up to date', () => {
  const swift = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'App', 'Sources', 'Browser', 'ObserverScript.swift'), 'utf8');
  assert.ok(swift.includes(SOURCE.trimEnd()), 'run scripts/build-playgrounds-app.py');
});

const playing = (video) => Object.defineProperty(video, 'paused', { get: () => false });
const blockSecondReel = (m) =>
  m.type === 'reel' && m.reelID !== firstReel.id ? { decision: 'block', block: {} } : { decision: 'allow' };
const firstReel = { id: null };

test('a Reel opened over a DM thread is allowed, scrolling past it is reported, and nothing is read', async () => {
  firstReel.id = null;
  const decide = (m) => {
    if (m.type === 'reel' && firstReel.id === null) firstReel.id = m.reelID;
    return blockSecondReel(m);
  };
  const { dom, w, sent, events } = makePage('https://www.instagram.com/direct/t/7/', decide);
  const first = reelMarkup(w, { creator: 'friendname', button: 'Following' });
  playing(first);
  first.dispatchEvent(new w.Event('play'));
  await sleep(50);

  w.document.body.innerHTML = '';
  const next = reelMarkup(w, { creator: 'brand', button: 'Follow' });
  playing(next);
  w.document.dispatchEvent(new w.Event('touchmove'));
  next.dispatchEvent(new w.Event('play'));
  await sleep(50);

  const reels = sent.filter((m) => m.type === 'reel');
  assert.equal(reels.length, 2);
  assert.notEqual(reels[0].reelID, reels[1].reelID);
  for (const m of reels) {
    assert.equal(m.creator, null, 'no names read on DM pages');
    assert.equal(m.followHint, 'unknown');
  }
  assert.equal(events.blocked, 1);
});

test('the same <video> element switching to a new source after a swipe is a new Reel', async () => {
  const { w, sent, navigate } = makePage('https://www.instagram.com/direct/t/1/');
  const video = reelMarkup(w, { creator: 'pal', button: null });
  video.src = 'blob:https://www.instagram.com/one';
  navigate('/reel/AAA/');
  await sleep(450);
  w.document.dispatchEvent(new w.Event('touchmove'));
  video.src = 'blob:https://www.instagram.com/two';
  video.dispatchEvent(new w.Event('play'));
  await sleep(50);
  assert.deepEqual(plain(sent.filter((m) => m.type === 'reel').map((m) => m.reelID)), ['AAA', 'video-1']);
});

test('scrolling the Reel viewer a full screen is a new Reel, even if the video never changes', async () => {
  const { w, sent, navigate } = makePage('https://www.instagram.com/direct/t/1/');
  const scroller = w.document.createElement('div');
  w.document.body.appendChild(scroller);
  let top = 0;
  Object.defineProperty(scroller, 'scrollTop', { get: () => top });
  const video = w.document.createElement('video');
  scroller.appendChild(video);
  navigate('/reel/AAA/');
  await sleep(1800); // no creator link on the page: the first report waits for one, then gives up

  scroller.dispatchEvent(new w.Event('scroll'));   // baseline
  top = 100;
  scroller.dispatchEvent(new w.Event('scroll'));   // small drag: same Reel
  assert.equal(sent.filter((m) => m.type === 'reel').length, 1);
  top = 700;
  scroller.dispatchEvent(new w.Event('scroll'));   // a full screen: next Reel
  await sleep(50);
  assert.equal(sent.filter((m) => m.type === 'reel').length, 2);
});

test('Instagram re-rendering the same Reel without any swipe is not a new Reel', async () => {
  const { w, sent, navigate } = makePage('https://www.instagram.com/direct/t/1/');
  reelMarkup(w, { creator: 'pal', button: null });
  navigate('/reel/AAA/');
  await sleep(450);
  w.document.body.innerHTML = '';
  const rerendered = reelMarkup(w, { creator: 'pal', button: null });
  rerendered.dispatchEvent(new w.Event('play'));
  await sleep(600);
  assert.equal(sent.filter((m) => m.type === 'reel').length, 1);
});
