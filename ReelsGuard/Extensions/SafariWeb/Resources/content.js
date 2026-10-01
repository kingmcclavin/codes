// Safari host for reels-observer.js: transports messages to the native
// handler, keeps the per-tab GuardState in sessionStorage (survives reloads,
// cleared when the tab closes) and draws the blocking screen.
(function () {
  'use strict';
  var STATE_KEY = '__reelsGuardState';
  var host = null;

  function readState() {
    try { return sessionStorage.getItem(STATE_KEY); } catch (e) { return null; }
  }
  function writeState(json) {
    try { if (json) sessionStorage.setItem(STATE_KEY, json); } catch (e) { /* ignore */ }
  }

  function showBlock(copy) {
    hideBlock();
    host = document.createElement('reels-guard-block');
    host.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647;';
    var shadow = host.attachShadow({ mode: 'closed' });
    shadow.innerHTML =
      '<style>' +
      ':host{all:initial}' +
      '.wrap{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;' +
      'background:#f2f2f2;color:#1c1c1e;font:16px -apple-system,system-ui,sans-serif;padding:24px;box-sizing:border-box}' +
      '@media (prefers-color-scheme:dark){.wrap{background:#111;color:#f2f2f2}button{background:#f2f2f2!important;color:#111!important}}' +
      '.card{max-width:340px;text-align:center}' +
      'h1{font-size:22px;font-weight:600;margin:0 0 12px}' +
      'p{margin:0 0 12px;line-height:1.4}' +
      'p.detail{opacity:.65;font-size:14px;margin-bottom:28px}' +
      'button{font:inherit;font-weight:600;border:0;border-radius:10px;padding:12px 20px;background:#1c1c1e;color:#fff;width:100%}' +
      '</style>' +
      '<div class="wrap" role="alertdialog" aria-modal="true"><div class="card">' +
      '<h1></h1><p class="msg"></p><p class="detail"></p><button type="button"></button>' +
      '</div></div>';
    shadow.querySelector('h1').textContent = copy.title || 'Reels Blocked';
    shadow.querySelector('.msg').textContent = copy.message || '';
    shadow.querySelector('.detail').textContent = copy.detail || '';
    var button = shadow.querySelector('button');
    button.textContent = copy.buttonTitle || 'Back to Instagram';
    button.addEventListener('click', function () {
      location.assign('https://www.instagram.com/');
    });
    (document.documentElement || document).appendChild(host);
  }

  function hideBlock() {
    if (host && host.parentNode) host.parentNode.removeChild(host);
    host = null;
  }

  // Instagram re-renders aggressively; put the overlay back if it gets removed.
  setInterval(function () {
    if (host && !host.isConnected) (document.documentElement || document).appendChild(host);
  }, 500);

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
      onBlock: function (response) { showBlock(response.block || {}); },
      onAllow: hideBlock
    }
  );
})();
