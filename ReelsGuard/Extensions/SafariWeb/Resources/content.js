// Safari host for reels-observer.js: transports messages to the native
// handler and keeps the per-tab GuardState in sessionStorage (survives reloads,
// cleared when the tab closes). The blocking screen is block-overlay.js.
(function () {
  'use strict';
  var STATE_KEY = '__reelsGuardState';

  function readState() {
    try { return sessionStorage.getItem(STATE_KEY); } catch (e) { return null; }
  }
  function writeState(json) {
    try { if (json) sessionStorage.setItem(STATE_KEY, json); } catch (e) { /* ignore */ }
  }

  ReelsGuardObserver.start(
    {
      send: function (message) {
        message.stateJSON = readState();
        return browser.runtime.sendMessage(message).then(function (response) {
          if (response) writeState(response.stateJSON);
          return response;
        });
      }
    },
    {
      onBlock: function (response) { ReelsGuardOverlay.show(response.block || {}); },
      onAllow: ReelsGuardOverlay.hide
    }
  );
})();
