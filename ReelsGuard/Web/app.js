/* Reels Guard for the web — UI. Logic lives in core.js. */
(function () {
  'use strict';
  var core = window.ReelsGuardWeb;
  var KEYS = { inbox: 'rg.inbox.v1', settings: 'rg.settings.v1', budget: 'rg.budget.v1' };
  var INBOX_LIMIT = 100;
  var TICK_SECONDS = 5;
  var INSTAGRAM_ORIGIN = 'https://www.instagram.com';

  // ---------------------------------------------------------------------------
  // Storage (this browser only). Every access is guarded: private windows and
  // blocked storage must not break the page.

  function load(key, fallback) {
    try {
      var raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* ignore */ }
  }

  var inbox = load(KEYS.inbox, []);
  if (!Array.isArray(inbox)) inbox = [];
  var settings = { limitMinutes: 0, cooldownMinutes: 60 };
  var savedSettings = load(KEYS.settings, {});
  if (savedSettings && typeof savedSettings === 'object') {
    if ([0, 5, 10, 15, 30].indexOf(savedSettings.limitMinutes) >= 0) settings.limitMinutes = savedSettings.limitMinutes;
    if ([30, 60, 120, 240].indexOf(savedSettings.cooldownMinutes) >= 0) settings.cooldownMinutes = savedSettings.cooldownMinutes;
  }
  var budget = core.normalizeBudget(load(KEYS.budget, null), Date.now());

  // ---------------------------------------------------------------------------
  // Elements

  function $(id) { return document.getElementById(id); }
  var els = {
    form: $('add-form'), link: $('link-input'), from: $('from-input'), error: $('add-error'),
    paused: $('paused'), pausedText: $('paused-text'),
    inbox: $('inbox'), empty: $('empty'), count: $('count'),
    limit: $('limit-select'), cooldown: $('cooldown-select'), cooldownRow: $('cooldown-row'),
    timeStatus: $('time-status'), clearWatched: $('clear-watched'), clearAll: $('clear-all'),
    viewer: $('viewer'), frame: $('viewer-frame'), title: $('viewer-title'),
    done: $('viewer-done'), copy: $('viewer-copy')
  };

  // ---------------------------------------------------------------------------
  // Formatting

  var rtf = typeof Intl !== 'undefined' && Intl.RelativeTimeFormat
    ? new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' }) : null;

  function ago(ms) {
    var seconds = Math.round((ms - Date.now()) / 1000);
    var units = [['day', 86400], ['hour', 3600], ['minute', 60]];
    for (var i = 0; i < units.length; i++) {
      if (Math.abs(seconds) >= units[i][1]) {
        var n = Math.round(seconds / units[i][1]);
        return rtf ? rtf.format(n, units[i][0]) : Math.abs(n) + ' ' + units[i][0] + 's ago';
      }
    }
    return 'just now';
  }

  function clock(ms) {
    return new Date(ms).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }

  // ---------------------------------------------------------------------------
  // Reel time limit

  function limitOn() { return settings.limitMinutes > 0; }

  function pausedUntil() {
    if (!limitOn()) return null;
    budget = core.normalizeBudget(budget, Date.now());
    return core.activeCooldown(budget, Date.now());
  }

  function renderTime() {
    var until = pausedUntil();
    els.paused.hidden = until === null;
    if (until !== null) els.pausedText.textContent = 'Reels are paused until ' + clock(until) + '. Your list is still here.';

    els.cooldownRow.hidden = !limitOn();
    if (!limitOn()) {
      els.timeStatus.textContent = 'No limit set.';
    } else if (until !== null) {
      els.timeStatus.textContent = 'Paused until ' + clock(until) + '.';
    } else {
      var left = Math.ceil(core.remainingSeconds(budget, settings.limitMinutes * 60) / 60);
      els.timeStatus.textContent = left + ' min of Reels left today.';
    }
    return until;
  }

  // ---------------------------------------------------------------------------
  // List

  function persistInbox() { save(KEYS.inbox, inbox); }

  function renderInbox() {
    var until = renderTime();
    els.inbox.textContent = '';
    els.empty.hidden = inbox.length > 0;
    els.count.textContent = inbox.length ? String(inbox.length) : '';

    inbox.forEach(function (item) {
      var li = document.createElement('li');
      if (item.watchedAt) li.className = 'watched';

      var open = document.createElement('button');
      open.type = 'button';
      open.className = 'reel-open';
      open.disabled = until !== null;
      open.setAttribute('aria-label', 'Play ' + (item.kind === 'p' ? 'post' : 'Reel') +
        (item.from ? ' from ' + item.from : '') + ', ' + item.code);
      open.addEventListener('click', function () { openViewer(item); });

      var thumb = document.createElement('span');
      thumb.className = 'thumb';
      thumb.innerHTML = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2.5 1.5v7l6-3.5z"/></svg>';

      var text = document.createElement('span');
      text.className = 'reel-text';
      var from = document.createElement('span');
      from.className = 'reel-from';
      from.textContent = item.from || (item.kind === 'p' ? 'Post' : 'Reel');
      var meta = document.createElement('span');
      meta.className = 'reel-meta';
      var code = document.createElement('span');
      code.className = 'code';
      code.textContent = item.code;
      meta.appendChild(code);
      meta.appendChild(document.createTextNode(' · ' + (item.watchedAt ? 'watched ' + ago(item.watchedAt) : 'added ' + ago(item.addedAt))));
      text.appendChild(from);
      text.appendChild(meta);

      open.appendChild(thumb);
      open.appendChild(text);

      var remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'reel-remove';
      remove.textContent = 'Remove';
      remove.setAttribute('aria-label', 'Remove ' + item.code);
      remove.addEventListener('click', function () {
        inbox = inbox.filter(function (x) { return x.code !== item.code; });
        persistInbox();
        renderInbox();
      });

      li.appendChild(open);
      li.appendChild(remove);
      els.inbox.appendChild(li);
    });
  }

  /** Adds a link. Returns an error message, or null on success. */
  function addLink(text, from) {
    var parsed = core.parseLink(text);
    if (parsed.error === 'share') {
      return 'That\'s a short share link, which can\'t be played here. Open it once in Safari, then copy the address from the address bar and paste that.';
    }
    if (parsed.error) {
      return 'That isn\'t a link to an Instagram Reel or post. In Instagram, tap Share on the Reel, then Copy link.';
    }
    var label = (from || '').trim().slice(0, 40);
    var existing = null;
    inbox = inbox.filter(function (x) {
      if (x.code === parsed.code) { existing = x; return false; }
      return true;
    });
    var item = existing || {
      code: parsed.code, kind: parsed.kind, url: parsed.url, embedUrl: parsed.embedUrl,
      addedAt: Date.now(), watchedAt: null, from: ''
    };
    if (label) item.from = label;
    inbox.unshift(item);
    inbox = inbox.slice(0, INBOX_LIMIT);
    persistInbox();
    renderInbox();
    return null;
  }

  els.form.addEventListener('submit', function (event) {
    event.preventDefault();
    var message = addLink(els.link.value, els.from.value);
    els.error.hidden = message === null;
    els.error.textContent = message || '';
    if (message === null) {
      els.link.value = '';
      els.from.value = '';
    }
  });

  // ---------------------------------------------------------------------------
  // Viewer: one Reel, then nothing.

  var openItem = null;
  var lastFocus = null;

  function openViewer(item) {
    if (pausedUntil() !== null) { renderInbox(); return; }
    openItem = item;
    lastFocus = document.activeElement;
    item.watchedAt = Date.now();
    persistInbox();
    els.title.textContent = (item.from ? item.from + ' · ' : '') + item.code;
    els.frame.style.height = '';
    els.frame.src = item.embedUrl;
    els.viewer.hidden = false;
    document.body.classList.add('viewing');
    els.done.focus();
  }

  function closeViewer() {
    if (!openItem) return;
    openItem = null;
    els.frame.src = 'about:blank';
    els.viewer.hidden = true;
    document.body.classList.remove('viewing');
    renderInbox();
    if (lastFocus && document.contains(lastFocus)) lastFocus.focus();
  }

  els.done.addEventListener('click', closeViewer);
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && openItem) closeViewer();
  });

  els.copy.addEventListener('click', function () {
    if (!openItem) return;
    var url = openItem.url;
    var done = function () { els.copy.textContent = 'Copied'; setTimeout(function () { els.copy.textContent = 'Copy link'; }, 1500); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(done, function () { window.prompt('Copy this link', url); });
    } else {
      window.prompt('Copy this link', url);
    }
  });

  // Instagram's embed reports its height; size the frame so nothing is cut off.
  window.addEventListener('message', function (event) {
    if (event.origin !== INSTAGRAM_ORIGIN || event.source !== els.frame.contentWindow) return;
    var data = event.data;
    if (typeof data === 'string') {
      try { data = JSON.parse(data); } catch (e) { return; }
    }
    if (data && data.type === 'MEASURE' && data.details && data.details.height > 0) {
      els.frame.style.height = Math.ceil(data.details.height) + 'px';
    }
  });

  // Count time while a Reel is open and the page is visible.
  setInterval(function () {
    if (!openItem || !limitOn() || document.visibilityState !== 'visible') return;
    var result = core.recordWatch(budget, TICK_SECONDS, settings.limitMinutes * 60,
      settings.cooldownMinutes * 60, Date.now());
    budget = result.budget;
    save(KEYS.budget, budget);
    if (result.until !== null) {
      closeViewer();
      showTab('reels');
    }
  }, TICK_SECONDS * 1000);

  // Lift the pause when the cooldown ends, and keep "added 5 minutes ago" fresh.
  setInterval(function () { if (!openItem) renderInbox(); }, 30 * 1000);

  // ---------------------------------------------------------------------------
  // Settings

  els.limit.value = String(settings.limitMinutes);
  els.cooldown.value = String(settings.cooldownMinutes);

  els.limit.addEventListener('change', function () {
    settings.limitMinutes = Number(els.limit.value);
    save(KEYS.settings, settings);
    renderInbox();
  });
  els.cooldown.addEventListener('change', function () {
    settings.cooldownMinutes = Number(els.cooldown.value);
    save(KEYS.settings, settings);
    renderInbox();
  });

  els.clearWatched.addEventListener('click', function () {
    inbox = inbox.filter(function (x) { return !x.watchedAt; });
    persistInbox();
    renderInbox();
  });

  // Two-step confirmation in the page itself.
  var confirmTimer = null;
  els.clearAll.addEventListener('click', function () {
    if (!confirmTimer) {
      els.clearAll.textContent = 'Tap again to remove all';
      confirmTimer = setTimeout(function () {
        confirmTimer = null;
        els.clearAll.textContent = 'Remove all Reels';
      }, 4000);
      return;
    }
    clearTimeout(confirmTimer);
    confirmTimer = null;
    els.clearAll.textContent = 'Remove all Reels';
    inbox = [];
    persistInbox();
    renderInbox();
  });

  // ---------------------------------------------------------------------------
  // Tabs

  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  function showTab(name) {
    tabs.forEach(function (tab) {
      var selected = tab.getAttribute('data-tab') === name;
      tab.setAttribute('aria-selected', String(selected));
      $(tab.getAttribute('aria-controls')).hidden = !selected;
    });
    renderInbox();
  }
  tabs.forEach(function (tab) {
    tab.addEventListener('click', function () { showTab(tab.getAttribute('data-tab')); });
  });

  // ---------------------------------------------------------------------------
  // Links shared into the app (Android share sheet, or ?url= from a shortcut).

  (function takeSharedLink() {
    var params = new URLSearchParams(location.search);
    var shared = [params.get('url'), params.get('text'), params.get('title')].filter(Boolean).join(' ');
    if (!shared) return;
    var message = addLink(shared, '');
    if (message) {
      els.error.hidden = false;
      els.error.textContent = message;
    }
    try { history.replaceState(null, '', location.pathname); } catch (e) { /* ignore */ }
  })();

  renderInbox();

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(function () { /* offline support is optional */ });
  }
})();
