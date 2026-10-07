// Shared UI pieces: dialogs, sheets, popovers, menus, toasts and inputs.
// Built in the page (the artifact frame blocks alert/confirm/prompt).

import { h, rgbaToHex, hexToRgba, colorsClose, css } from './util.js';
import { icon } from './icons.js';

let layer;
function overlayLayer() {
  if (!layer) { layer = h('div', { class: 'overlay-layer' }); document.body.append(layer); }
  return layer;
}

/** Modal sheet. `build(body, close)` fills it; returns a promise resolved on close. */
export function sheet({ title, build, wide = false, actions = null, onClose = null, className = '' }) {
  return new Promise((resolve) => {
    const backdrop = h('div', { class: 'backdrop' });
    const panel = h('div', { class: `sheet ${wide ? 'wide' : ''} ${className}`, role: 'dialog', 'aria-modal': 'true', 'aria-label': title || 'Dialog' });
    const body = h('div', { class: 'sheet-body' });
    let result;
    const close = (value) => {
      result = value;
      backdrop.classList.add('closing');
      panel.classList.add('closing');
      document.removeEventListener('keydown', onKey, true);
      setTimeout(() => { backdrop.remove(); panel.remove(); }, 160);
      onClose?.(value);
      resolve(result);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.stopPropagation(); close(undefined); }
    };
    document.addEventListener('keydown', onKey, true);
    backdrop.addEventListener('pointerdown', () => close(undefined));
    const header = h('div', { class: 'sheet-header' },
      h('button', { class: 'btn ghost', onclick: () => close(undefined) }, actions?.cancel ?? 'Close'),
      h('div', { class: 'sheet-title' }, title || ''),
      actions?.confirm ? h('button', { class: 'btn primary', onclick: () => { const v = actions.onConfirm?.(); if (v !== false) close(v ?? true); } }, actions.confirm) : h('span', { class: 'sheet-spacer' }));
    panel.append(header, body);
    overlayLayer().append(backdrop, panel);
    build(body, close, header);
    setTimeout(() => panel.querySelector('input:not([type=color]):not([type=range]), textarea')?.focus(), 60);
  });
}

/** Text input dialog (replaces prompt()). */
export function askText({ title, label, value = '', confirm = 'Save', placeholder = '' }) {
  let input;
  return sheet({
    title,
    actions: { confirm, onConfirm: () => input.value },
    build(body, close) {
      input = h('input', { class: 'field', id: 'ask-text', value, placeholder, 'aria-label': label || title });
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') close(input.value); });
      body.append(h('label', { class: 'form-row' }, label ? h('span', { class: 'form-label' }, label) : null, input));
      setTimeout(() => { input.focus(); input.select(); }, 50);
    },
  });
}

/** Confirmation dialog (replaces confirm()). */
export function confirmDialog({ title, message, confirm = 'Delete', destructive = true }) {
  return new Promise((resolve) => {
    sheet({
      title,
      className: 'compact',
      build(body, close) {
        body.append(
          h('p', { class: 'dialog-message' }, message),
          h('div', { class: 'dialog-actions' },
            h('button', { class: 'btn', onclick: () => close(false) }, 'Cancel'),
            h('button', { class: `btn ${destructive ? 'danger' : 'primary'}`, onclick: () => close(true) }, confirm)),
        );
      },
    }).then((v) => resolve(!!v));
  });
}

/** Popover anchored to an element. Closes on outside tap. */
export function popover(anchor, build, { align = 'start', className = '' } = {}) {
  closePopovers();
  const pop = h('div', { class: `popover ${className}`, role: 'dialog' });
  const close = () => { pop.remove(); document.removeEventListener('pointerdown', outside, true); document.removeEventListener('keydown', esc, true); };
  const outside = (e) => { if (!pop.contains(e.target) && !anchor.contains(e.target)) close(); };
  const esc = (e) => { if (e.key === 'Escape') { e.stopPropagation(); close(); } };
  pop.__close = close;
  build(pop, close);
  overlayLayer().append(pop);
  const r = anchor.getBoundingClientRect();
  const pw = pop.offsetWidth, ph = pop.offsetHeight;
  let x = align === 'end' ? r.right - pw : align === 'center' ? r.left + r.width / 2 - pw / 2 : r.left;
  let y = r.bottom + 6;
  x = Math.max(8, Math.min(window.innerWidth - pw - 8, x));
  if (y + ph > window.innerHeight - 8) y = Math.max(8, r.top - ph - 6);
  pop.style.left = x + 'px';
  pop.style.top = y + 'px';
  setTimeout(() => { document.addEventListener('pointerdown', outside, true); document.addEventListener('keydown', esc, true); }, 0);
  return close;
}

export function closePopovers() {
  document.querySelectorAll('.popover').forEach((p) => p.__close?.());
}

