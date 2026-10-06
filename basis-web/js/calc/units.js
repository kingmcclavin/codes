// Unit library and conversion: value_SI = value × scale + offset.
// Dimensions are exponents of [m, kg, s, A, K, mol].

const D = (...e) => e.concat(Array(6 - e.length).fill(0));
const mulD = (a, b) => a.map((x, i) => x + b[i]);
const divD = (a, b) => a.map((x, i) => x - b[i]);
const powD = (a, n) => a.map((x) => x * n);
const eqD = (a, b) => a.every((x, i) => x === b[i]);

const L = D(1), M = D(0, 1), T = D(0, 0, 1), I = D(0, 0, 0, 1), Θ = D(0, 0, 0, 0, 1), N = D(0, 0, 0, 0, 0, 1), NONE = D();
const FORCE = divD(mulD(M, L), powD(T, 2)), ENERGY = mulD(FORCE, L), POWER = divD(ENERGY, T), PRESSURE = divD(FORCE, powD(L, 2));
const CHARGE = mulD(I, T), VOLTAGE = divD(POWER, I);

const u = (symbol, name, category, dim, scale, offset = 0) => ({ symbol, name, category, dim, scale, offset });

export const UNITS = [
  u('nm', 'nanometre', 'Length', L, 1e-9), u('µm', 'micrometre', 'Length', L, 1e-6), u('mm', 'millimetre', 'Length', L, 1e-3),
  u('cm', 'centimetre', 'Length', L, 1e-2), u('m', 'metre', 'Length', L, 1), u('km', 'kilometre', 'Length', L, 1e3),
  u('in', 'inch', 'Length', L, 0.0254), u('ft', 'foot', 'Length', L, 0.3048), u('yd', 'yard', 'Length', L, 0.9144), u('mi', 'mile', 'Length', L, 1609.344),
  u('mm²', 'square millimetre', 'Area', powD(L, 2), 1e-6), u('cm²', 'square centimetre', 'Area', powD(L, 2), 1e-4), u('m²', 'square metre', 'Area', powD(L, 2), 1),
  u('in²', 'square inch', 'Area', powD(L, 2), 0.00064516), u('ft²', 'square foot', 'Area', powD(L, 2), 0.09290304),
  u('mL', 'millilitre', 'Volume', powD(L, 3), 1e-6), u('L', 'litre', 'Volume', powD(L, 3), 1e-3), u('m³', 'cubic metre', 'Volume', powD(L, 3), 1),
  u('in³', 'cubic inch', 'Volume', powD(L, 3), 1.6387064e-5), u('ft³', 'cubic foot', 'Volume', powD(L, 3), 0.028316846592), u('gal', 'US gallon', 'Volume', powD(L, 3), 0.003785411784),
  u('mg', 'milligram', 'Mass', M, 1e-6), u('g', 'gram', 'Mass', M, 1e-3), u('kg', 'kilogram', 'Mass', M, 1), u('t', 'tonne', 'Mass', M, 1000),
  u('oz', 'ounce', 'Mass', M, 0.028349523125), u('lb', 'pound', 'Mass', M, 0.45359237),
  u('ms', 'millisecond', 'Time', T, 1e-3), u('s', 'second', 'Time', T, 1), u('min', 'minute', 'Time', T, 60), u('hr', 'hour', 'Time', T, 3600), u('day', 'day', 'Time', T, 86400),
  u('m/s', 'metre per second', 'Speed', divD(L, T), 1), u('km/h', 'kilometre per hour', 'Speed', divD(L, T), 1 / 3.6), u('mph', 'mile per hour', 'Speed', divD(L, T), 0.44704),
  u('ft/s', 'foot per second', 'Speed', divD(L, T), 0.3048), u('kn', 'knot', 'Speed', divD(L, T), 1852 / 3600),
  u('m/s²', 'metre per second squared', 'Acceleration', divD(L, powD(T, 2)), 1), u('ft/s²', 'foot per second squared', 'Acceleration', divD(L, powD(T, 2)), 0.3048),
  u('gₙ', 'standard gravity', 'Acceleration', divD(L, powD(T, 2)), 9.80665),
  u('N', 'newton', 'Force', FORCE, 1), u('kN', 'kilonewton', 'Force', FORCE, 1e3), u('lbf', 'pound-force', 'Force', FORCE, 4.4482216152605), u('kip', 'kip', 'Force', FORCE, 4448.2216152605),
  u('J', 'joule', 'Energy', ENERGY, 1), u('kJ', 'kilojoule', 'Energy', ENERGY, 1e3), u('MJ', 'megajoule', 'Energy', ENERGY, 1e6), u('cal', 'calorie', 'Energy', ENERGY, 4.184),
  u('kcal', 'kilocalorie', 'Energy', ENERGY, 4184), u('ft·lbf', 'foot-pound', 'Energy', ENERGY, 1.3558179483314), u('Wh', 'watt-hour', 'Energy', ENERGY, 3600),
  u('kWh', 'kilowatt-hour', 'Energy', ENERGY, 3.6e6), u('BTU', 'British thermal unit', 'Energy', ENERGY, 1055.05585262), u('eV', 'electronvolt', 'Energy', ENERGY, 1.602176634e-19),
  u('W', 'watt', 'Power', POWER, 1), u('kW', 'kilowatt', 'Power', POWER, 1e3), u('MW', 'megawatt', 'Power', POWER, 1e6), u('hp', 'horsepower', 'Power', POWER, 745.69987158227),
  u('Pa', 'pascal', 'Pressure', PRESSURE, 1), u('kPa', 'kilopascal', 'Pressure', PRESSURE, 1e3), u('MPa', 'megapascal', 'Pressure', PRESSURE, 1e6),
  u('GPa', 'gigapascal', 'Pressure', PRESSURE, 1e9), u('bar', 'bar', 'Pressure', PRESSURE, 1e5), u('psi', 'pound per square inch', 'Pressure', PRESSURE, 6894.757293168),
  u('ksi', 'kip per square inch', 'Pressure', PRESSURE, 6894757.293168), u('atm', 'atmosphere', 'Pressure', PRESSURE, 101325),
  u('K', 'kelvin', 'Temperature', Θ, 1), u('°C', 'degree Celsius', 'Temperature', Θ, 1, 273.15), u('°F', 'degree Fahrenheit', 'Temperature', Θ, 5 / 9, (459.67 * 5) / 9),
  u('N·m', 'newton-metre', 'Torque', ENERGY, 1), u('lbf·ft', 'pound-foot', 'Torque', ENERGY, 1.3558179483314), u('lbf·in', 'pound-inch', 'Torque', ENERGY, 0.1129848290276),
  u('kg/m³', 'kilogram per cubic metre', 'Density', divD(M, powD(L, 3)), 1), u('g/cm³', 'gram per cubic centimetre', 'Density', divD(M, powD(L, 3)), 1000),
  u('lb/ft³', 'pound per cubic foot', 'Density', divD(M, powD(L, 3)), 16.018463373960138),
  u('mA', 'milliampere', 'Current', I, 1e-3), u('A', 'ampere', 'Current', I, 1),
  u('mV', 'millivolt', 'Voltage', VOLTAGE, 1e-3), u('V', 'volt', 'Voltage', VOLTAGE, 1), u('kV', 'kilovolt', 'Voltage', VOLTAGE, 1e3),
  u('Ω', 'ohm', 'Resistance', divD(VOLTAGE, I), 1), u('kΩ', 'kiloohm', 'Resistance', divD(VOLTAGE, I), 1e3), u('MΩ', 'megaohm', 'Resistance', divD(VOLTAGE, I), 1e6),
  u('C', 'coulomb', 'Charge', CHARGE, 1), u('mAh', 'milliampere-hour', 'Charge', CHARGE, 3.6),
  u('F', 'farad', 'Capacitance', divD(CHARGE, VOLTAGE), 1), u('µF', 'microfarad', 'Capacitance', divD(CHARGE, VOLTAGE), 1e-6),
  u('nF', 'nanofarad', 'Capacitance', divD(CHARGE, VOLTAGE), 1e-9), u('pF', 'picofarad', 'Capacitance', divD(CHARGE, VOLTAGE), 1e-12),
  u('Hz', 'hertz', 'Frequency', divD(NONE, T), 1), u('kHz', 'kilohertz', 'Frequency', divD(NONE, T), 1e3), u('rpm', 'revolution per minute', 'Frequency', divD(NONE, T), 1 / 60),
  u('rad', 'radian', 'Angle', NONE, 1), u('°', 'degree', 'Angle', NONE, Math.PI / 180),
];

