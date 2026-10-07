// Userscript host for reels-observer.js: runs the JavaScript policy right in
// the page (no app needed), keeps the tab's Reel state in sessionStorage and
// the accounts learned as followed in localStorage. Nothing leaves the device.
(function () {
  'use strict';
  var STATE_KEY = '__reelsGuardState';
  var FOLLOWS_KEY = 'reelsGuard.follows';

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

  ReelsGuardObserver.start(
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
        return Promise.resolve(result.response);
      }
    },
    {
      onBlock: function (response) { ReelsGuardOverlay.show(response.block || {}); },
      onAllow: ReelsGuardOverlay.hide
    }
  );
})();
