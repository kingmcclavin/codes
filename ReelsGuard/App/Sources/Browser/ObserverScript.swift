// GENERATED from Shared/WebGuard/reels-observer.js by scripts/build-playgrounds-app.py.
// Do not edit; edit the .js file and rerun the script.

enum ObserverScript {
    static let source = ##"""
/*
 * Reels Guard — page observer for instagram.com.
 *
 * Runs in an isolated JavaScript world (a WKContentWorld in the app's web view,
 * a content script in Safari). It never makes decisions itself: it reports
 * what the user is looking at to the host, and applies the host's verdict.
 *
 * What it reads:
 *   - location.href
 *   - on Reel pages: the creator's profile link and any Follow/Following button
 *     next to the playing video
 *   - on profile pages: whether the header shows "Following"
 * What it never reads: DM contents, captions, comments, form fields, cookies.
 * On /direct/ pages it reports the URL kind and, when a full-screen Reel
 * player is open, only that player's size and source, never text or names.
 *
 * Instagram's markup is undocumented and changes often. Everything that
 * depends on it is in the "DOM heuristics" section below so it can be
 * updated in one place. Follow/Following detection is English-only.
 */
(function (root) {
  'use strict';
  if (root.ReelsGuardObserver) return;

  // Keep in sync with InstagramURLClassifier.reservedSegments (Swift).
  var RESERVED = new Set([
    'accounts', 'about', 'api', 'ajax', 'archive', 'challenge', 'data', 'developer',
    'direct', 'directory', 'emails', 'explore', 'graphql', 'legal', 'locations',
    'notifications', 'oauth', 'p', 'privacy', 'reel', 'reels', 'session', 'settings',
    'static', 'stories', 'topics', 'tv', 'web', 'your_activity'
  ]);
  var USERNAME_RE = /^[A-Za-z0-9._]{1,30}$/;
  var INSTAGRAM_HOST_RE = /(^|\.)instagram\.com$/i;

  var URL_POLL_MS = 300;
  var TICK_MS = 5000;
  var CREATOR_RETRY_MS = 250;
  var CREATOR_RETRIES = 6;
  var ACTIVE_CHECK_MS = 500;

  // ---------------------------------------------------------------------------
  // URL parsing (mirrors InstagramURLClassifier for the parts the observer needs)

  function isUsername(segment) {
    return USERNAME_RE.test(segment) && !RESERVED.has(segment.toLowerCase());
  }

  function parsePath(pathname) {
    var segs = pathname.split('/').filter(Boolean);
    if (segs.length === 0) return { kind: 'home' };
    var first = segs[0].toLowerCase();
    var second = segs[1];
    if (first === 'reels' && second && second.toLowerCase() === 'audio') return { kind: 'other' };
    if (first === 'reel' || first === 'reels' || first === 'tv') {
      return second ? { kind: 'reel', id: second, author: null } : { kind: 'reelsFeed' };
    }
    if (first === 'direct') return { kind: 'direct' };
    if (isUsername(segs[0])) {
      var sub = second ? second.toLowerCase() : null;
      if ((sub === 'reel' || sub === 'reels' || sub === 'tv') && segs[2]) {
        return { kind: 'reel', id: segs[2], author: first };
      }
      if (sub === null || sub === 'reels' || sub === 'tagged') return { kind: 'profile', username: first };
    }
    return { kind: 'other' };
  }

  // ---------------------------------------------------------------------------
  // DOM heuristics

  function usernameFromHref(href) {
    var u;
    try { u = new URL(href, root.location.href); } catch (e) { return null; }
    if (!INSTAGRAM_HOST_RE.test(u.hostname)) return null;
    var segs = u.pathname.split('/').filter(Boolean);
    if (segs.length !== 1 || !isUsername(segs[0])) return null;
    return segs[0].toLowerCase();
  }

  function reelIdFromHref(href) {
    var u;
    try { u = new URL(href, root.location.href); } catch (e) { return null; }
    var p = parsePath(u.pathname);
    return p.kind === 'reel' ? p.id : null;
  }

  function visibleRatio(el) {
    var r = el.getBoundingClientRect();
    var vw = root.innerWidth || 0, vh = root.innerHeight || 0;
    var w = Math.max(0, Math.min(r.right, vw) - Math.max(r.left, 0));
    var h = Math.max(0, Math.min(r.bottom, vh) - Math.max(r.top, 0));
    var area = r.width * r.height;
    return area > 0 ? (w * h) / area : 0;
  }

  function mostVisibleVideo() {
    var best = null, bestRatio = 0.5;
    var videos = root.document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      var ratio = visibleRatio(videos[i]);
      if (ratio > bestRatio) { best = videos[i]; bestRatio = ratio; }
    }
    return best;
  }

  /** Nearest ancestor of `el` (within a few levels) that links to a profile. */
  function findCreator(el) {
    for (var depth = 0; el && depth < 12; depth++, el = el.parentElement) {
      var links = el.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) {
        var name = usernameFromHref(links[i].getAttribute('href'));
        if (name) return { creator: name, container: el };
      }
    }
    return { creator: null, container: null };
  }