export const UNIT_CATEGORIES = [...new Set(UNITS.map((x) => x.category))];

const EXTRAS = {
  h: { dim: T, scale: 3600 }, mol: { dim: N, scale: 1 }, kmol: { dim: N, scale: 1000 }, ohm: { dim: divD(VOLTAGE, I), scale: 1 },
  um: { dim: L, scale: 1e-6 }, deg: { dim: NONE, scale: Math.PI / 180 }, degC: { dim: Θ, scale: 1, offset: 273.15 },
  degF: { dim: Θ, scale: 5 / 9, offset: (459.67 * 5) / 9 }, lbm: { dim: M, scale: 0.45359237 },
};
const BY_SYMBOL = Object.fromEntries(UNITS.map((x) => [x.symbol, x]));
const PREFIXES = { G: 1e9, M: 1e6, k: 1e3, c: 1e-2, m: 1e-3, µ: 1e-6, μ: 1e-6, u: 1e-6, n: 1e-9, p: 1e-12 };
const PREFIXABLE = new Set(['m', 'g', 's', 'N', 'J', 'W', 'Pa', 'A', 'V', 'Ω', 'F', 'Hz', 'C', 'L', 'eV', 'mol']);
const SUPS = { '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-' };

function atom(sym) {
  if (BY_SYMBOL[sym]) { const x = BY_SYMBOL[sym]; return { dim: x.dim, scale: x.scale, offset: x.offset }; }
  if (EXTRAS[sym]) return { offset: 0, ...EXTRAS[sym] };
  const p = sym[0], rest = sym.slice(1);
  if (PREFIXES[p] && PREFIXABLE.has(rest)) { const b = atom(rest); if (b && !b.offset) return { dim: b.dim, scale: b.scale * PREFIXES[p], offset: 0 }; }
  return null;
}

