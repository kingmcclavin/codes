// Calculation engine: lexer, recursive-descent parser, evaluator, formula
// dependencies and cycle detection. No UI or persistence.

export class CalcError extends Error {
  constructor(kind, message, extra) { super(message); this.kind = kind; this.extra = extra; }
}
const invalid = (m) => new CalcError('invalid', `Invalid expression: ${m}`);
const missing = (n) => new CalcError('missing', `Missing variable: ${n}`, n);
const divZero = () => new CalcError('divzero', 'Division by zero');
const domain = (m) => new CalcError('domain', m);
const notFinite = () => new CalcError('notfinite', 'Result is too large or undefined');
const circular = (chain) => new CalcError('circular', `Circular formula dependency detected: ${chain.join(' → ')}`);

// ---------- Lexer ----------

const SUPERSCRIPTS = { '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-' };
const FRACTIONS = { '½': 0.5, '⅓': 1 / 3, '⅔': 2 / 3, '¼': 0.25, '¾': 0.75, '⅛': 0.125 };
const SUBSCRIPTS = new Set(['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉', 'ₓ', 'ᵢ', 'ₙ']);
const isDigit = (c) => c >= '0' && c <= '9';
const isLetter = (c) => /\p{L}/u.test(c);

export const isIdentStart = (c) => (isLetter(c) || c === '_') && !(c in SUPERSCRIPTS) && !SUBSCRIPTS.has(c) && !(c in FRACTIONS);
const isIdentBody = (c) => isIdentStart(c) || isDigit(c) || SUBSCRIPTS.has(c) || c === "'";

export function tokenize(text) {
  const ch = Array.from(text);
  const out = [];
  let i = 0;
  while (i < ch.length) {
    const c = ch[i];
    if (/\s/.test(c)) { i++; continue; }
    if (isDigit(c) || (c === '.' && i + 1 < ch.length && isDigit(ch[i + 1]))) {
      let s = '';
      while (i < ch.length && (isDigit(ch[i]) || ch[i] === '.')) s += ch[i++];
      if (i < ch.length && (ch[i] === 'e' || ch[i] === 'E')) {
        let j = i + 1, exp = 'e';
        if (j < ch.length && (ch[j] === '+' || ch[j] === '-' || ch[j] === '−')) { exp += ch[j] === '+' ? '+' : '-'; j++; }
        if (j < ch.length && isDigit(ch[j])) {
          while (j < ch.length && isDigit(ch[j])) exp += ch[j++];
          s += exp; i = j;
        }
      }
      const v = Number(s);
      if ((s.match(/\./g) || []).length > 1 || !Number.isFinite(v)) throw invalid(`bad number "${s}"`);
      out.push({ t: 'num', v });
      continue;
    }
    if (c in FRACTIONS) { out.push({ t: 'num', v: FRACTIONS[c] }); i++; continue; }
    if (c in SUPERSCRIPTS) {
      let s = '';
      while (i < ch.length && ch[i] in SUPERSCRIPTS) s += SUPERSCRIPTS[ch[i++]];
      const v = Number(s);
      if (!Number.isFinite(v) || s === '-') throw invalid('bad exponent');
      out.push({ t: 'op', v: '^' }, { t: 'num', v });
      continue;
    }
    if (isIdentStart(c)) {
      let s = '';
      while (i < ch.length && isIdentBody(ch[i])) s += ch[i++];
      out.push({ t: 'id', v: s });
      continue;
    }
    switch (c) {
      case '+': out.push({ t: 'op', v: '+' }); break;
      case '-': case '−': case '–': out.push({ t: 'op', v: '-' }); break;
      case '*':
        if (ch[i + 1] === '*') { out.push({ t: 'op', v: '^' }); i++; } else out.push({ t: 'op', v: '*' });
        break;
      case '×': case '·': case '⋅': case '∙': out.push({ t: 'op', v: '*' }); break;
      case '/': case '÷': out.push({ t: 'op', v: '/' }); break;
      case '^': out.push({ t: 'op', v: '^' }); break;
      case '(': case '[': case '{': out.push({ t: '(' }); break;
      case ')': case ']': case '}': out.push({ t: ')' }); break;
      case ',': case ';': out.push({ t: ',' }); break;
      case '|': out.push({ t: '|' }); break;
      case '=': out.push({ t: '=' }); break;
      case '√': out.push({ t: 'sqrt' }); break;
      case '∛': out.push({ t: 'cbrt' }); break;
      case '!': case '%': case '°': out.push({ t: 'post', v: c }); break;
      default: throw invalid(`unexpected character "${c}"`);
    }
    i++;
  }
  return out;
}