/** Menu of actions. items: {label, icon, action, danger, checked, disabled} | 'sep' | {header} */
export function menu(anchor, items, opts = {}) {
  return popover(anchor, (pop, close) => {
    pop.classList.add('menu');
    for (const it of items) {
      if (!it) continue;
      if (it === 'sep') { pop.append(h('div', { class: 'menu-sep' })); continue; }
      if (it.header) { pop.append(h('div', { class: 'menu-header' }, it.header)); continue; }
      const b = h('button', { class: `menu-item ${it.danger ? 'danger' : ''}`, disabled: it.disabled, role: 'menuitem' },
        it.checked != null ? h('span', { class: 'menu-check' }, it.checked ? icon('check', 16) : '') : null,
        it.icon ? icon(it.icon, 18) : null,
        h('span', { class: 'menu-label' }, it.label),
        it.hint ? h('span', { class: 'menu-hint' }, it.hint) : null);
      b.addEventListener('click', () => { if (!it.keepOpen) close(); it.action?.(); });
      pop.append(b);
    }
  }, opts);
}

let toastTimer;
export function toast(message) {
  let t = document.querySelector('.toast');
  if (!t) { t = h('div', { class: 'toast', role: 'status', 'aria-live': 'polite' }); document.body.append(t); }
  t.textContent = message;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
}

export function segmented(options, value, onChange, { label } = {}) {
  const wrap = h('div', { class: 'segmented', role: 'radiogroup', 'aria-label': label || '' });
  const render = (v) => {
    wrap.replaceChildren(...options.map((o) => {
      const b = h('button', { class: `seg ${o.value === v ? 'on' : ''}`, role: 'radio', 'aria-checked': String(o.value === v), title: o.title || '' },
        o.icon ? icon(o.icon, 18) : null, o.label ? h('span', {}, o.label) : null);
      b.addEventListener('click', () => { render(o.value); onChange(o.value); });
      return b;
    }));
  };
  render(value);
  wrap.setValue = render;
  return wrap;
}

export function selectField(id, options, value, onChange) {
  const s = h('select', { class: 'field', id });
  for (const o of options) {
    if (o.group) {
      const g = h('optgroup', { label: o.group });
      for (const x of o.options) g.append(h('option', { value: x.value, selected: x.value === value }, x.label));
      s.append(g);
    } else s.append(h('option', { value: o.value, selected: o.value === value }, o.label));
  }
  s.addEventListener('change', () => onChange(s.value));
  return s;
}

export function slider(id, { min, max, step = 0.01, value, format = (v) => v, onInput }) {
  const out = h('span', { class: 'slider-value' }, format(value));
  const r = h('input', { type: 'range', id, min, max, step, value, class: 'range' });
  r.addEventListener('input', () => { out.textContent = format(Number(r.value)); onInput(Number(r.value)); });
  return { el: h('div', { class: 'slider-row' }, r, out), input: r, set: (v) => { r.value = v; out.textContent = format(v); } };
}

/** Swatch row with optional custom color input. */
export function swatches(colors, current, onPick, { custom = true, extra = [] } = {}) {
  const wrap = h('div', { class: 'swatches' });
  const all = [...colors, ...extra];
  const render = (cur) => {
    wrap.replaceChildren(
      ...all.map((c, i) => {
        const on = cur && colorsClose(c, cur);
        const b = h('button', { class: `swatch ${on ? 'on' : ''} ${i === colors.length ? 'sep-before' : ''}`, style: { '--c': css({ ...c, a: 1 }) }, 'aria-label': 'Color ' + rgbaToHex(c), 'aria-pressed': String(!!on) });
        b.addEventListener('click', () => { render(c); onPick(c); });
        return b;
      }),
      custom ? (() => {
        const input = h('input', { type: 'color', class: 'swatch-custom', value: cur ? rgbaToHex(cur) : '#1f4fd8', 'aria-label': 'Custom color' });
        input.addEventListener('input', () => { const c = hexToRgba(input.value); onPick(c, true); });
        input.addEventListener('change', () => render(hexToRgba(input.value)));
        return input;
      })() : null,
    );
  };
  render(current);
  wrap.setValue = render;
  return wrap;
}

export function toggle(id, label, checked, onChange) {
  const input = h('input', { type: 'checkbox', id, checked, class: 'switch' });
  input.addEventListener('change', () => onChange(input.checked));
  return h('label', { class: 'toggle-row', for: id }, h('span', {}, label), input);
}

export function iconButton(name, title, onClick, { cls = '', size = 22 } = {}) {
  const b = h('button', { class: `icon-btn ${cls}`, title, 'aria-label': title }, icon(name, size));
  if (onClick) b.addEventListener('click', onClick);
  return b;
}

export function pickFile(accept, multiple = false) {
  return new Promise((resolve) => {
    const input = h('input', { type: 'file', accept: accept || null, multiple, style: { display: 'none' } });
    input.addEventListener('change', () => { resolve([...input.files]); input.remove(); });
    document.body.append(input);
    input.click();
  });
}

/** Saves a blob as a file. Inside some sandboxed viewers downloads are blocked. */
export function saveFile(blob, filename) {
  try {
    const url = URL.createObjectURL(blob);
    const a = h('a', { href: url, download: filename, style: { display: 'none' } });
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 4000);
    return true;
  } catch {
    return false;
  }
}