/** Parses `kg`, `m/s²`, `kg·m^2/s^2`, `J/(mol·K)`. Empty = dimensionless. */
export function parseUnit(text) {
  const t = text.trim();
  if (!t) return { dim: NONE, scale: 1, offset: 0 };
  const whole = atom(t);
  if (whole) return whole;
  const ch = Array.from(t);
  let i = 0;
  const factor = () => {
    if (i >= ch.length) return null;
    let base;
    if (ch[i] === '(') { i++; base = product(); if (!base || ch[i] !== ')') return null; i++; } else if (ch[i] === '1') { i++; base = { dim: NONE, scale: 1, offset: 0 }; } else {
      let s = '';
      while (i < ch.length && !'·*⋅ /()^'.includes(ch[i]) && !(ch[i] in SUPS)) s += ch[i++];
      base = atom(s);
      if (!base) return null;
    }
    let e = '';
    if (ch[i] === '^') { i++; while (i < ch.length && /[-\d]/.test(ch[i])) e += ch[i++]; } else while (i < ch.length && ch[i] in SUPS) e += SUPS[ch[i++]];
    if (e) { const n = parseInt(e, 10); if (Number.isNaN(n)) return null; return { dim: powD(base.dim, n), scale: Math.pow(base.scale, n), offset: 0 }; }
    return base;
  };
  const product = () => {
    let r = factor();
    if (!r) return null;
    while (i < ch.length && ch[i] !== ')') {
      const c = ch[i];
      if (c === '/') { i++; const f = factor(); if (!f) return null; r = { dim: divD(r.dim, f.dim), scale: r.scale / f.scale, offset: 0 }; } else if ('·*⋅ '.includes(c)) { i++; const f = factor(); if (!f) return null; r = { dim: mulD(r.dim, f.dim), scale: r.scale * f.scale, offset: 0 }; } else return null;
    }
    return r;
  };
  const spec = product();
  return spec && i === ch.length ? spec : null;
}

export function describeDim(dim) {
  if (dim.every((x) => x === 0)) return 'dimensionless';
  const sym = ['m', 'kg', 's', 'A', 'K', 'mol'];
  const SUP = { 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹' };
  const part = (pos) => [1, 0, 2, 3, 4, 5].map((i) => {
    const e = dim[i];
    if (pos ? e <= 0 : e >= 0) return null;
    const p = Math.abs(e);
    return p === 1 ? sym[i] : sym[i] + String(p).split('').map((c) => SUP[c]).join('');
  }).filter(Boolean).join('·');
  const num = part(true), den = part(false);
  return den ? `${num || '1'}/${den}` : num;
}

export function convertUnit(value, from, to) {
  const a = parseUnit(from), b = parseUnit(to);
  if (!a) throw new Error(`Unknown unit: ${from}`);
  if (!b) throw new Error(`Unknown unit: ${to}`);
  if (!eqD(a.dim, b.dim)) throw new Error(`Can't convert ${from} to ${to}: ${describeDim(a.dim)} vs ${describeDim(b.dim)}`);
  return (value * a.scale + a.offset - b.offset) / b.scale;
}

export const unitsIn = (category) => UNITS.filter((x) => x.category === category);