// ---------- AST helpers ----------
// Nodes: {n:'num',v} {n:'var',name} {n:'neg',x} {n:'bin',op,l,r} {n:'call',name,args} {n:'post',op,x}

export function exprVariables(e) {
  const seen = [];
  const walk = (x) => {
    switch (x.n) {
      case 'var': if (!seen.includes(x.name)) seen.push(x.name); break;
      case 'neg': case 'post': walk(x.x); break;
      case 'bin': walk(x.l); walk(x.r); break;
      case 'call': x.args.forEach(walk); break;
    }
  };
  walk(e);
  return seen;
}

// ---------- Functions & constants ----------

const ALIASES = { arcsin: 'asin', arccos: 'acos', arctan: 'atan', log10: 'log', sqr: 'sqrt', fabs: 'abs' };
const FUNCTION_NAMES = new Set(['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'sinh', 'cosh', 'tanh', 'sec', 'csc', 'cot',
  'sqrt', 'cbrt', 'root', 'abs', 'log', 'ln', 'log2', 'logb', 'exp', 'floor', 'ceil', 'round', 'sign', 'min', 'max', 'fact', 'nCr', 'nPr',
  'deg', 'rad', 'hypot', 'avg', 'sum', 'mod']);
export const canonicalName = (n) => ALIASES[n] || n;
export const isFunction = (n) => FUNCTION_NAMES.has(canonicalName(n));

export const FUNCTION_CATALOG = [
  ['sin', 'Sine'], ['cos', 'Cosine'], ['tan', 'Tangent'], ['asin', 'Inverse sine'], ['acos', 'Inverse cosine'], ['atan', 'Inverse tangent'],
  ['atan2', 'atan2(y, x) – angle of a vector'], ['sinh', 'Hyperbolic sine'], ['cosh', 'Hyperbolic cosine'], ['tanh', 'Hyperbolic tangent'],
  ['sqrt', 'Square root'], ['cbrt', 'Cube root'], ['root', 'root(x, n) – n-th root'], ['abs', 'Absolute value'], ['log', 'Base-10 logarithm'],
  ['ln', 'Natural logarithm'], ['log2', 'Base-2 logarithm'], ['logb', 'logb(x, b) – logarithm base b'], ['exp', 'e to the power x'],
  ['floor', 'Round down'], ['ceil', 'Round up'], ['round', 'round(x) or round(x, digits)'], ['min', 'Smallest argument'], ['max', 'Largest argument'],
  ['avg', 'Average of arguments'], ['sum', 'Sum of arguments'], ['hypot', '√(a² + b² + …)'], ['mod', 'mod(a, b) – remainder'],
  ['fact', 'Factorial (also n!)'], ['nCr', 'Combinations'], ['nPr', 'Permutations'], ['deg', 'Radians → degrees'], ['rad', 'Degrees → radians'],
].map(([name, help]) => ({ name, insert: name + '(', help }));

