// Userscript host for reels-observer.js: runs the JavaScript policy right in
// the page (no app needed), keeps the tab's Reel state in sessionStorage and
// the accounts learned as followed in localStorage. Nothing leaves the device.
(function () {
  'use strict';
  var STATE_KEY = '__reelsGuardState';
  var FOLLOWS_KEY = 'reelsGuard.follows';
  var DEBUG_KEY = 'reelsGuard.debug';
  var ANNOUNCED_KEY = '__reelsGuardAnnounced';

  function readJSON(store, key, fallback) {
    try {
      var raw = store.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) { return fallback; }
  }
  function writeJSON(store, key, value) {
    try { store.setItem(key, JSON.stringify(value)); } catch (e) { /* ignore */ }
  }
  function knownFollows() {
    var list = readJSON(localStorage, FOLLOWS_KEY, []);
    return new Set(Array.isArray(list) ? list : []);
  }

  var lastDecision = '';

  var observer = ReelsGuardObserver.start(
    {
      send: function (message) {
        if (message.type === 'profile') {
          var follows = knownFollows();
          var name = String(message.username || '').toLowerCase();
          if (name) {
            if (message.following) follows.add(name); else follows.delete(name);
            writeJSON(localStorage, FOLLOWS_KEY, Array.from(follows).sort());
          }
          return Promise.resolve({ decision: 'allow' });
        }
        var result = ReelsGuardPolicy.decide(message, readJSON(sessionStorage, STATE_KEY, null), knownFollows());
        writeJSON(sessionStorage, STATE_KEY, result.state);
        if (message.type !== 'tick') {
          lastDecision = message.type + ' → ' + (result.response.reason || result.response.decision);
        }
        return Promise.resolve(result.response);
      }
    },
    {
      onBlock: function (response) { ReelsGuardOverlay.show(response.block || {}); },
      onAllow: ReelsGuardOverlay.hide
    }
  );

  // ---------------------------------------------------------------------------
  // A small badge, so it's easy to tell that the script is running.

  function badge(text, persistent) {
    var el = document.createElement('reels-guard-badge');
    el.style.cssText = 'all:initial;position:fixed;z-index:2147483646;left:50%;transform:translateX(-50%);' +
      'top:calc(env(safe-area-inset-top, 0px) + 8px);padding:6px 12px;border-radius:999px;' +
      'background:rgba(28,28,30,.88);color:#fff;font:600 13px -apple-system,system-ui,sans-serif;' +
      'pointer-events:none;white-space:pre;text-align:left;max-width:92vw;overflow:hidden';
    el.textContent = text;
    (document.documentElement || document).appendChild(el);
    if (!persistent) setTimeout(function () { el.remove(); }, 2500);
    return el;
  }

  function announce() {
    try {
      if (sessionStorage.getItem(ANNOUNCED_KEY)) return;
      sessionStorage.setItem(ANNOUNCED_KEY, '1');
    } catch (e) { /* show it anyway */ }
    badge('Reels Guard is on', false);
  }

  // ---------------------------------------------------------------------------
  // Diagnostic panel: open instagram.com/#reelsguard-debug to turn it on,
  // #reelsguard-debug-off to turn it off. Shows what the script sees, so a
  // screenshot explains why something was or wasn't blocked.

  var panel = null;

  function debugEnabled() {
    var hash = location.hash;
    try {
      if (hash === '#reelsguard-debug') localStorage.setItem(DEBUG_KEY, '1');
      if (hash === '#reelsguard-debug-off') localStorage.removeItem(DEBUG_KEY);
      return localStorage.getItem(DEBUG_KEY) === '1';
    } catch (e) { return hash === '#reelsguard-debug'; }
  }

  function renderPanel() {
    if (!debugEnabled()) {
      if (panel) { panel.remove(); panel = null; }
      return;
    }
    var info = observer.debugInfo();
    var state = readJSON(sessionStorage, STATE_KEY, null) || {};
    var chain = state.chain;
    var text = 'Reels Guard (diagnostics)\n' +
      'page: ' + info.page + (info.overlayViewer ? ' + viewer' : '') + (info.viewerOpen ? ' · reel view' : '') + '\n' +
      'reel: ' + (info.reel || '–') + ' · started from: ' + (chain ? chain.entry : '–') + '\n' +
      'videos: ' + info.videos + ' · player: ' + info.playerHeight + '% tall\n' +
      'touches: ' + info.touches + ' · swipes: ' + info.swipes + (info.blocked ? ' · BLOCKED' : '') + '\n' +
      'last: ' + (lastDecision || '–');
    if (!panel || !panel.isConnected) panel = badge(text, true);
    panel.style.top = 'auto';
    panel.style.bottom = 'calc(env(safe-area-inset-bottom, 0px) + 72px)';
    panel.style.fontWeight = '500';
    panel.style.fontSize = '12px';
    panel.style.borderRadius = '10px';
    panel.textContent = text;
  }

  function onReady() {
    announce();
    renderPanel();
    setInterval(renderPanel, 500);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', onReady);
  else onReady();
})();
