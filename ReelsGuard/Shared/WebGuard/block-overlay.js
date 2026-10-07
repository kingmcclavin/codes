/*
 * Reels Guard blocking screen for instagram.com pages (Safari extension and
 * userscript). Plain on purpose: a title, a sentence, one way out.
 */
(function (root) {
  'use strict';
  if (root.ReelsGuardOverlay) return;
  var host = null;

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
    button.addEventListener('click', backToInstagram);
    (document.documentElement || document).appendChild(host);
  }

  // Back to the page the Reels were opened from (such as the DM thread),
  // otherwise the home feed. Never forward to another Reel.
  function backToInstagram() {
    var path = location.pathname;
    var onReel = /^\/(reels?|tv)(\/|$)|^\/[^/]+\/(reel|reels|tv)\/[^/]+/i.test(path);
    if (!onReel) { location.reload(); return; } // viewer opened over this page
    history.back();
    setTimeout(function () {
      if (location.pathname === path) location.assign('https://www.instagram.com/');
    }, 800);
  }

  function hideBlock() {
    if (host && host.parentNode) host.parentNode.removeChild(host);
    host = null;
  }

  // Instagram re-renders aggressively; put the overlay back if it gets removed.
  setInterval(function () {
    if (host && !host.isConnected) (document.documentElement || document).appendChild(host);
  }, 500);

  root.ReelsGuardOverlay = { show: showBlock, hide: hideBlock };
})(typeof window !== 'undefined' ? window : globalThis);