export const CONSTANTS = [
  { id: 'π', symbol: 'π', name: 'Pi', value: Math.PI, unit: '' },
  { id: 'e', symbol: 'e', name: "Euler's number", value: Math.E, unit: '' },
  { id: 'g0', symbol: 'g₀', name: 'Standard gravity', value: 9.80665, unit: 'm/s²' },
  { id: 'c0', symbol: 'c', name: 'Speed of light', value: 299792458, unit: 'm/s' },
  { id: 'G_N', symbol: 'G', name: 'Gravitational constant', value: 6.6743e-11, unit: 'N·m²/kg²' },
  { id: 'h_P', symbol: 'h', name: 'Planck constant', value: 6.62607015e-34, unit: 'J·s' },
  { id: 'ħ', symbol: 'ħ', name: 'Reduced Planck constant', value: 1.054571817e-34, unit: 'J·s' },
  { id: 'k_B', symbol: 'k', name: 'Boltzmann constant', value: 1.380649e-23, unit: 'J/K' },
  { id: 'N_A', symbol: 'Nₐ', name: 'Avogadro constant', value: 6.02214076e23, unit: '1/mol' },
  { id: 'R_u', symbol: 'R', name: 'Universal gas constant', value: 8.314462618, unit: 'J/(mol·K)' },
  { id: 'q_e', symbol: 'e', name: 'Elementary charge', value: 1.602176634e-19, unit: 'C' },
  { id: 'm_e', symbol: 'mₑ', name: 'Electron mass', value: 9.1093837015e-31, unit: 'kg' },
  { id: 'm_p', symbol: 'mₚ', name: 'Proton mass', value: 1.67262192369e-27, unit: 'kg' },
  { id: 'ε0', symbol: 'ε₀', name: 'Vacuum permittivity', value: 8.8541878128e-12, unit: 'F/m' },
  { id: 'μ0', symbol: 'μ₀', name: 'Vacuum permeability', value: 1.25663706212e-6, unit: 'N/A²' },
  { id: 'σ_SB', symbol: 'σ', name: 'Stefan–Boltzmann constant', value: 5.670374419e-8, unit: 'W/(m²·K⁴)' },
  { id: 'atm0', symbol: 'atm', name: 'Standard atmosphere', value: 101325, unit: 'Pa' },
];
const CONST_BY_ID = Object.fromEntries([...CONSTANTS.map((c) => [c.id, c.value]), ['pi', Math.PI], ['eps0', 8.8541878128e-12], ['mu0', 1.25663706212e-6]]);
export const constantValue = (n) => CONST_BY_ID[n];
export const isConstant = (n) => n in CONST_BY_ID;

// ---------- Parser ----------

const GREEK = new Set(['mu', 'nu', 'xi', 'pi', 'rho', 'tau', 'phi', 'chi', 'psi', 'eta', 'ans']);
const RESERVED = new Set(['max', 'min', 'deg', 'rad']);

function describe(t) {
  switch (t.t) {
    case 'num': return `number ${t.v}`;
    case 'id': return `"${t.v}"`;
    case 'op': case 'post': return `"${t.v}"`;
    case 'sqrt': return '"√"';
    case 'cbrt': return '"∛"';
    default: return `"${t.t}"`;
  }
}

/** Short all-lowercase names (`ac`, `mgh`) are products of single letters unless known. */
function splitIdentifier(name, known) {
  const letters = Array.from(name);
  const splittable = letters.length >= 2 && letters.length <= 3 && letters.every((c) => c >= 'a' && c <= 'z')
    && !known.has(name) && !isConstant(name) && !GREEK.has(name) && !RESERVED.has(name);
  if (!splittable) return { n: 'var', name };
  let e = { n: 'var', name: letters[0] };
  for (const c of letters.slice(1)) e = { n: 'bin', op: '*', l: e, r: { n: 'var', name: c } };
  return e;
}

class Cursor {
  constructor(tokens, known) { this.tokens = tokens; this.known = known; this.i = 0; }
  get peek() { return this.tokens[this.i]; }
  next() { return this.tokens[this.i++]; }
  is(t, v) { const p = this.peek; return p && p.t === t && (v === undefined || p.v === v); }

