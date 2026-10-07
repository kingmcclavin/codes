// Calculator screens: the keypad (full and floating), tape, variables,
// formula library, unit converter, history and graphs.

import { h, uuid, storage, relativeTime, clamp } from './util.js';
import { icon } from './icons.js';
import { sheet, menu, toast, popover, selectField, confirmDialog, iconButton } from './ui.js';
import { calc } from './calc/store.js';
import { feature } from './features.js';
import { CalculatorEngine, formatNumber, plainNumber, prettyMath, FUNCTION_CATALOG, CONSTANTS, tokenize, outputNames, formulaLines } from './calc/engine.js';
import { UNITS, UNIT_CATEGORIES, unitsIn, convertUnit, parseUnit } from './calc/units.js';

const CONTINUING = new Set(['+', '-', '×', '÷', '^', '²', '!', '%', '°']);

/** The keypad with display. `compact` for the floating calculator. */
export function calculatorPad({ compact = false, onInsert = null } = {}) {
  const sciKey = compact ? 'basis.calcSciFloating' : 'basis.calcSciFull';
  let scientific = storage.get(sciKey, !compact);
  let result = null; // { expression, value }
  let error = null;

  const root = h('div', { class: `calc-pad ${compact ? 'compact' : ''}`, tabindex: compact ? null : '0' });
  const angleBtn = h('button', { class: 'chip accent', title: 'Angle unit' });
  const sciBtn = h('button', { class: 'chip' });
  const status = h('div', { class: 'calc-status' });
  const main = h('div', { class: 'calc-main', 'aria-live': 'polite' });
  const display = h('div', { class: 'calc-display' }, h('div', { class: 'calc-display-top' }, angleBtn, sciBtn, status), main);
  const sciKeys = h('div', { class: 'calc-keys sci' });
  const basicKeys = h('div', { class: 'calc-keys basic' });
  const insertBtn = onInsert ? h('button', { class: 'btn wide', onclick: () => { const e = insertable(); if (e) onInsert(e); } }, icon('insert', 18), 'Insert on Page') : null;
  root.append(display, sciKeys, basicKeys, insertBtn);

  const type = (s) => {
    error = null;
    if (result) {
      calc.draft = CONTINUING.has(s) ? plainNumber(result.value) + s : s;
      result = null;
    } else calc.draft += s;
    update();
  };
  const clear = () => { calc.draft = ''; result = null; error = null; update(); };
  const backspace = () => {
    if (result) return clear();
    calc.draft = Array.from(calc.draft).slice(0, -1).join('');
    error = null;
    update();
  };
  const evaluate = () => {
    const t = calc.draft.trim();
    if (!t || result) return;
    try {
      const r = calc.evaluate(t);
      result = { expression: t, value: r.value };
      calc.draft = '';
    } catch (e) { error = e.message; }
    update();
  };
  const insertable = () => (result ? result.expression : calc.draft.trim() || null);

  const key = (title, kind, action, aria) => {
    const b = h('button', { class: `key ${kind}`, 'aria-label': aria || title }, title);
    b.addEventListener('click', action);
    return b;
  };
  const d = (x) => key(x, 'digit', () => type(x));
  const fn = (title, text, aria) => key(title, 'fn', () => type(text), aria);
  basicKeys.append(
    key('AC', 'clear', clear, 'All clear'), fn('(', '('), fn(')', ')'), key('÷', 'op', () => type('÷'), 'Divide'),
    d('7'), d('8'), d('9'), key('×', 'op', () => type('×'), 'Multiply'),
    d('4'), d('5'), d('6'), key('−', 'op', () => type('-'), 'Minus'),
    d('1'), d('2'), d('3'), key('+', 'op', () => type('+'), 'Plus'),
    d('0'), key('.', 'digit', () => type('.'), 'Decimal point'), key('⌫', 'fn', backspace, 'Delete'), key('=', 'equals', evaluate, 'Equals'),
  );
  const moreBtn = key('more', 'fn', () => {
    popover(moreBtn, (pop, close) => {
      pop.classList.add('picker');
      pop.append(h('div', { class: 'picker-head' }, 'Functions'));
      for (const f of FUNCTION_CATALOG) {
        pop.append(h('button', { class: 'picker-row', onclick: () => { close(); type(f.insert); } }, h('code', {}, f.name), h('span', {}, f.help)));
      }
      pop.append(h('div', { class: 'picker-head' }, 'Constants'));
      for (const c of CONSTANTS) {
        pop.append(h('button', { class: 'picker-row', onclick: () => { close(); type(c.id); } }, h('code', {}, c.symbol), h('span', {}, `${c.name} · ${c.id} = ${formatNumber(c.value)} ${c.unit}`)));
      }
    }, { align: 'end' });
  }, 'More functions and constants');
  sciKeys.append(
    fn('sin', 'sin('), fn('cos', 'cos('), fn('tan', 'tan('), fn('√', '√(', 'Square root'), fn('x²', '²', 'Squared'), fn('xʸ', '^', 'Power'),
    fn('sin⁻¹', 'asin(', 'Inverse sine'), fn('cos⁻¹', 'acos(', 'Inverse cosine'), fn('tan⁻¹', 'atan(', 'Inverse tangent'), fn('log', 'log('), fn('ln', 'ln('), fn('eˣ', 'exp(', 'e to the x'),
    fn('π', 'π', 'Pi'), fn('e', 'e'), fn('°', '°', 'Degrees'), fn('n!', '!', 'Factorial'), fn('ans', 'ans', 'Last answer'), moreBtn,
  );

  angleBtn.addEventListener('click', () => { calc.setAngleMode(calc.angleMode === 'degrees' ? 'radians' : 'degrees'); update(); });
  sciBtn.addEventListener('click', () => { scientific = !scientific; storage.set(sciKey, scientific); update(); });

  function update() {
    angleBtn.textContent = calc.angleMode === 'degrees' ? 'DEG' : 'RAD';
    sciBtn.textContent = scientific ? 'Basic' : 'Scientific';
    sciKeys.hidden = !scientific;
    status.className = 'calc-status';
    if (error) { status.textContent = error; status.classList.add('error'); } else if (result) status.textContent = prettyMath(result.expression) + ' =';
    else {
      const t = calc.draft.trim();
      let preview = '';
      if (t) { try { preview = '= ' + formatNumber(calc.engine.evaluateLine(t).value); } catch { /* incomplete */ } }
      status.textContent = preview;
      status.classList.add('preview');
    }
    main.textContent = result ? formatNumber(result.value) : (calc.draft ? prettyMath(calc.draft) : '0');
    main.classList.toggle('long', main.textContent.length > (compact ? 14 : 18));
    if (insertBtn) insertBtn.disabled = !insertable();
  }

  // Keyboard input.
  root.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Enter') { e.preventDefault(); evaluate(); return; }
    if (e.key === 'Backspace') { e.preventDefault(); backspace(); return; }
    if (e.key === 'Escape') { clear(); return; }
    if (e.key.length === 1 && /[0-9.+\-*/^()!%,=a-zA-Z_ ]/.test(e.key)) {
      e.preventDefault();
      type(e.key === '*' ? '×' : e.key === '/' ? '÷' : e.key);
    }
  });

  root.refresh = update;
  root.setDraft = (text) => { calc.draft = text; result = null; error = null; update(); };
  update();
  return root;
}

