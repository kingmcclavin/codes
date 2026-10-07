// The JavaScript policy must make the same decisions as ReelsGuardCore
// (Swift) with default settings. Scenarios mirror ReelsGuardEngineTests.
const { test } = require('node:test');
const assert = require('node:assert/strict');
require('../reels-observer.js');
require('../reels-policy.js');
const { decide } = globalThis.ReelsGuardPolicy;

function session(follows = []) {
  let state = null;
  const known = new Set(follows);
  const run = (message) => {
    const r = decide(message, state, known);
    state = JSON.parse(JSON.stringify(r.state)); // round-trips through sessionStorage
    return r.response.decision === 'block' ? r.response.reason : 'allow';
  };
  return {
    page: (path) => run({ type: 'page', url: 'https://www.instagram.com' + path }),
    reel: (id, creator = null, followHint = 'unknown') =>
      run({ type: 'reel', url: 'https://www.instagram.com/reel/' + id + '/', reelID: id, creator, followHint }),
    get state() { return state; },
  };
}

test('a Reel sent in DMs plays; scrolling past it is blocked, even to a followed account', () => {
  const s = session(['amy']);
  s.page('/direct/t/1/');
  assert.equal(s.reel('1', 'stranger'), 'allow');
  assert.equal(s.reel('2', 'amy', 'following'), 'endOfSentReel');
  assert.equal(s.reel('3'), 'endOfSentReel');
  assert.equal(s.reel('1', 'stranger'), 'allow'); // swiping back to it
});

test('a link opened in a fresh tab counts as sent', () => {
  const s = session();
  assert.equal(s.reel('1'), 'allow');
  assert.equal(s.reel('2', 'amy', 'following'), 'endOfSentReel');
});

test('back in the conversation, the next sent Reel plays', () => {
  const s = session();
  s.page('/direct/t/1/');
  s.reel('1', 'a');
  s.reel('2', 'b');
  s.page('/direct/t/1/');
  assert.equal(s.reel('3', 'c'), 'allow');
});

test('the Reels tab and Reels reached from it are blocked', () => {
  const s = session();
  assert.equal(s.page('/reels/'), 'reelsFeed');
  assert.equal(s.reel('1', 'friend', 'following'), 'recommended');
  assert.equal(s.page('/reels/C1xyz/'), 'recommended'); // URL of a Reel in the feed
});

test('Explore Reels play only from followed accounts', () => {
  const s = session(['friend']);
  assert.equal(s.page('/explore/'), 'allow');
  assert.equal(s.reel('1', 'creator', 'notFollowing'), 'recommended');
  s.page('/explore/');
  assert.equal(s.reel('2', 'friend'), 'allow');
});

test('a profile Reel plays, the same creator can be swiped, others stop', () => {
  const s = session();
  s.page('/artist/reels/');
  assert.equal(s.reel('1', 'artist', 'notFollowing'), 'allow');
  assert.equal(s.reel('2', 'artist', 'notFollowing'), 'allow');
  assert.equal(s.reel('3', 'other', 'notFollowing'), 'notFollowed');
});

test('from the home feed: followed creators continue, suggested and unknown ones stop', () => {
  const s = session(['amy', 'ben']);
  s.page('/');
  assert.equal(s.reel('1', 'amy'), 'allow');
  assert.equal(s.reel('2', 'ben'), 'allow');
  assert.equal(s.reel('3', 'influencer', 'notFollowing'), 'notFollowed');
  assert.equal(s.reel('4'), 'infiniteScroll');
  assert.equal(s.reel('5', 'pal', 'noFollowButton'), 'infiniteScroll');

  const feed = session();
  feed.page('/');
  assert.equal(feed.reel('1', 'brand', 'notFollowing'), 'recommended'); // "Suggested for you"
});

test('normal pages are never blocked', () => {
  const s = session();
  for (const p of ['/', '/direct/inbox/', '/direct/t/9/', '/friend/', '/p/abc/', '/explore/', '/accounts/edit/']) {
    assert.equal(s.page(p), 'allow', p);
  }
});