  parseAll() {
    const e = this.additive();
    const t = this.peek;
    if (t) {
      if (t.t === '=') throw invalid('only one "=" is allowed, as in "name = expression"');
      if (t.t === ')') throw invalid('unmatched ")"');
      throw invalid(`unexpected ${describe(t)}`);
    }
    return e;
  }
  additive() {
    let l = this.multiplicative();
    while (this.is('op', '+') || this.is('op', '-')) { const op = this.next().v; l = { n: 'bin', op, l, r: this.multiplicative() }; }
    return l;
  }
  multiplicative() {
    let l = this.unary();
    for (;;) {
      if (this.is('op', '*') || this.is('op', '/')) { const op = this.next().v; l = { n: 'bin', op, l, r: this.unary() }; } else if (this.startsOperand(this.peek)) l = { n: 'bin', op: '*', l, r: this.power() };
      else return l;
    }
  }
  startsOperand(t) { return !!t && ['num', 'id', '(', 'sqrt', 'cbrt'].includes(t.t); }
  unary() {
    if (this.is('op', '-') || this.is('op', '+')) { const op = this.next().v; const x = this.unary(); return op === '-' ? { n: 'neg', x } : x; }
    return this.power();
  }
  power() {
    const base = this.postfix();
    if (this.is('op', '^')) { this.next(); return { n: 'bin', op: '^', l: base, r: this.unary() }; }
    return base;
  }
  postfix() {
    let e = this.primary();
    while (this.is('post')) e = { n: 'post', op: this.next().v, x: e };
    return e;
  }
  primary() {
    const t = this.next();
    if (!t) throw invalid('expression ends too early');
    switch (t.t) {
      case 'num': return { n: 'num', v: t.v };
      case '(': {
        const e = this.additive();
        if (this.next()?.t !== ')') throw invalid('missing ")"');
        return e;
      }
      case '|': {
        const e = this.additive();
        if (this.next()?.t !== '|') throw invalid('missing closing "|"');
        return { n: 'call', name: 'abs', args: [e] };
      }
      case 'sqrt': return { n: 'call', name: 'sqrt', args: [this.power()] };
      case 'cbrt': return { n: 'call', name: 'cbrt', args: [this.power()] };
      case 'id': {
        const name = t.v;
        if (this.is('(') && isFunction(name)) {
          this.next();
          const args = [];
          if (!this.is(')')) {
            args.push(this.additive());
            while (this.is(',')) { this.next(); args.push(this.additive()); }
          }
          if (this.next()?.t !== ')') throw invalid(`missing ")" after ${name}(`);
          return { n: 'call', name: canonicalName(name), args };
        }
        if (isFunction(name) && !this.known.has(name)) {
          if (!this.startsOperand(this.peek)) throw invalid(`${name} needs an argument, e.g. ${name}(x)`);
          return { n: 'call', name: canonicalName(name), args: [this.power()] };
        }
        return splitIdentifier(name, this.known);
      }
      case ')': throw invalid('unexpected ")"');
      case '=': throw invalid('unexpected "="');
      case ',': throw invalid('unexpected ","');
      case 'op': throw invalid(`missing number before "${t.v}"`);
      case 'post': throw invalid(`unexpected "${t.v}"`);
    }
    throw invalid('unexpected token');
  }
}

export function parseStatement(text, known = new Set()) {
  const tokens = tokenize(text);
  if (!tokens.length) throw invalid('empty expression');
  if (tokens.length >= 2 && tokens[0].t === 'id' && tokens[1].t === '=') {
    if (tokens.length <= 2) throw invalid('nothing after "="');
    return { target: tokens[0].v, expr: new Cursor(tokens.slice(2), known).parseAll() };
  }
  return { target: null, expr: new Cursor(tokens, known).parseAll() };
}

export function parseExpression(text, known) {
  const s = parseStatement(text, known);
  if (s.target) throw invalid('unexpected "="');
  return s.expr;
}

// ---------- Evaluator ----------

function factorial(v) {
  if (v < 0 || v !== Math.round(v)) throw domain('Factorial requires a non-negative whole number');
  if (v > 170) throw notFinite();
  let r = 1;
  for (let i = 2; i <= v; i++) r *= i;
  return r;
}

const fin = (v) => { if (!Number.isFinite(v)) throw notFinite(); return v; };