/** Full-screen calculator: tape of answers and the keypad. */
export function calculatorScreen({ insertIntoNote } = {}) {
  const tape = h('div', { class: 'calc-tape', 'aria-label': 'Recent calculations' });
  const pad = calculatorPad();
  const moreBtn = iconButton('more', 'More', () => {
    menu(moreBtn, [
      { label: 'Variables…', icon: 'function', action: () => variablesSheet() },
      feature('toolbox') ? { label: 'Save as Formula…', icon: 'docPlus', action: saveAsFormula } : null,
      'sep',
      { label: 'Clear Tape', icon: 'trash', danger: true, action: () => calc.deleteHistory(new Set(calc.history.filter((r) => !r.formulaId).map((r) => r.id))) },
    ], { align: 'end' });
  });
  const root = h('section', { class: 'screen calc-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'Calculator'), h('div', { class: 'header-actions' }, moreBtn)),
    h('div', { class: 'calc-layout' }, tape, h('div', { class: 'calc-pad-wrap' }, pad)));

  function renderTape() {
    const items = calc.history.filter((r) => !r.formulaId).slice(0, 40).reverse();
    if (!items.length) {
      tape.replaceChildren(h('div', { class: 'empty-state' }, icon('calc', 40), h('p', {}, 'Your answers will appear here.'), h('p', { class: 'muted small' }, 'Tip: type m = 5 to save a variable you can reuse.')));
      return;
    }
    tape.replaceChildren(...items.map((r) => {
      const row = h('div', { class: 'tape-row' },
        h('button', { class: 'tape-entry', title: 'Use again', onclick: () => pad.setDraft(r.expression) },
          h('span', { class: 'tape-expr' }, prettyMath(r.expression)),
          h('span', { class: 'tape-value' }, r.results[0] ? formatNumber(r.results[0].value) : '')));
      const more = iconButton('more', 'Actions', () => menu(more, [
        { label: 'Copy Result', icon: 'copy', action: () => copyText(r.results[0] ? plainNumber(r.results[0].value) : '') },
        { label: 'Use Again', icon: 'redo', action: () => pad.setDraft(r.expression) },
        insertIntoNote ? { label: 'Insert into Notebook', icon: 'insert', action: () => insertIntoNote(r.expression) } : null,
        { label: 'Delete', icon: 'trash', danger: true, action: () => calc.deleteHistory(new Set([r.id])) },
      ], { align: 'end' }), { cls: 'small' });
      row.append(more);
      return row;
    }));
    tape.scrollTop = tape.scrollHeight;
  }

  function saveAsFormula() {
    const t = calc.draft.trim() || calc.history.find((r) => !r.formulaId)?.expression;
    if (!t) { toast('Type a calculation first.'); return; }
    const expression = CalculatorEngine.splitAssignment(t) ? t : `result = ${t}`;
    formulaEditor({ id: uuid(), name: 'New Formula', category: 'Custom', summary: '', expression, variables: [] }, true);
  }

  const onChange = () => { renderTape(); pad.refresh(); };
  calc.addEventListener('change', onChange);
  root.cleanup = () => calc.removeEventListener('change', onChange);
  renderTape();
  setTimeout(() => pad.focus(), 50);
  return root;
}

export function copyText(text) {
  const done = () => toast('Copied');
  try {
    navigator.clipboard.writeText(text).then(done, () => toast(text));
  } catch { toast(text); }
}

// ---------- Variables ----------

export function variablesSheet() {
  sheet({
    title: 'Variables',
    build(body) {
      const list = h('div', { class: 'list' });
      const addBtn = h('button', { class: 'btn', onclick: () => variableEditor(null) }, icon('plus', 18), 'Add Variable');
      body.append(h('div', { class: 'row-actions' }, addBtn), list);
      const render = () => {
        if (!calc.variables.length) {
          list.replaceChildren(h('div', { class: 'empty-state small' }, h('p', {}, 'No variables yet.'), h('p', { class: 'muted small' }, 'Type m = 5 in the calculator, or add one here.')));
          return;
        }
        list.replaceChildren(...calc.variables.map((v) => {
          const r = calc.valueOfVariable(v.name);
          return h('div', { class: 'list-row' },
            h('div', { class: 'list-main' }, h('code', { class: 'var-name' }, v.name), Number.isNaN(Number(v.expression)) ? h('div', { class: 'muted small mono' }, v.expression) : null),
            h('span', { class: 'mono muted' }, r.ok ? formatNumber(r.value) + (v.unit ? ' ' + v.unit : '') : '—'),
            iconButton('pencilLine', 'Edit', () => variableEditor(v), { cls: 'small' }),
            iconButton('trash', 'Delete', () => calc.deleteVariable(v.name), { cls: 'small danger' }));
        }));
      };
      calc.addEventListener('change', render);
      render();
    },
    onClose: () => {},
  });
}

function variableEditor(variable) {
  const name = h('input', { class: 'field mono', id: 'var-name', placeholder: 'Name (e.g. m)', value: variable?.name || '', disabled: !!variable, autocapitalize: 'off', spellcheck: 'false' });
  const expr = h('input', { class: 'field mono', id: 'var-expr', placeholder: 'Value or expression (5, 2.1e3, 30°, m*g0)', value: variable?.expression || '', autocapitalize: 'off', spellcheck: 'false' });
  const unit = h('input', { class: 'field', id: 'var-unit', placeholder: 'Unit (optional, e.g. kg)', value: variable?.unit || '' });
  const status = h('p', { class: 'form-help' });
  const valid = () => {
    try { const t = tokenize(name.value.trim()); if (t.length !== 1 || t[0].t !== 'id') return false; } catch { return false; }
    try { calc.engine.evaluateExpression(expr.value); return true; } catch { return false; }
  };
  const refresh = () => {
    if (!expr.value.trim()) { status.textContent = 'Variables can hold numbers, angles (30°), scientific notation (6.02e23), constants or expressions of other variables.'; return; }
    try { status.textContent = '= ' + formatNumber(calc.engine.evaluateExpression(expr.value)); } catch (e) { status.textContent = e.message; }
  };
  [name, expr].forEach((i) => i.addEventListener('input', refresh));
  sheet({
    title: variable ? `Edit ${variable.name}` : 'New Variable',
    className: 'compact',
    actions: {
      confirm: 'Save',
      onConfirm: () => {
        if (!valid()) { status.textContent = 'Names start with a letter and contain no spaces, and the value must calculate.'; return false; }
        calc.setVariable({ name: name.value.trim(), expression: expr.value.trim(), unit: unit.value.trim() });
        return true;
      },
    },
    build(body) { body.append(name, expr, unit, status); refresh(); },
  });
}

// ---------- Formulas ----------

export function formulasScreen({ insertIntoNote } = {}) {
  let selected = storage.get('basis.selectedFormula', null);
  let query = '';
  const list = h('nav', { class: 'formula-list', 'aria-label': 'Formulas' });
  const detail = h('div', { class: 'formula-detail' });
  const search = h('input', { class: 'field search', id: 'formula-search', placeholder: 'Search formulas', type: 'search' });
  search.addEventListener('input', () => { query = search.value.toLowerCase(); renderList(); });
  const newBtn = iconButton('plus', 'New Formula', () => formulaEditor({ id: uuid(), name: 'New Formula', category: 'Custom', summary: '', expression: 'y = 2x + 1', variables: [] }, true));
  const root = h('section', { class: 'screen formulas-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'Formulas'), h('div', { class: 'header-actions' }, newBtn)),
    h('div', { class: 'split' }, h('div', { class: 'split-list' }, search, list), detail));

  function renderList() {
    list.replaceChildren();
    for (const cat of calc.categories) {
      const items = calc.allFormulas.filter((f) => f.category === cat && (!query || f.name.toLowerCase().includes(query) || f.summary?.toLowerCase().includes(query)));
      if (!items.length) continue;
      list.append(h('div', { class: 'list-header' }, cat));
      for (const f of items) {
        const b = h('button', { class: `list-item ${f.id === selected ? 'on' : ''}`, onclick: () => { selected = f.id; storage.set('basis.selectedFormula', f.id); renderList(); renderDetail(); root.classList.add('show-detail'); } },
          h('span', { class: 'list-item-title' }, f.name), h('span', { class: 'list-item-sub' }, f.summary || formulaLines(f)[0] || ''));
        list.append(b);
      }
    }
  }

  function renderDetail() {
    const f = calc.formula(selected);
    if (!f) { detail.replaceChildren(h('div', { class: 'empty-state' }, icon('function', 40), h('p', {}, 'Choose a formula to calculate with it.'))); return; }
    const engine = calc.engine;
    const inputs = engine.inputs(f);
    const saved = storage.get('basis.formulaInputs.' + f.id, {});
    const fields = {};
    const outBox = h('div', { class: 'formula-results' });
    const err = engine.validate(f);
    const back = h('button', { class: 'btn ghost back-only', onclick: () => root.classList.remove('show-detail') }, icon('back', 18), 'Formulas');
    const actions = h('div', { class: 'header-actions' });
    const more = iconButton('more', 'Formula actions', () => menu(more, [
      { label: 'Duplicate', icon: 'duplicate', action: () => { const c = calc.duplicateFormula(f); selected = c.id; renderList(); renderDetail(); } },
      !f.isBuiltIn ? { label: 'Edit…', icon: 'pencilLine', action: () => formulaEditor(f, false) } : null,
      !f.isBuiltIn ? { label: 'Delete', icon: 'trash', danger: true, action: async () => { if (await confirmDialog({ title: `Delete “${f.name}”?`, message: 'This formula will be removed. History entries stay.' })) { calc.deleteFormula(f.id); selected = null; } } } : null,
    ], { align: 'end' }));
    actions.append(more);
    const run = () => {
      const values = {};
      for (const n of inputs) {
        const t = fields[n].value.trim();
        if (!t) continue;
        try { values[n] = engine.evaluateExpression(t); } catch { /* left empty */ }
      }
      storage.set('basis.formulaInputs.' + f.id, Object.fromEntries(inputs.map((n) => [n, fields[n].value])));
      const r = engine.evaluateFormula(f, values);
      renderResults(r);
      return { r, values };
    };
    const renderResults = (r) => {
      if (r.error) { outBox.replaceChildren(h('p', { class: 'error' }, r.error.message)); return; }
      outBox.replaceChildren(...r.outputs.map((o) => h('div', { class: 'result-row' },
        h('code', { class: 'result-name' }, o.name),
        o.error ? h('span', { class: 'muted small' }, o.error.kind === 'missing' ? `needs ${o.error.extra}` : o.error.message)
          : h('span', { class: 'result-value' }, formatNumber(o.value), o.unit ? h('span', { class: 'unit' }, ' ' + o.unit) : null))));
    };
    const form = h('div', { class: 'formula-inputs' });
    for (const n of inputs) {
      const meta = f.variables?.find((v) => v.name === n);
      const input = h('input', { class: 'field mono', id: `fi-${n}`, inputmode: 'decimal', placeholder: meta?.defaultValue ? `default ${meta.defaultValue}` : (calc.variables.some((v) => v.name === n) ? 'uses calculator variable' : 'value'), value: saved[n] || '' });
      input.addEventListener('input', run);
      fields[n] = input;
      form.append(h('label', { class: 'input-row', for: `fi-${n}` }, h('code', { class: 'input-name' }, n), h('span', { class: 'input-label' }, meta?.label || ''), input, h('span', { class: 'unit' }, meta?.unit || '')));
    }
    const calcBtn = h('button', { class: 'btn primary', onclick: () => { const { r } = run(); calc.runFormula(f, collect()); if (!r.error) toast('Saved to History'); } }, 'Calculate');
    const collect = () => {
      const values = {};
      for (const n of inputs) { const t = fields[n].value.trim(); if (t) { try { values[n] = engine.evaluateExpression(t); } catch { /* skip */ } } }
      return values;
    };
    const insertBtn = insertIntoNote ? h('button', { class: 'btn', onclick: () => {
      const { r, values } = run();
      if (r.error) return;
      const lines = [...inputs.filter((n) => values[n] != null).map((n) => `${n} = ${plainNumber(values[n])}`), ...formulaLines(f)];
      insertIntoNote(lines.join('\n'));
    } }, icon('insert', 18), 'Insert into Notebook') : null;
    detail.replaceChildren(
      h('div', { class: 'detail-head' }, back, actions),
      h('h2', {}, f.name),
      f.summary ? h('p', { class: 'muted' }, f.summary) : null,
      h('pre', { class: 'formula-expr' }, f.expression),
      err ? h('p', { class: 'error' }, err.message) : null,
      inputs.length ? h('h3', { class: 'section-label' }, 'Inputs') : null,
      form,
      h('div', { class: 'row-actions' }, calcBtn, insertBtn),
      h('h3', { class: 'section-label' }, 'Results'),
      outBox,
    );
    run();
  }

  const onChange = () => { renderList(); renderDetail(); };
  calc.addEventListener('change', onChange);
  root.cleanup = () => calc.removeEventListener('change', onChange);
  renderList();
  renderDetail();
  return root;
}

function formulaEditor(formula, isNew) {
  const f = structuredClone(formula);
  const name = h('input', { class: 'field', id: 'fe-name', value: f.name, placeholder: 'Name' });
  const category = h('input', { class: 'field', id: 'fe-cat', value: f.category, placeholder: 'Category', list: 'fe-cats' });
  const cats = h('datalist', { id: 'fe-cats' }, calc.categories.map((c) => h('option', { value: c })));
  const summary = h('input', { class: 'field', id: 'fe-sum', value: f.summary || '', placeholder: 'Short description (optional)' });
  const expr = h('textarea', { class: 'field mono', id: 'fe-expr', rows: 5, spellcheck: 'false' }, f.expression);
  const status = h('p', { class: 'form-help' });
  const varsBox = h('div', { class: 'var-meta' });
  const meta = Object.fromEntries((f.variables || []).map((v) => [v.name, { ...v }]));
  const refresh = () => {
    const draft = { ...f, expression: expr.value, variables: Object.values(meta) };
    const engine = calc.engine;
    const err = engine.validate(draft);
    status.textContent = err ? err.message : 'One statement per line, e.g. KE = ½ m v². Inputs are detected automatically.';
    status.classList.toggle('error', !!err);
    const names = [...new Set([...engine.inputs(draft), ...outputNames(draft)])];
    varsBox.replaceChildren(...names.map((n) => {
      meta[n] = meta[n] || { name: n, label: '', unit: '', defaultValue: '' };
      const lbl = h('input', { class: 'field', placeholder: 'meaning', value: meta[n].label, 'aria-label': `${n} meaning` });
      const un = h('input', { class: 'field', placeholder: 'unit', value: meta[n].unit, 'aria-label': `${n} unit` });
      lbl.addEventListener('input', () => { meta[n].label = lbl.value; });
      un.addEventListener('input', () => { meta[n].unit = un.value; un.classList.toggle('invalid', !!un.value && !parseUnit(un.value)); });
      return h('div', { class: 'var-meta-row' }, h('code', {}, n), lbl, un);
    }));
  };
  expr.addEventListener('input', refresh);
  sheet({
    title: isNew ? 'New Formula' : 'Edit Formula',
    wide: true,
    actions: {
      confirm: 'Save',
      onConfirm: () => {
        const draft = { ...f, name: name.value.trim() || 'Formula', category: category.value.trim() || 'Custom', summary: summary.value.trim(), expression: expr.value };
        const names = new Set([...calc.engine.inputs(draft), ...outputNames(draft)]);
        draft.variables = Object.values(meta).filter((v) => names.has(v.name));
        if (calc.engine.validate(draft)) { refresh(); return false; }
        calc.saveFormula(draft);
        storage.set('basis.selectedFormula', draft.id);
        return true;
      },
    },
    build(body) {
      body.append(name, h('div', { class: 'two-col' }, category, summary), cats, expr, status, h('h3', { class: 'section-label' }, 'Symbols'), varsBox);
      refresh();
    },
  });
}

// ---------- Unit converter ----------

export function unitConverterScreen() {
  let cat = storage.get('basis.unitCat', 'Length');
  const value = h('input', { class: 'field big mono', id: 'uc-value', inputmode: 'decimal', value: storage.get('basis.unitValue', '1') });
  const fromHost = h('div'), toHost = h('div');
  const out = h('div', { class: 'convert-result', 'aria-live': 'polite' });
  const all = h('div', { class: 'convert-all' });
  let from, to;
  const catSel = selectField('uc-cat', UNIT_CATEGORIES.map((c) => ({ value: c, label: c })), cat, (v) => { cat = v; storage.set('basis.unitCat', v); buildUnits(true); });
  const swap = iconButton('convert', 'Swap units', () => { const a = from.value; from.value = to.value; to.value = a; update(); });

  function buildUnits(reset) {
    const units = unitsIn(cat);
    const opts = units.map((u) => ({ value: u.symbol, label: `${u.symbol} — ${u.name}` }));
    const f0 = reset ? units[0].symbol : storage.get('basis.unitFrom', units[0].symbol);
    const t0 = reset ? (units[1] || units[0]).symbol : storage.get('basis.unitTo', (units[1] || units[0]).symbol);
    from = selectField('uc-from', opts, units.some((u) => u.symbol === f0) ? f0 : units[0].symbol, update);
    to = selectField('uc-to', opts, units.some((u) => u.symbol === t0) ? t0 : (units[1] || units[0]).symbol, update);
    fromHost.replaceChildren(from); toHost.replaceChildren(to);
    update();
  }

  function update() {
    storage.set('basis.unitValue', value.value);
    storage.set('basis.unitFrom', from.value);
    storage.set('basis.unitTo', to.value);
    let x;
    try { x = calc.engine.evaluateExpression(value.value || '0'); } catch (e) { out.textContent = e.message; all.replaceChildren(); return; }
    try {
      const r = convertUnit(x, from.value, to.value);
      out.replaceChildren(h('span', { class: 'mono' }, `${formatNumber(x)} ${from.value} =`), h('strong', { class: 'mono' }, `${formatNumber(r)} ${to.value}`));
    } catch (e) { out.textContent = e.message; }
    all.replaceChildren(...unitsIn(cat).map((u) => {
      let v = '—';
      try { v = formatNumber(convertUnit(x, from.value, u.symbol)); } catch { /* incompatible */ }
      return h('div', { class: 'convert-row' }, h('span', { class: 'mono' }, v), h('span', { class: 'muted' }, `${u.symbol} · ${u.name}`));
    }));
  }
  value.addEventListener('input', update);
  const root = h('section', { class: 'screen convert-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'Unit Converter')),
    h('div', { class: 'convert-card' },
      h('label', { class: 'form-row', for: 'uc-cat' }, h('span', { class: 'form-label' }, 'Quantity'), catSel),
      h('label', { class: 'form-row', for: 'uc-value' }, h('span', { class: 'form-label' }, 'Value'), value),
      h('div', { class: 'convert-units' }, h('label', { class: 'form-row' }, h('span', { class: 'form-label' }, 'From'), fromHost), swap, h('label', { class: 'form-row' }, h('span', { class: 'form-label' }, 'To'), toHost)),
      out),
    h('h3', { class: 'section-label' }, 'In every unit'),
    all);
  buildUnits(false);
  return root;
}

// ---------- History ----------

export function historyScreen({ insertIntoNote, openCalculator } = {}) {
  const list = h('div', { class: 'history-list' });
  const clearBtn = h('button', { class: 'btn ghost danger', onclick: async () => {
    if (await confirmDialog({ title: 'Clear all history?', message: 'Every calculator and formula entry will be removed.', confirm: 'Clear History' })) calc.deleteHistory(new Set(calc.history.map((r) => r.id)));
  } }, 'Clear');
  const root = h('section', { class: 'screen history-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'History'), h('div', { class: 'header-actions' }, clearBtn)), list);
  const render = () => {
    clearBtn.disabled = !calc.history.length;
    if (!calc.history.length) { list.replaceChildren(h('div', { class: 'empty-state' }, icon('history', 40), h('p', {}, 'Calculations and formula runs appear here.'))); return; }
    list.replaceChildren(...calc.history.slice(0, 200).map((r) => {
      const more = iconButton('more', 'Actions', () => menu(more, [
        { label: 'Copy Result', icon: 'copy', action: () => copyText(r.results.map((x) => `${x.name} = ${plainNumber(x.value)}`).join('\n')) },
        !r.formulaId && openCalculator ? { label: 'Open in Calculator', icon: 'calc', action: () => { calc.draft = r.expression; openCalculator(); } } : null,
        insertIntoNote ? { label: 'Insert into Notebook', icon: 'insert', action: () => insertIntoNote(r.formulaId ? [...r.inputs.map((x) => `${x.name} = ${plainNumber(x.value)}`), ...r.expression.split('\n')].join('\n') : r.expression) } : null,
        { label: 'Delete', icon: 'trash', danger: true, action: () => calc.deleteHistory(new Set([r.id])) },
      ], { align: 'end' }), { cls: 'small' });
      return h('article', { class: 'history-item' },
        h('div', { class: 'history-top' }, h('strong', {}, r.title), h('span', { class: 'muted small' }, relativeTime(r.date)), more),
        r.inputs?.length ? h('div', { class: 'mono small muted' }, r.inputs.map((x) => `${x.name} = ${formatNumber(x.value)}${x.unit ? ' ' + x.unit : ''}`).join('   ')) : h('div', { class: 'mono small muted' }, prettyMath(r.expression)),
        h('div', { class: 'mono' }, r.results.map((x) => `${x.name === '=' ? '=' : x.name + ' ='} ${formatNumber(x.value)}${x.unit ? ' ' + x.unit : ''}`).join('   ')));
    }));
  };
  calc.addEventListener('change', render);
  root.cleanup = () => calc.removeEventListener('change', render);
  render();
  return root;
}

// ---------- Graphs ----------

const GRAPH_COLORS = ['#2f6bff', '#e5484d', '#30a46c', '#f76b15', '#9b51e0', '#0891b2'];

export function graphScreen() {
  let fns = storage.get('basis.graphFns', ['sin(x)', 'x^2/4 - 1']);
  let view = storage.get('basis.graphView', { cx: 0, cy: 0, scale: 40 }); // px per unit
  const canvas = h('canvas', { class: 'graph-canvas', 'aria-label': 'Graph of the functions', role: 'img' });
  const list = h('div', { class: 'graph-fns' });
  const readout = h('div', { class: 'graph-readout mono small' });
  const reset = h('button', { class: 'btn ghost', onclick: () => { view = { cx: 0, cy: 0, scale: 40 }; draw(); } }, 'Reset View');
  const root = h('section', { class: 'screen graph-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'Graphs'), h('div', { class: 'header-actions' }, reset)),
    h('div', { class: 'graph-layout' }, h('div', { class: 'graph-side' }, list, h('p', { class: 'muted small' }, 'Use x as the variable. Drag to pan, scroll or pinch to zoom.'), readout), h('div', { class: 'graph-host' }, canvas)));

  const renderList = () => {
    list.replaceChildren(...fns.map((f, i) => {
      const input = h('input', { class: 'field mono', value: f, 'aria-label': `Function ${i + 1}`, spellcheck: 'false' });
      input.addEventListener('input', () => { fns[i] = input.value; storage.set('basis.graphFns', fns); draw(); });
      return h('div', { class: 'graph-fn' }, h('span', { class: 'graph-dot', style: { background: GRAPH_COLORS[i % GRAPH_COLORS.length] } }), h('span', { class: 'mono' }, 'y ='), input,
        iconButton('close', 'Remove', () => { fns.splice(i, 1); storage.set('basis.graphFns', fns); renderList(); draw(); }, { cls: 'small' }));
    }), h('button', { class: 'btn ghost', onclick: () => { fns.push(''); renderList(); list.querySelector('.graph-fn:last-of-type input')?.focus(); } }, icon('plus', 18), 'Add Function'));
  };

  function draw() {
    storage.set('basis.graphView', view);
    const r = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    if (!r.width) return;
    canvas.width = r.width * dpr; canvas.height = r.height * dpr;
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const W = r.width, H = r.height, s = view.scale;
    const X = (x) => W / 2 + (x - view.cx) * s, Y = (y) => H / 2 - (y - view.cy) * s;
    const styles = getComputedStyle(root);
    const grid = styles.getPropertyValue('--line').trim(), axis = styles.getPropertyValue('--muted').trim(), text = styles.getPropertyValue('--muted').trim();
    ctx.clearRect(0, 0, W, H);
    const raw = 80 / s, p10 = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 5, 10].map((m) => m * p10).find((v) => v >= raw);
    ctx.lineWidth = 1; ctx.strokeStyle = grid; ctx.beginPath();
    const x0 = view.cx - W / 2 / s, x1 = view.cx + W / 2 / s, y0 = view.cy - H / 2 / s, y1 = view.cy + H / 2 / s;
    for (let x = Math.ceil(x0 / step) * step; x <= x1; x += step) { ctx.moveTo(X(x), 0); ctx.lineTo(X(x), H); }
    for (let y = Math.ceil(y0 / step) * step; y <= y1; y += step) { ctx.moveTo(0, Y(y)); ctx.lineTo(W, Y(y)); }
    ctx.stroke();
    ctx.strokeStyle = axis; ctx.beginPath(); ctx.moveTo(X(0), 0); ctx.lineTo(X(0), H); ctx.moveTo(0, Y(0)); ctx.lineTo(W, Y(0)); ctx.stroke();
    ctx.fillStyle = text; ctx.font = '11px "IBM Plex Mono", monospace';
    const ax = clamp(X(0), 4, W - 30), ay = clamp(Y(0), 12, H - 4);
    for (let x = Math.ceil(x0 / step) * step; x <= x1; x += step) if (Math.abs(x) > step / 2) ctx.fillText(formatNumber(Number(x.toPrecision(6))), X(x) + 3, ay - 3);
    for (let y = Math.ceil(y0 / step) * step; y <= y1; y += step) if (Math.abs(y) > step / 2) ctx.fillText(formatNumber(Number(y.toPrecision(6))), ax + 3, Y(y) - 3);
    const engine = new CalculatorEngine({ angleMode: 'radians', formulas: calc.allFormulas, variables: calc.variables });
    fns.forEach((f, i) => {
      if (!f.trim()) return;
      let expr;
      try { expr = engine.compile(f, ['x']); } catch { return; }
      ctx.strokeStyle = GRAPH_COLORS[i % GRAPH_COLORS.length];
      ctx.lineWidth = 2.2; ctx.beginPath();
      let pen = false, prevY = null;
      for (let px = 0; px <= W; px += 1) {
        const x = view.cx + (px - W / 2) / s;
        let y;
        try { y = engine.evalCompiled(expr, { x }); } catch { pen = false; continue; }
        const py = Y(y);
        if (!Number.isFinite(py) || (prevY != null && Math.abs(py - prevY) > H * 2)) { pen = false; prevY = py; continue; }
        if (pen) ctx.lineTo(px, py); else ctx.moveTo(px, py);
        pen = true; prevY = py;
      }
      ctx.stroke();
    });
  }

  let drag = null;
  const pts = new Map();
  canvas.addEventListener('pointerdown', (e) => { canvas.setPointerCapture(e.pointerId); pts.set(e.pointerId, { x: e.clientX, y: e.clientY }); drag = { view: { ...view }, pts: new Map(pts) }; });
  canvas.addEventListener('pointermove', (e) => {
    const rect = canvas.getBoundingClientRect();
    const x = view.cx + (e.clientX - rect.left - rect.width / 2) / view.scale, y = view.cy - (e.clientY - rect.top - rect.height / 2) / view.scale;
    readout.textContent = `x = ${formatNumber(Number(x.toPrecision(5)))}, y = ${formatNumber(Number(y.toPrecision(5)))}`;
    if (!pts.has(e.pointerId) || !drag) return;
    pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const a = [...drag.pts.values()], b = [...pts.values()];
    if (a.length >= 2 && b.length >= 2) {
      const d0 = Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y), d1 = Math.hypot(b[0].x - b[1].x, b[0].y - b[1].y);
      view.scale = clamp(drag.view.scale * (d1 / Math.max(d0, 1)), 2, 5000);
    } else {
      const s0 = a.find((_, k) => [...drag.pts.keys()][k] === e.pointerId) || a[0];
      view.cx = drag.view.cx - (e.clientX - s0.x) / view.scale;
      view.cy = drag.view.cy + (e.clientY - s0.y) / view.scale;
    }
    draw();
  });
  const up = (e) => { pts.delete(e.pointerId); drag = pts.size ? { view: { ...view }, pts: new Map(pts) } : null; };
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', (e) => { e.preventDefault(); view.scale = clamp(view.scale * Math.exp(-e.deltaY * 0.002), 2, 5000); draw(); }, { passive: false });
  const ro = new ResizeObserver(draw);
  ro.observe(canvas);
  root.cleanup = () => ro.disconnect();
  renderList();
  return root;
}
