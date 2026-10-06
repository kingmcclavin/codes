// App-wide calculator state: saved formulas, variables, history and the
// angle mode, kept in this browser.

import { CalculatorEngine, formatNumber, plainNumber } from './engine.js';
import { BUILT_IN_FORMULAS, FORMULA_CATEGORIES } from './formulas.js';
import { storage, uuid } from '../util.js';

const MAX_HISTORY = 500;

class CalcStore extends EventTarget {
  constructor() {
    super();
    this.userFormulas = storage.get('basis.formulas', []);
    this.variables = storage.get('basis.variables', []);
    this.history = storage.get('basis.history', []);
    this.angleMode = storage.get('basis.angleMode', 'degrees');
    this.ans = null;
    this.draft = '';
  }

  changed() { this.dispatchEvent(new Event('change')); }

  get allFormulas() { return [...this.userFormulas, ...BUILT_IN_FORMULAS]; }
  get engine() { return new CalculatorEngine({ angleMode: this.angleMode, formulas: this.allFormulas, variables: this.variables, ans: this.ans }); }
  formula(id) { return this.allFormulas.find((f) => f.id === id); }

  get categories() {
    const out = [...FORMULA_CATEGORIES];
    for (const f of this.userFormulas) if (!out.includes(f.category)) out.push(f.category);
    if (!out.includes('Custom')) out.push('Custom');
    return out;
  }

  setAngleMode(m) { this.angleMode = m; storage.set('basis.angleMode', m); this.changed(); }

  /** Evaluates a calculator line; `name = expr` stores a variable. */
  evaluate(text) {
    const t = text.trim();
    const r = this.engine.evaluateLine(t);
    this.ans = r.value;
    if (r.target) {
      const parts = CalculatorEngine.splitAssignment(t);
      if (parts) this.setVariable({ name: r.target, expression: parts.expression, unit: this.variables.find((v) => v.name === r.target)?.unit || '' });
    }
    this.record({ title: r.target ? `${r.target} =` : 'Calculation', expression: t, inputs: [], results: [{ name: r.target || '=', value: r.value }] });
    return r;
  }

  setVariable(v) {
    const i = this.variables.findIndex((x) => x.name === v.name);
    if (i >= 0) this.variables[i] = v; else this.variables.push(v);
    storage.set('basis.variables', this.variables);
    this.changed();
  }

  deleteVariable(name) {
    this.variables = this.variables.filter((v) => v.name !== name);
    storage.set('basis.variables', this.variables);
    this.changed();
  }

  valueOfVariable(name) {
    try { return { ok: true, value: this.engine.valueOfVariable(name) }; } catch (e) { return { ok: false, error: e }; }
  }

  saveFormula(f) {
    const copy = { ...f, isBuiltIn: false, exportsOutputs: true };
    const i = this.userFormulas.findIndex((x) => x.id === copy.id);
    if (i >= 0) this.userFormulas[i] = copy; else this.userFormulas.push(copy);
    storage.set('basis.formulas', this.userFormulas);
    this.changed();
  }

  deleteFormula(id) {
    this.userFormulas = this.userFormulas.filter((f) => f.id !== id);
    storage.set('basis.formulas', this.userFormulas);
    this.changed();
  }

  duplicateFormula(f) {
    const copy = { ...structuredClone(f), id: uuid(), name: f.name + (f.isBuiltIn ? '' : ' Copy'), isBuiltIn: false };
    if (f.isBuiltIn) copy.category = 'Custom';
    this.saveFormula(copy);
    return copy;
  }

  runFormula(f, inputs) {
    const engine = this.engine;
    const result = engine.evaluateFormula(f, inputs);
    if (!result.error && result.outputs.every((o) => o.value != null)) {
      const names = engine.inputs(f);
      const inputValues = names.filter((n) => inputs[n] != null).map((n) => ({ name: n, value: inputs[n], unit: f.variables?.find((v) => v.name === n)?.unit || '' }));
      const outs = result.outputs.map((o) => ({ name: o.name, value: o.value, unit: o.unit }));
      this.ans = outs[outs.length - 1]?.value ?? this.ans;
      this.record({ title: f.name, formulaId: f.id, expression: f.expression, inputs: inputValues, results: outs });
    }
    return result;
  }

  record(r) {
    const entry = { id: uuid(), date: Date.now(), formulaId: null, ...r };
    const last = this.history[0];
    if (last && last.title === entry.title && JSON.stringify(last.inputs) === JSON.stringify(entry.inputs) && JSON.stringify(last.results) === JSON.stringify(entry.results)) return;
    this.history.unshift(entry);
    if (this.history.length > MAX_HISTORY) this.history.length = MAX_HISTORY;
    storage.set('basis.history', this.history);
    this.changed();
  }

  deleteHistory(ids) {
    this.history = this.history.filter((h) => !ids.has(h.id));
    storage.set('basis.history', this.history);
    this.changed();
  }

  /** Text for a calculation card: each line followed by its result. */
  renderCard(source) {
    const engine = this.engine;
    const lines = source.split('\n').map((l) => l.trim()).filter(Boolean);
    const local = [];
    const out = [];
    for (const line of lines) {
      try {
        const e = new CalculatorEngine({ angleMode: this.angleMode, formulas: this.allFormulas, variables: [...this.variables.filter((v) => !local.some((l) => l.name === v.name)), ...local], ans: this.ans });
        const r = e.evaluateLine(line);
        if (r.target) {
          const parts = CalculatorEngine.splitAssignment(line);
          if (parts) local.push({ name: r.target, expression: plainNumber(r.value) });
          out.push(`${line.replace(/\s*=\s*/, ' = ')} = ${formatNumber(r.value)}`.replace(/ = ([^=]+) = \1$/, ' = $1'));
        } else out.push(`${line} = ${formatNumber(r.value)}`);
      } catch (err) {
        out.push(`${line}  ⚠ ${err.message}`);
      }
    }
    void engine;
    return out.join('\n');
  }

  exportData() { return { formulas: this.userFormulas, variables: this.variables, history: this.history }; }

  importData(data) {
    for (const f of data.formulas || []) if (!f.isBuiltIn) {
      const i = this.userFormulas.findIndex((x) => x.id === f.id);
      if (i >= 0) this.userFormulas[i] = f; else this.userFormulas.push(f);
    }
    for (const v of data.variables || []) {
      const i = this.variables.findIndex((x) => x.name === v.name);
      if (i >= 0) this.variables[i] = v; else this.variables.push(v);
    }
    const known = new Set(this.history.map((h) => h.id));
    this.history = [...this.history, ...(data.history || []).filter((h) => !known.has(h.id))].sort((a, b) => b.date - a.date).slice(0, MAX_HISTORY);
    storage.set('basis.formulas', this.userFormulas);
    storage.set('basis.variables', this.variables);
    storage.set('basis.history', this.history);
    this.changed();
  }
}

export const calc = new CalcStore();