export function evaluate(expr, angleMode, resolve) {
  const toRad = (x) => (angleMode === 'degrees' ? (x * Math.PI) / 180 : x);
  const fromRad = (x) => (angleMode === 'degrees' ? (x * 180) / Math.PI : x);
  const quarter = (x) => {
    const q = angleMode === 'degrees' ? x / 90 : x / (Math.PI / 2);
    const r = Math.round(q);
    if (Math.abs(q - r) >= 1e-12) return null;
    return ((r % 4) + 4) % 4;
  };
  const clean = (v) => (Math.abs(v) < 1e-15 ? 0 : v);

  const call = (name, a) => {
    const need = (n) => { if (a.length !== n) throw new CalcError('args', `${name} expects ${n === 1 ? '1 argument' : `${n} arguments`}`); };
    const atLeast = (n) => { if (a.length < n) throw new CalcError('args', `${name} expects at least ${n} argument${n === 1 ? '' : 's'}`); };
    switch (name) {
      case 'sin': { need(1); const q = quarter(a[0]); return q != null ? [0, 1, 0, -1][q] : clean(Math.sin(toRad(a[0]))); }
      case 'cos': { need(1); const q = quarter(a[0]); return q != null ? [1, 0, -1, 0][q] : clean(Math.cos(toRad(a[0]))); }
      case 'tan': {
        need(1); const q = quarter(a[0]);
        if (q != null) { if (q % 2 === 1) throw domain(`tan is undefined at ${angleMode === 'degrees' ? '90°' : 'π/2'} + k·${angleMode === 'degrees' ? '180°' : 'π'}`); return 0; }
        return clean(Math.tan(toRad(a[0])));
      }
      case 'sec': { need(1); const c = call('cos', a); if (!c) throw divZero(); return 1 / c; }
      case 'csc': { need(1); const s = call('sin', a); if (!s) throw divZero(); return 1 / s; }
      case 'cot': { need(1); const t = call('tan', a); if (!t) throw divZero(); return 1 / t; }
      case 'asin': need(1); if (a[0] < -1 || a[0] > 1) throw domain('asin requires a value between -1 and 1'); return fromRad(Math.asin(a[0]));
      case 'acos': need(1); if (a[0] < -1 || a[0] > 1) throw domain('acos requires a value between -1 and 1'); return fromRad(Math.acos(a[0]));
      case 'atan': need(1); return fromRad(Math.atan(a[0]));
      case 'atan2': need(2); return fromRad(Math.atan2(a[0], a[1]));
      case 'sinh': need(1); return fin(Math.sinh(a[0]));
      case 'cosh': need(1); return fin(Math.cosh(a[0]));
      case 'tanh': need(1); return Math.tanh(a[0]);
      case 'sqrt': need(1); if (a[0] < 0) throw domain('Square root requires a non-negative value'); return Math.sqrt(a[0]);
      case 'cbrt': need(1); return Math.cbrt(a[0]);
      case 'root': need(2); if (!a[1]) throw domain('root(x, n) requires n ≠ 0'); return pow(a[0], 1 / a[1]);
      case 'abs': need(1); return Math.abs(a[0]);
      case 'log':
        if (a.length === 2) return call('logb', a);
        need(1); if (a[0] <= 0) throw domain('log requires a positive value'); return Math.log10(a[0]);
      case 'ln': need(1); if (a[0] <= 0) throw domain('ln requires a positive value'); return Math.log(a[0]);
      case 'log2': need(1); if (a[0] <= 0) throw domain('log2 requires a positive value'); return Math.log2(a[0]);
      case 'logb': need(2); if (a[0] <= 0 || a[1] <= 0 || a[1] === 1) throw domain('logb(x, b) requires x > 0 and b > 0, b ≠ 1'); return Math.log(a[0]) / Math.log(a[1]);
      case 'exp': need(1); return fin(Math.exp(a[0]));
      case 'floor': need(1); return Math.floor(a[0]);
      case 'ceil': need(1); return Math.ceil(a[0]);
      case 'round':
        if (a.length === 2) { const f = Math.pow(10, Math.round(a[1])); return Math.round(a[0] * f) / f; }
        need(1); return Math.round(a[0]);
      case 'sign': need(1); return Math.sign(a[0]);
      case 'min': atLeast(1); return Math.min(...a);
      case 'max': atLeast(1); return Math.max(...a);
      case 'sum': atLeast(1); return a.reduce((s, x) => s + x, 0);
      case 'avg': atLeast(1); return a.reduce((s, x) => s + x, 0) / a.length;
      case 'hypot': atLeast(1); return Math.sqrt(a.reduce((s, x) => s + x * x, 0));
      case 'mod': { need(2); if (!a[1]) throw divZero(); const r = a[0] % a[1]; return r < 0 ? r + Math.abs(a[1]) : r; }
      case 'fact': need(1); return factorial(a[0]);
      case 'nCr': case 'nPr': {
        need(2);
        const [n, r] = a;
        if (n < 0 || r < 0 || r > n || n !== Math.round(n) || r !== Math.round(r)) throw domain(`${name} requires whole numbers with 0 ≤ r ≤ n`);
        let res = 1;
        for (let i = 0; i < r; i++) res *= n - i;
        if (name === 'nCr') res /= factorial(r);
        return fin(Math.round(res));
      }
      case 'deg': need(1); return (a[0] * 180) / Math.PI;
      case 'rad': need(1); return (a[0] * Math.PI) / 180;
    }
    throw new CalcError('unknownfn', `Unknown function: ${name}`);
  };

  const pow = (a, b) => {
    if (a < 0 && b !== Math.round(b)) {
      const inv = 1 / b;
      if (Math.abs(inv - Math.round(inv)) < 1e-9 && Math.round(inv) % 2 !== 0) return -Math.pow(-a, b);
      throw domain("A negative number can't be raised to a fractional power");
    }
    if (a === 0 && b < 0) throw divZero();
    return fin(Math.pow(a, b));
  };

  const ev = (e) => {
    switch (e.n) {
      case 'num': return e.v;
      case 'var': {
        const v = resolve(e.name);
        if (v != null) return v;
        if (isConstant(e.name)) return constantValue(e.name);
        throw missing(e.name);
      }
      case 'neg': return -ev(e.x);
      case 'bin': {
        const a = ev(e.l), b = ev(e.r);
        switch (e.op) {
          case '+': return fin(a + b);
          case '-': return fin(a - b);
          case '*': return fin(a * b);
          case '/': if (b === 0) throw divZero(); return fin(a / b);
          case '^': return pow(a, b);
        }
        break;
      }
      case 'post': {
        const v = ev(e.x);
        if (e.op === '!') return factorial(v);
        if (e.op === '%') return v / 100;
        if (e.op === '°') return angleMode === 'radians' ? (v * Math.PI) / 180 : v;
        break;
      }
      case 'call': return call(e.name, e.args.map(ev));
    }
    throw invalid('unknown operator');
  };
  return fin(ev(expr));
}

