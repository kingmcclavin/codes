/*
 * Reels Guard for the web — pure logic (no DOM), shared by app.js and the tests.
 *
 * The web version can't show or filter instagram.com itself: Instagram forbids
 * other sites from framing it. It plays single Reels through Instagram's
 * official embed player, which shows exactly one Reel and no feed.
 */
(function (root) {
  'use strict';

  var HOST_RE = /^(www\.|m\.)?instagram\.com$|^(www\.)?instagr\.am$/i;
  var CODE_RE = /^[A-Za-z0-9_-]{5,64}$/;
  var KINDS = ['reel', 'reels', 'tv', 'p'];
  // Instagram routes that look like a username in /<username>/reel/<code>/.
  var RESERVED = ['share', 'stories', 'explore', 'direct', 'accounts', 'about', 'legal', 'web'];

  function fromSegments(segs) {
    var first = (segs[0] || '').toLowerCase();
    var kindSeg = null;
    var code = null;
    if (KINDS.indexOf(first) >= 0) {
      kindSeg = first;
      code = segs[1];
    } else if (segs.length >= 3 && RESERVED.indexOf(first) < 0 &&
               KINDS.indexOf((segs[1] || '').toLowerCase()) >= 0) {
      kindSeg = segs[1].toLowerCase(); // /<username>/reel/<code>/
      code = segs[2];
    }
    if (!kindSeg || !code || !CODE_RE.test(code)) return null;
    if (kindSeg === 'reels' && code.toLowerCase() === 'audio') return null;
    var kind = kindSeg === 'p' ? 'p' : 'reel';
    var url = 'https://www.instagram.com/' + kind + '/' + code + '/';
    return { kind: kind, code: code, url: url, embedUrl: url + 'embed/' };
  }

  /**
   * Finds an Instagram Reel or post link in pasted or shared text.
   * Returns { kind, code, url, embedUrl } or { error: 'share' | 'invalid' }.
   * 'share' means an instagram.com/share/… short link, which only resolves on
   * Instagram's side and can't be embedded directly.
   */
  function parseLink(text) {
    if (typeof text !== 'string') return { error: 'invalid' };
    var tokens = text.split(/[\s<>"']+/);
    var sawShare = false;
    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      if (!/instagr(\.am|am\.com)/i.test(token)) continue;
      if (!/^https?:\/\//i.test(token)) token = 'https://' + token;
      var u;
      try { u = new URL(token); } catch (e) { continue; }
      if (!HOST_RE.test(u.hostname)) continue;
      var segs = u.pathname.split('/').filter(Boolean);
      var found = fromSegments(segs);
      if (found) return found;
      if ((segs[0] || '').toLowerCase() === 'share') sawShare = true;
    }
    return { error: sawShare ? 'share' : 'invalid' };
  }

  // ---------------------------------------------------------------------------
  // Reel time limit. Same rules as the iOS app's ReelTimeBudget: a daily counter
  // that, once used up, starts a cooldown; when the cooldown ends the counter
  // starts again from zero.

  var MAX_TICK = 15;

  function startOfDay(ms) {
    var d = new Date(ms);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  function normalizeBudget(budget, now) {
    var b = { dayStart: 0, secondsUsed: 0, cooldownUntil: null };
    if (budget) {
      if (typeof budget.dayStart === 'number') b.dayStart = budget.dayStart;
      if (typeof budget.secondsUsed === 'number') b.secondsUsed = budget.secondsUsed;
      if (typeof budget.cooldownUntil === 'number') b.cooldownUntil = budget.cooldownUntil;
    }
    if (b.cooldownUntil !== null) {
      if (now >= b.cooldownUntil) {
        b.cooldownUntil = null;
        b.secondsUsed = 0;
        b.dayStart = startOfDay(now);
      }
      return b;
    }
    var today = startOfDay(now);
    if (b.dayStart !== today) {
      b.dayStart = today;
      b.secondsUsed = 0;
    }
    return b;
  }

  function activeCooldown(budget, now) {
    return budget && typeof budget.cooldownUntil === 'number' && now < budget.cooldownUntil
      ? budget.cooldownUntil : null;
  }

  /** Adds watch time. Returns { budget, until } where until is set when the limit was reached. */
  function recordWatch(budget, seconds, limitSeconds, cooldownSeconds, now) {
    var b = normalizeBudget(budget, now);
    if (activeCooldown(b, now) !== null) return { budget: b, until: b.cooldownUntil };
    b.secondsUsed += Math.min(Math.max(seconds, 0), MAX_TICK);
    if (b.secondsUsed >= limitSeconds) {
      b.cooldownUntil = now + cooldownSeconds * 1000;
      return { budget: b, until: b.cooldownUntil };
    }
    return { budget: b, until: null };
  }

  function remainingSeconds(budget, limitSeconds) {
    return Math.max(limitSeconds - (budget ? budget.secondsUsed : 0), 0);
  }

  var api = {
    parseLink: parseLink,
    normalizeBudget: normalizeBudget,
    activeCooldown: activeCooldown,
    recordWatch: recordWatch,
    remainingSeconds: remainingSeconds,
    MAX_TICK: MAX_TICK
  };
  root.ReelsGuardWeb = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
