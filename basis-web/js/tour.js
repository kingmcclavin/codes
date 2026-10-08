// Tutorial: a welcome tour on first visit and a guided tour of the notebook
// editor the first time a notebook opens. Steps either spotlight a real
// control or show a centered card.

import { h, storage } from './util.js';
import { icon } from './icons.js';
import { store } from './store.js';
import { feature } from './features.js';

const KEY = 'basis.tutorial';
const seen = () => storage.get(KEY, null);
const mark = (part) => storage.set(KEY, { ...(seen() || {}), [part]: true });

/** People who used Basis before the tutorial existed don't get it unasked. */
export function initTutorial() {
  if (seen() === null) storage.set(KEY, store.summaries.length ? { welcome: true, editor: true } : {});
}
export const shouldShowWelcome = () => !seen()?.welcome;
export const shouldShowEditorTour = () => !seen()?.editor;
export function resetTutorial() { storage.set(KEY, {}); }

let active = null;

/**
 * Runs a list of steps. Each step: { target?: () => Element, title, body,
 * art?, badge?, actions?: [{ label, primary, run }], enter?, leave? }.
 */
export function runTour(steps, { onDone } = {}) {
  steps = steps.filter(Boolean);
  active?.end(false);
  let i = 0, ended = false;
  const root = h('div', { class: 'tour', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'Tutorial' });
  const shade = h('div', { class: 'tour-shade' });
  const ring = h('div', { class: 'tour-ring' });
  const card = h('div', { class: 'tour-card' });
  root.append(shade, ring, card);
  document.body.append(root);

  const targetOf = (s) => {
    const el = s.target?.();
    if (!el) return null;
    const r = el.getBoundingClientRect();
    // Off-screen targets (e.g. the sidebar hidden on a phone) get a centered card instead.
    const onScreen = r.right > 0 && r.bottom > 0 && r.left < window.innerWidth && r.top < window.innerHeight;
    return r.width > 0 && r.height > 0 && onScreen ? r : null;
  };

  const place = () => {
    const s = steps[i];
    const r = targetOf(s);
    const vw = window.innerWidth, vh = window.innerHeight;
    card.style.width = Math.min(360, vw - 32) + 'px';
    if (!r) {
      root.classList.add('centered');
      card.style.left = (vw - card.offsetWidth) / 2 + 'px';
      card.style.top = Math.max(16, (vh - card.offsetHeight) / 2) + 'px';
      return;
    }
    root.classList.remove('centered');
    const pad = 6;
    Object.assign(ring.style, { left: r.left - pad + 'px', top: r.top - pad + 'px', width: r.width + pad * 2 + 'px', height: r.height + pad * 2 + 'px' });
    const cw = card.offsetWidth, ch = card.offsetHeight, gap = 14;
    const clampX = (x) => Math.max(16, Math.min(vw - cw - 16, x));
    const clampY = (y) => Math.max(16, Math.min(vh - ch - 16, y));
    let left = clampX(r.left + r.width / 2 - cw / 2), top;
    if (r.bottom + pad + gap + ch <= vh - 16) top = r.bottom + pad + gap; // below
    else if (r.top - pad - gap - ch >= 16) top = r.top - pad - gap - ch; // above
    else {
      // Beside the target, whichever side has room; otherwise overlap as little as possible.
      top = clampY(r.top + r.height / 2 - ch / 2);
      if (r.left - pad - gap - cw >= 16) left = r.left - pad - gap - cw;
      else if (r.right + pad + gap + cw <= vw - 16) left = r.right + pad + gap;
      else top = clampY(vh - ch - 16);
    }
    card.style.left = left + 'px';
    card.style.top = top + 'px';
  };

  const go = async (n) => {
    await steps[i]?.leave?.();
    i = n;
    const s = steps[i];
    await s.enter?.();
    const last = i === steps.length - 1;
    const back = h('button', { class: 'btn ghost', onclick: () => go(i - 1) }, 'Back');
    const next = h('button', { class: 'btn primary', onclick: () => (last ? end(true) : go(i + 1)) }, last ? 'Done' : 'Next');
    card.replaceChildren(
      s.badge ? h('span', { class: 'tour-badge' }, s.badge) : null,
      s.art ? h('div', { class: 'tour-art' }, s.art) : null,
      h('h2', { class: 'tour-title' }, s.title),
      ...[].concat(s.body).map((p) => h('p', { class: 'tour-body' }, p)),
      s.actions ? h('div', { class: 'tour-actions' }, ...s.actions.map((a) => h('button', { class: `btn ${a.primary ? 'primary' : ''}`, onclick: () => { end(true); a.run(); } }, a.icon ? icon(a.icon, 18) : null, a.label))) : null,
      h('div', { class: 'tour-foot' },
        h('button', { class: 'btn ghost small tour-skip', onclick: () => end(true) }, last ? '' : 'Skip'),
        h('span', { class: 'tour-dots', 'aria-label': `Step ${i + 1} of ${steps.length}` }, ...steps.map((_, k) => h('span', { class: k === i ? 'on' : '' }))),
        h('span', { class: 'tour-nav' }, i > 0 ? back : null, next)));
    card.classList.toggle('featured', !!s.badge);
    place();
    // Layout can shift once a step's panel opens; settle the position.
    requestAnimationFrame(place);
    setTimeout(place, 250);
    next.focus({ preventScroll: true });
  };

  const onKey = (e) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); end(true); }
    else if (e.key === 'ArrowRight') { e.stopPropagation(); if (i < steps.length - 1) go(i + 1); }
    else if (e.key === 'ArrowLeft') { e.stopPropagation(); if (i > 0) go(i - 1); }
    else if (!['Enter', ' ', 'Tab'].includes(e.key)) e.stopPropagation();
  };
  document.addEventListener('keydown', onKey, true);
  window.addEventListener('resize', place);

  async function end(finished) {
    if (ended) return;
    ended = true;
    active = null;
    document.removeEventListener('keydown', onKey, true);
    window.removeEventListener('resize', place);
    root.classList.add('closing');
    setTimeout(() => root.remove(), 200);
    await steps[i]?.leave?.();
    if (finished) onDone?.();
  }
  active = { end };
  go(0);
}