// ---------- Number formatting ----------

const SUP = { 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹', '-': '⁻' };
export const superscript = (n) => String(n).split('').map((c) => SUP[c] ?? c).join('');
const trim = (s) => (s.includes('.') && !s.includes('e') ? s.replace(/0+$/, '').replace(/\.$/, '') : s);

export function formatNumber(v, digits = 10, pretty = true) {
  if (!Number.isFinite(v)) return Number.isNaN(v) ? 'undefined' : v > 0 ? '∞' : '−∞';
  if (v === 0) return '0';
  const a = Math.abs(v);
  if (a >= 1e10 || a < 1e-4) {
    let exp = Math.floor(Math.log10(a));
    let m = v / Math.pow(10, exp);
    const r = Math.round(m * 1e6) / 1e6;
    if (Math.abs(r) >= 10) { m = r / 10; exp += 1; } else m = r;
    const ms = trim(m.toFixed(6));
    return pretty ? `${ms} × 10${superscript(exp)}` : `${ms}e${exp}`;
  }
  return trim(v.toPrecision(digits));
}
export const plainNumber = (v) => formatNumber(v, 12, false);

/** Calculator-style display of typed text: × ÷ − √ π. */
export function prettyMath(s) {
  return String(s)
    .replace(/\*\*/g, '^')
    .replace(/\*/g, '×')
    .replace(/\//g, '÷')
    .replace(/(^|[^e\d])-/g, '$1−')
    .replace(/\bsqrt\(/g, '√(')
    .replace(/\bpi\b/g, 'π');
}

// ---------- Engine ----------

export function formulaLines(f) {
  return f.expression.split(/\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
}

export function outputNames(f) {
  return formulaLines(f).map((line) => {
    try { const t = tokenize(line); return t.length > 2 && t[0].t === 'id' && t[1].t === '=' ? t[0].v : null; } catch { return null; }
  }).filter(Boolean);
}

export const formulaUnit = (f, name) => f.variables?.find((v) => v.name === name)?.unit || '';

export class CalculatorEngine {
  constructor({ angleMode = 'degrees', formulas = [], variables = [], ans = null } = {}) {
    this.angleMode = angleMode;
    this.formulas = formulas;
    this.variables = variables;
    this.ans = ans;
    this.known = new Set(variables.map((v) => v.name));
    for (const f of formulas) { outputNames(f).forEach((n) => this.known.add(n)); (f.variables || []).forEach((v) => this.known.add(v.name)); }
  }

  knownFor(formula) {
    const k = new Set(this.known);
    if (formula) { (formula.variables || []).forEach((v) => k.add(v.name)); outputNames(formula).forEach((n) => k.add(n)); }
    return k;
  }

  formulaProducing(name, excluding) {
    const c = this.formulas.filter((f) => f.id !== excluding && f.exportsOutputs !== false && outputNames(f).includes(name));
    return c.find((f) => !f.isBuiltIn) || c[0] || null;
  }

  parse(formula) {
    const known = this.knownFor(formula);
    const lines = formulaLines(formula);
    const stmts = lines.map((line, i) => {
      try { return parseStatement(line, known); } catch (e) {
        if (lines.length > 1 && e.kind === 'invalid') throw new CalcError('invalid', `Invalid expression: line ${i + 1}: ${e.message.replace('Invalid expression: ', '')}`);
        throw e;
      }
    });
    if (!stmts.length) throw invalid('the formula is empty');
    return stmts;
  }

  inputs(formula) {
    const result = [];
    this.collectInputs(formula, new Set(), result);
    const declared = (formula.variables || []).map((v) => v.name);
    return result.map((n, i) => [n, declared.includes(n) ? declared.indexOf(n) : declared.length + i]).sort((a, b) => a[1] - b[1]).map((x) => x[0]);
  }

  collectInputs(formula, visiting, result) {
    let stmts;
    try { stmts = this.parse(formula); } catch { return; }
    const locals = new Set();
    for (const s of stmts) {
      for (const name of exprVariables(s.expr)) {
        if (locals.has(name) || result.includes(name)) continue;
        if (isConstant(name) || name === 'ans') continue;
        const dep = this.formulaProducing(name, formula.id);
        if (dep && !visiting.has(dep.id) && !(formula.variables || []).some((v) => v.name === name)) {
          this.collectInputs(dep, new Set([...visiting, formula.id]), result);
        } else result.push(name);
      }
      if (s.target) locals.add(s.target);
    }
  }

  dependencies(formula) {
    let stmts;
    try { stmts = this.parse(formula); } catch { return []; }
    const locals = new Set(), deps = [];
    for (const s of stmts) {
      for (const name of exprVariables(s.expr)) {
        if (locals.has(name)) continue;
        const dep = this.formulaProducing(name, formula.id);
        if (dep && !deps.some((d) => d.id === dep.id)) deps.push(dep);
      }
      if (s.target) locals.add(s.target);
    }
    return deps;
  }

  validate(formula) {
    try { this.parse(formula); } catch (e) { return e; }
    const path = [];
    const visit = (f) => {
      const i = path.findIndex((p) => p.id === f.id);
      if (i >= 0) return circular([...path.slice(i).map((p) => p.name), f.name]);
      path.push(f);
      for (const d of this.dependencies(f)) { const e = visit(d); if (e) return e; }
      path.pop();
      return null;
    };
    return visit(formula);
  }

  evaluateFormula(formula, inputs) {
    const v = this.validate(formula);
    if (v && v.kind === 'circular') return { outputs: [], error: v };
    let stmts;
    try { stmts = this.parse(formula); } catch (e) { return { outputs: [], error: e }; }
    const scope = new Scope(this, { ...inputs });
    scope.formulaStack = [formula.id];
    scope.declared = new Set((formula.variables || []).map((x) => x.name));
    scope.applyDefaults(formula);
    const outputs = stmts.map((s, i) => {
      const name = s.target || (stmts.length === 1 ? 'Result' : `Line ${i + 1}`);
      try {
        const val = scope.eval(s.expr);
        if (s.target) scope.values[s.target] = val;
        return { name, value: val, error: null, unit: formulaUnit(formula, name) };
      } catch (e) {
        return { name, value: null, error: e, unit: formulaUnit(formula, name) };
      }
    });
    return { outputs, error: null };
  }

  evaluateLine(text) {
    const st = parseStatement(text, this.known);
    const scope = new Scope(this, {});
    if (st.target) scope.variableStack = [st.target];
    return { target: st.target, value: scope.eval(st.expr) };
  }

  compile(text, names = []) { return parseExpression(text, new Set([...this.known, ...names])); }
  evalCompiled(expr, values) { return new Scope(this, { ...values }).eval(expr); }
  evaluateExpression(text, values = {}) { return this.evalCompiled(this.compile(text, Object.keys(values)), values); }
  valueOfVariable(name) { return new Scope(this, {}).eval({ n: 'var', name }); }

  static splitAssignment(text) {
    const eq = text.indexOf('=');
    if (eq < 0) return null;
    const name = text.slice(0, eq).trim(), expr = text.slice(eq + 1).trim();
    if (!name || !expr) return null;
    try { const t = tokenize(name); if (t.length !== 1 || t[0].t !== 'id') return null; } catch { return null; }
    return { name, expression: expr };
  }
}

class Scope {
  constructor(engine, values) {
    this.engine = engine; this.values = values;
    this.formulaStack = []; this.variableStack = []; this.declared = new Set();
  }
  eval(e) { return evaluate(e, this.engine.angleMode, (n) => this.lookup(n)); }
  applyDefaults(formula) {
    for (const v of formula.variables || []) {
      if (!v.defaultValue || this.values[v.name] != null || this.engine.variables.some((x) => x.name === v.name)) continue;
      try { this.values[v.name] = this.eval(parseExpression(v.defaultValue)); } catch { /* ignore bad default */ }
    }
  }
  lookup(name) {
    if (this.values[name] != null) return this.values[name];
    if (name === 'ans') return this.engine.ans;
    const variable = this.engine.variables.find((v) => v.name === name);
    if (variable) {
      if (this.variableStack.includes(name)) throw circular([...this.variableStack, name]);
      this.variableStack.push(name);
      try {
        const v = this.eval(parseExpression(variable.expression, this.engine.known));
        this.values[name] = v;
        return v;
      } finally { this.variableStack.pop(); }
    }
    if (isConstant(name)) return constantValue(name);
    if (!this.declared.has(name)) {
      const f = this.engine.formulaProducing(name, null);
      if (f) {
        if (this.formulaStack.includes(f.id)) {
          throw circular([...this.formulaStack.map((id) => this.engine.formulas.find((x) => x.id === id)?.name).filter(Boolean), f.name]);
        }
        this.formulaStack.push(f.id);
        try {
          this.applyDefaults(f);
          for (const s of this.engine.parse(f)) {
            const v = this.eval(s.expr);
            if (s.target) { this.values[s.target] = v; if (s.target === name) return v; }
          }
        } finally { this.formulaStack.pop(); }
      }
    }
    return null;
  }
}
