/*
 * Reels Guard policy in JavaScript, for hosts without the Swift engine (the
 * Safari userscript). Mirrors ReelsGuardCore's rules with default settings:
 *
 *   - the Reels tab (/reels/) is blocked;
 *   - a Reel sent to the user (DM or shared link) plays, and any swipe past it
 *     is blocked;
 *   - a Reel opened from a profile plays, and so do that creator's other Reels;
 *   - a Reel opened from the home feed plays unless the page shows a Follow
 *     button for its creator;
 *   - Reels from Explore, search or anywhere else play only from followed
 *     accounts;
 *   - after a Reel from a profile or the feed, the next one plays only if its
 *     creator is followed.
 *
 * Pure function of (message, state, knownFollows). No DOM, no storage.
 */
(function (root) {
  'use strict';
  if (root.ReelsGuardPolicy) return;

  var DETAIL = 'You can still watch Reels that you intentionally open from people you follow or receive from friends.';
  var COPY = {
    reelsFeed: { title: "That's enough Reels for now.", message: 'The Reels feed is made of recommendations, not things you chose.', detail: DETAIL },
    recommended: { title: 'Reels Blocked', message: 'This Reel was recommended by Instagram.', detail: DETAIL },
    notFollowed: { title: 'Reels Blocked', message: "This Reel isn't from an account you follow.", detail: DETAIL },
    infiniteScroll: {
      title: "That's enough Reels for now.",
      message: "Instagram tried to keep the Reels going, and this one couldn't be confirmed as coming from someone you follow.",
      detail: DETAIL
    },
    endOfSentReel: {
      title: "That's the Reel you were sent.",
      message: "Scrolling past it would start Instagram's Reels feed, so it stops here.",
      detail: 'You can still open other Reels your friends send you.'
    }
  };

  function parsePath(url) {
    var path;
    try { path = new URL(url).pathname; } catch (e) { return { kind: 'other' }; }
    return root.ReelsGuardObserver._internal.parsePath(path);
  }

  function block(reason, state) {
    var copy = COPY[reason];
    return {
      response: { decision: 'block', reason: reason, block: { title: copy.title, message: copy.message, detail: copy.detail, buttonTitle: 'Back to Instagram' } },
      state: state
    };
  }

  function allow(state) {
    return { response: { decision: 'allow' }, state: state };
  }

  function followState(creator, hint, knownFollows) {
    if (creator && knownFollows && knownFollows.has(creator.toLowerCase())) return 'following';
    if (hint === 'following') return 'following';
    if (hint === 'notFollowing') return 'notFollowing';
    return 'unknown';
  }

  function entrySource(lastPage) {
    if (!lastPage) return { type: 'sent' };            // fresh tab: a link opened from elsewhere
    switch (lastPage.kind) {
      case 'direct': return { type: 'sent' };
      case 'profile': return { type: 'profile', username: lastPage.username };
      case 'home': return { type: 'home' };
      case 'reelsFeed': return { type: 'reelsTab' };
      default: return { type: 'other' };
    }
  }

  /**
   * message: { type: 'page'|'reel'|'tick'|'profile', url, reelID, creator, followHint }
   * state:   { lastPage, chain } (plain JSON; null for a fresh tab)
   * Returns  { response, state }.
   */
  function decide(message, state, knownFollows) {
    state = state ? { lastPage: state.lastPage || null, chain: state.chain || null } : { lastPage: null, chain: null };
    if (!message) return allow(state);

    if (message.type === 'page') {
      var page = parsePath(message.url);
      if (page.kind === 'reel') {
        message = { type: 'reel', url: message.url, reelID: page.id, creator: page.author, followHint: 'unknown' };
      } else {
        state.chain = null;
        state.lastPage = page;
        return page.kind === 'reelsFeed' ? block('reelsFeed', state) : allow(state);
      }
    }
    if (message.type !== 'reel' || !message.reelID) return allow(state);

    var id = String(message.reelID);
    var creator = message.creator ? String(message.creator).toLowerCase() : null;
    var follow = followState(creator, message.followHint, knownFollows);
    var chain = state.chain;

    // The Reel already being watched (re-render, or swiping back to it).
    if (chain && chain.current === id) return allow(state);

    // A swipe to another Reel.
    if (chain) {
      if (chain.entry === 'sent') return block('endOfSentReel', state);
      var ok = (chain.anchor && creator === chain.anchor) || follow === 'following';
      if (!ok) return block(follow === 'notFollowing' ? 'notFollowed' : 'infiniteScroll', state);
      chain.current = id;
      chain.length += 1;
      return allow(state);
    }

    // The first Reel after a normal page.
    var source = entrySource(state.lastPage);
    var allowed;
    var reason = 'recommended';
    switch (source.type) {
      case 'sent': allowed = true; break;
      case 'profile': allowed = true; break;
      case 'home': allowed = follow !== 'notFollowing'; break;
      case 'reelsTab': allowed = false; break;
      default: allowed = follow === 'following';
    }
    if (!allowed) return block(reason, state);
    state.chain = {
      entry: source.type === 'sent' ? 'sent' : source.type,
      current: id,
      length: 1,
      anchor: source.type === 'profile' ? source.username : null
    };
    return allow(state);
  }

  root.ReelsGuardPolicy = { decide: decide };
})(typeof window !== 'undefined' ? window : globalThis);