const art = (name) => h('span', { class: 'tour-icon' }, icon(name, 30));

/** First visit: what Basis does, importing, and making a notebook. */
export function welcomeTour({ onNewNotebook, onImport }) {
  const isIPad = /iPad|Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1;
  const installed = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  runTour([
    {
      art: h('img', { class: 'tour-logo', src: 'icons/icon-192.png', alt: '' }),
      title: 'Welcome to Basis',
      body: 'Handwritten notes with a calculator built in. Here’s a quick look around. It takes less than a minute.',
    },
    {
      art: art('pen'),
      title: 'Write like on paper',
      body: [
        'Pens feel pressure and tilt from Apple Pencil or any stylus. Hold still at the end of a stroke to snap it into a clean shape.',
        'Scribble over ink to erase it. Double-tap with a finger to zoom the page edge to edge, and pull up past the last page to add another.',
      ],
    },
    {
      badge: 'Built in',
      art: art('calc'),
      title: 'A calculator that floats over your notes',
      body: 'Open the floating calculator in any notebook to work out answers without leaving the page, then drop the result onto the page as a live calculation card.',
    },
    {
      badge: 'Bring your notes',
      art: h('span', { class: 'tour-icon' }, icon('import', 30)),
      title: 'Switching from GoodNotes or Notability?',
      body: [
        'Import .goodnotes and .note files and your handwriting comes in as real ink you can keep writing on, erase and edit, with its paper and pages.',
        'In GoodNotes or Notability, export the notebook in its own format (.goodnotes or .note), then import it here. PDFs and Basis (.basis) notebooks work too.',
      ],
      actions: [{ label: 'Import a File…', icon: 'import', run: onImport }],
    },
    feature('ai') ? {
      badge: 'Optional',
      target: () => document.querySelector('[data-tour="ai"]'),
      art: art('sparkle'),
      title: 'AI study tools, whenever you want them',
      body: [
        'Connect your own Claude or Gemini account to search your handwriting and make practice exams, flashcards and summaries from your notes.',
        'No need to do it now. Set it up any time from AI in the sidebar; it walks you through each step.',
      ],
    } : null,
    {
      target: () => document.querySelector('[data-tour="new"]'),
      title: 'Make your first notebook',
      body: [
        'Tap New to start a notebook, make folders, or import files any time.',
        isIPad && !installed ? 'Tip: in Safari, tap Share → Add to Home Screen. Basis then opens like an app and keeps your notes safe.' : null,
      ].filter(Boolean),
      actions: [{ label: 'New Notebook', primary: true, icon: 'docPlus', run: onNewNotebook }],
    },
  ], { onDone: () => mark('welcome') });
  mark('welcome');
}

/** First notebook: the tools, with the floating calculator up front. */
export function editorTour(editor) {
  const root = editor.root;
  const q = (name) => () => root.querySelector(`[data-tour="${name}"]`);
  let calcWasOpen = false;
  runTour([
    {
      target: q('tools'),
      title: 'Your tools',
      body: 'Pen, highlighter, eraser, shapes, lasso and text. Tap a tool again to change its color and thickness in the bar below.',
    },
    {
      badge: 'Don’t miss this',
      target: q('calc'),
      title: 'The floating calculator',
      body: 'Tap here (or press K) any time to bring up a calculator over your page.',
      enter: () => { calcWasOpen = !!editor.floatCalc; },
    },
    {
      badge: 'Don’t miss this',
      target: () => editor.floatCalc,
      title: 'It floats over your notes',
      body: [
        'Drag it by the top bar to anywhere on the screen, and collapse it when you need room. It stays open as you move between pages.',
        'Tap Insert on Page to drop the result onto the page as a live calculation card.',
      ],
      enter: () => { if (!editor.floatCalc) editor.toggleCalculator(true); },
    },
    {
      target: q('pages'),
      title: 'Pages and zoom',
      body: 'Double-tap with a finger to zoom the page edge to edge. Pull up past the last page to add a new one, or use + here.',
      enter: () => { if (!calcWasOpen) editor.toggleCalculator(false); },
    },
    {
      target: q('more'),
      title: 'More',
      body: 'Export to PDF or a .basis notebook, insert calculation cards and PDFs, and turn scribble to erase on or off.',
    },
    {
      art: art('pen'),
      title: 'You’re all set',
      body: 'Find this tutorial again any time in Settings.',
    },
  ], { onDone: () => mark('editor') });
  mark('editor');
}