  function followHintIn(container, creator) {
    if (!container) return 'unknown';
    var buttons = container.querySelectorAll('button, div[role="button"]');
    for (var i = 0; i < buttons.length; i++) {
      var text = (buttons[i].textContent || '').trim();
      if (text === 'Following') return 'following';
      if (text === 'Follow') return 'notFollowing';
    }
    return creator ? 'noFollowButton' : 'unknown';
  }

  /** Reel id for a video: a single /reel/<id>/ link in its container, if any. */
  function reelIdNear(video) {
    var el = video;
    for (var depth = 0; el && depth < 8; depth++, el = el.parentElement) {
      var links = el.querySelectorAll('a[href*="/reel"]');
      var ids = new Set();
      for (var i = 0; i < links.length; i++) {
        var id = reelIdFromHref(links[i].getAttribute('href'));
        if (id) ids.add(id);
      }
      if (ids.size === 1) return ids.values().next().value;
      if (ids.size > 1) return null;
    }
    return null;
  }

  function profileHeaderFollowing() {
    var header = root.document.querySelector('header');
    if (!header) return null;
    var buttons = header.querySelectorAll('button, div[role="button"]');
    for (var i = 0; i < buttons.length; i++) {
      var text = (buttons[i].textContent || '').trim();
      if (text === 'Following' || text === 'Requested') return text === 'Following';
      if (text === 'Follow' || text === 'Follow Back') return false;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Observer

  function start(transport, hooks) {
    hooks = hooks || {};
    var queue = Promise.resolve();
    var blocked = false;
    var lastHref = null;
    var current = { kind: 'other' };
    var lastReelId = null;
    var navToken = 0;
    var syntheticCounter = 0;

    // The Reel currently on screen. Instagram may reuse one <video> element
    // for the next Reel and swap its source, so identity is element + source.
    var activeVideo = null;
    var activeSrc = null;
    // Set by touch / wheel / scroll input. A change of video only counts as a
    // new Reel when the user actually moved, so re-renders of the same Reel
    // aren't mistaken for a swipe.
    var userMoved = false;
    // Scroll position of each scroller when the current Reel became active.
    var scrollBaselines = new WeakMap();
    // A full-screen Reel viewer opened on top of a DM thread (no URL change).
    var overlayViewer = false;
    var missedViewerChecks = 0;

    function send(message) {
      queue = queue
        .then(function () { return transport.send(message); })
        .then(apply)
        .catch(function () { /* host unavailable: fail open */ });
      return queue;
    }

    function apply(response) {
      if (!response) return;
      if (response.decision === 'block') {
        blocked = true;
        pauseAll();
        if (hooks.onBlock) hooks.onBlock(response);
      } else if (blocked) {
        blocked = false;
        if (hooks.onAllow) hooks.onAllow(response);
      }
    }

    function pauseAll() {
      var videos = root.document.querySelectorAll('video, audio');
      for (var i = 0; i < videos.length; i++) {
        try { videos[i].pause(); } catch (e) { /* ignore */ }
      }
    }

    function srcOf(video) { return video.currentSrc || video.src || ''; }

    /** A video tall enough to be a Reel player rather than an inline preview. */
    function isPlayerSized(video) {
      var r = video.getBoundingClientRect();
      return r.height >= (root.innerHeight || 0) * 0.6 && visibleRatio(video) >= 0.5;
    }

    function largestPlayer() {
      var best = null, bestRatio = 0;
      var videos = root.document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (!isPlayerSized(videos[i])) continue;
        var ratio = visibleRatio(videos[i]);
        if (ratio > bestRatio) { best = videos[i]; bestRatio = ratio; }
      }
      return best;
    }

    function isReelUrl() { return current.kind === 'reel' || current.kind === 'reelsFeed'; }
    function isReelContext() { return isReelUrl() || overlayViewer; }

    function activate(video) {
      activeVideo = video;
      activeSrc = video ? srcOf(video) : null;
      userMoved = false;
      scrollBaselines = new WeakMap();
    }

    function reportReel(id, video, urlAuthor) {
      if (id === lastReelId) return;
      lastReelId = id;
      // On DM pages nothing around the video is read: no names, no messages.
      var found = video && current.kind !== 'direct' ? findCreator(video) : { creator: null, container: null };
      var creator = urlAuthor || found.creator;
      send({
        type: 'reel',
        url: root.location.href,
        reelID: id,
        creator: creator,
        followHint: followHintIn(found.container, creator)
      });
    }

    function newReelId(video) {
      return (current.kind !== 'direct' && reelIdNear(video)) || ('video-' + (++syntheticCounter));
    }

    function reportReelFromUrl(id, urlAuthor, token, attempt) {
      if (token !== navToken || id === lastReelId) return;
      var video = largestPlayer() || mostVisibleVideo();
      var hasCreator = urlAuthor || (video && findCreator(video).creator);
      if (hasCreator || attempt >= CREATOR_RETRIES) {
        if (video) activate(video);
        reportReel(id, video, urlAuthor);
        return;
      }
      setTimeout(function () { reportReelFromUrl(id, urlAuthor, token, attempt + 1); }, CREATOR_RETRY_MS);
    }

    /** Detects a swipe to another Reel by the on-screen player changing. */
    function checkActiveReel() {
      if (blocked) return;
      if (current.kind === 'direct') trackOverlayViewer();
      if (!isReelContext()) return;
      var video = largestPlayer();
      if (!video) return;
      if (video === activeVideo && srcOf(video) === activeSrc) return;

      if (activeVideo === null) {
        // First player since navigation: it belongs to the Reel in the URL.
        activate(video);
        reportReel(current.kind === 'reel' ? current.id : newReelId(video), video,
          current.kind === 'reel' ? current.author : null);
        return;
      }
      if (!userMoved) {
        // Same Reel re-rendered by Instagram; follow the new element silently.
        activate(video);
        return;
      }
      activate(video);
      reportReel(newReelId(video), video, null);
    }

    /** Detects a swipe by the Reel scroller moving most of a screen. */
    function onScroll(event) {
      userMoved = true;
      if (blocked || !isReelContext() || !activeVideo) return;
      var target = event.target;
      var scroller = (target === root.document || !target || target.nodeType !== 1)
        ? root.document.scrollingElement : target;
      if (!scroller || !scroller.contains(activeVideo)) return;
      var height = scroller.clientHeight || root.innerHeight || 0;
      if (height < (root.innerHeight || 0) * 0.6) return;
      if (!scrollBaselines.has(scroller)) { scrollBaselines.set(scroller, scroller.scrollTop); return; }
      if (Math.abs(scroller.scrollTop - scrollBaselines.get(scroller)) >= height * 0.6) {
        var video = largestPlayer() || activeVideo;
        activate(video);
        reportReel(newReelId(video), video, null);
      }
    }

    /** DM threads can open a Reel full screen without changing the URL. */
    function trackOverlayViewer() {
      var player = largestPlayer();
      if (player && !player.paused) {
        missedViewerChecks = 0;
        if (!overlayViewer) { overlayViewer = true; activeVideo = null; }
        return;
      }
      if (overlayViewer && !player && ++missedViewerChecks >= 3) {
        // Viewer closed: back to the conversation, which ends the Reel chain.
        overlayViewer = false;
        activeVideo = null;
        lastReelId = null;
        send({ type: 'page', url: root.location.href });
      }
    }

    function learnFromProfile(username, token, attempt) {
      if (token !== navToken) return;
      var following = profileHeaderFollowing();
      if (following !== null) {
        send({ type: 'profile', username: username, following: following });
      } else if (attempt < CREATOR_RETRIES) {
        setTimeout(function () { learnFromProfile(username, token, attempt + 1); }, CREATOR_RETRY_MS * 2);
      }
    }

    function onUrlChange() {
      var href = root.location.href;
      if (href === lastHref) return;
      lastHref = href;
      navToken++;
      current = parsePath(root.location.pathname);
      overlayViewer = false;
      missedViewerChecks = 0;
      activeVideo = null;
      activeSrc = null;

      if (current.kind === 'reel') {
        reportReelFromUrl(current.id, current.author, navToken, 0);
        return;
      }
      lastReelId = null;
      send({ type: 'page', url: href });
      if (current.kind === 'profile') learnFromProfile(current.username, navToken, 0);
    }

    function onPlay(event) {
      var video = event.target;
      if (!video || video.tagName !== 'VIDEO') return;
      if (blocked) { video.pause(); return; }
      checkActiveReel();
    }

    function onTick() {
      if (blocked || !isReelContext() || root.document.visibilityState !== 'visible') return;
      var videos = root.document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (!videos[i].paused && !videos[i].ended) {
          send({ type: 'tick', seconds: TICK_MS / 1000 });
          return;
        }
      }
    }

    function onUserMove() { userMoved = true; }

    // Isolated worlds can't see the page's history.pushState calls, so the URL
    // is polled. This is cheap: a string comparison every 300 ms.
    root.document.addEventListener('play', onPlay, true);
    root.document.addEventListener('scroll', onScroll, true);
    root.document.addEventListener('touchmove', onUserMove, { capture: true, passive: true });
    root.document.addEventListener('wheel', onUserMove, { capture: true, passive: true });
    root.addEventListener('popstate', onUrlChange);
    setInterval(onUrlChange, URL_POLL_MS);
    setInterval(checkActiveReel, ACTIVE_CHECK_MS);
    setInterval(onTick, TICK_MS);
    setInterval(function () { if (blocked) pauseAll(); }, 1000);
    onUrlChange();

    return {
      reset: function () { blocked = false; lastHref = null; lastReelId = null; onUrlChange(); }
    };
  }

  root.ReelsGuardObserver = {
    start: start,
    // Exposed for tests.
    _internal: { parsePath: parsePath, usernameFromHref: usernameFromHref, reelIdFromHref: reelIdFromHref }
  };
})(typeof window !== 'undefined' ? window : globalThis);
"""##
}
