// Run with: node --test ReelsGuard/Web/tests/   (no dependencies)
const { test } = require('node:test');
const assert = require('node:assert/strict');
const core = require('../core.js');

test('parses Reel and post links in the shapes Instagram shares them', () => {
  const cases = [
    ['https://www.instagram.com/reel/C1abcDEF/?igsh=MWQ1ZGUxMzBkMA==', 'reel', 'C1abcDEF'],
    ['instagram.com/reels/C1abcDEF', 'reel', 'C1abcDEF'],
    ['https://www.instagram.com/tv/C1abcDEF/', 'reel', 'C1abcDEF'],
    ['https://instagram.com/p/Cxyz_12-3/', 'p', 'Cxyz_12-3'],
    ['https://www.instagram.com/some.friend/reel/C1abcDEF/', 'reel', 'C1abcDEF'],
    ['Look at this lol https://www.instagram.com/reel/C1abcDEF/?utm_source=ig_web_copy_link', 'reel', 'C1abcDEF'],
    ['https://instagr.am/p/Cxyz123/', 'p', 'Cxyz123'],
  ];
  for (const [text, kind, code] of cases) {
    const r = core.parseLink(text);
    assert.equal(r.kind, kind, text);
    assert.equal(r.code, code, text);
    assert.equal(r.embedUrl, `https://www.instagram.com/${kind}/${code}/embed/`);
  }
});

test('rejects links that are not a single Reel or post', () => {
  for (const text of [
    'https://www.instagram.com/reels/',
    'https://www.instagram.com/explore/',
    'https://www.instagram.com/reels/audio/123456/',
    'https://www.instagram.com/some.friend/',
    'https://example.com/reel/C1abcDEF/',
    'https://instagram.com.evil.example/reel/C1abcDEF/',
    'no link here',
    '',
  ]) {
    assert.equal(core.parseLink(text).error, 'invalid', text);
  }
  assert.equal(core.parseLink('https://www.instagram.com/share/reel/BAxyz/').error, 'share');
});

test('the Reel time limit starts a cooldown and resets after it', () => {
  const now = new Date(2026, 9, 7, 15, 0, 0).getTime();
  let budget = core.normalizeBudget(null, now);
  let until = null;
  for (let i = 0; i < 60 && until === null; i++) {
    ({ budget, until } = core.recordWatch(budget, 5, 300, 3600, now)); // 5 min limit, 1 h cooldown
  }
  assert.equal(until, now + 3600 * 1000);
  assert.equal(core.activeCooldown(budget, now + 1000), until);
  // More watching during the cooldown changes nothing.
  assert.equal(core.recordWatch(budget, 5, 300, 3600, now + 2000).until, until);
  // After the cooldown the counter starts from zero.
  const later = core.normalizeBudget(budget, until + 1);
  assert.equal(later.cooldownUntil, null);
  assert.equal(later.secondsUsed, 0);
});

test('one oversized tick cannot use up the limit, and a new day resets the counter', () => {
  const now = new Date(2026, 9, 7, 23, 59, 0).getTime();
  const r = core.recordWatch(null, 10000, 300, 3600, now);
  assert.equal(r.budget.secondsUsed, core.MAX_TICK);
  const tomorrow = core.normalizeBudget(r.budget, now + 2 * 60 * 1000);
  assert.equal(tomorrow.secondsUsed, 0);
  assert.equal(core.remainingSeconds(tomorrow, 300), 300);
});
