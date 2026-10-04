// Engineering unit catalogue + conversion. Conversion is delegated to the
// math engine; this module defines *which* units Basis exposes and how to label them.

import { formatValue, math } from './calculations/engine'

export interface UnitDef {
  id: string // mathjs unit string
  label: string
  symbol: string
}

export interface UnitCategory {
  id: string
  name: string
  units: UnitDef[]
}

const u = (id: string, label: string, symbol = id): UnitDef => ({ id, label, symbol })

export const UNIT_CATEGORIES: UnitCategory[] = [
  { id: 'length', name: 'Length', units: [u('m', 'Metre'), u('cm', 'Centimetre'), u('mm', 'Millimetre'), u('km', 'Kilometre'), u('in', 'Inch'), u('ft', 'Foot'), u('yd', 'Yard'), u('mi', 'Mile')] },
  { id: 'mass', name: 'Mass', units: [u('kg', 'Kilogram'), u('g', 'Gram'), u('lb', 'Pound'), u('oz', 'Ounce'), u('tonne', 'Tonne', 't')] },
  { id: 'time', name: 'Time', units: [u('s', 'Second'), u('ms', 'Millisecond'), u('min', 'Minute'), u('hr', 'Hour', 'h'), u('day', 'Day')] },
  { id: 'force', name: 'Force', units: [u('N', 'Newton'), u('kN', 'Kilonewton'), u('lbf', 'Pound-force'), u('kip', 'Kip')] },
  { id: 'energy', name: 'Energy', units: [u('J', 'Joule'), u('kJ', 'Kilojoule'), u('cal', 'Calorie'), u('kcal', 'Kilocalorie'), u('Wh', 'Watt-hour'), u('kWh', 'Kilowatt-hour'), u('BTU', 'BTU'), u('eV', 'Electronvolt')] },
  { id: 'power', name: 'Power', units: [u('W', 'Watt'), u('kW', 'Kilowatt'), u('MW', 'Megawatt'), u('hp', 'Horsepower')] },
  { id: 'pressure', name: 'Pressure', units: [u('Pa', 'Pascal'), u('kPa', 'Kilopascal'), u('MPa', 'Megapascal'), u('psi', 'PSI'), u('ksi', 'KSI'), u('bar', 'Bar'), u('atm', 'Atmosphere')] },
  { id: 'velocity', name: 'Velocity', units: [u('m/s', 'Metres / second'), u('km/h', 'Kilometres / hour'), u('mi/h', 'Miles / hour', 'mph'), u('ft/s', 'Feet / second'), u('knot', 'Knot', 'kn')] },
  { id: 'temperature', name: 'Temperature', units: [u('degC', 'Celsius', '°C'), u('degF', 'Fahrenheit', '°F'), u('K', 'Kelvin')] },
  { id: 'angle', name: 'Angle', units: [u('deg', 'Degree', '°'), u('rad', 'Radian'), u('rev', 'Revolution'), u('grad', 'Gradian')] },
  { id: 'area', name: 'Area', units: [u('m^2', 'Square metre', 'm²'), u('cm^2', 'Square cm', 'cm²'), u('mm^2', 'Square mm', 'mm²'), u('in^2', 'Square inch', 'in²'), u('ft^2', 'Square foot', 'ft²')] },
  { id: 'volume', name: 'Volume', units: [u('m^3', 'Cubic metre', 'm³'), u('L', 'Litre'), u('mL', 'Millilitre'), u('in^3', 'Cubic inch', 'in³'), u('ft^3', 'Cubic foot', 'ft³'), u('gal', 'US gallon')] },
]

export function convert(value: number, from: string, to: string): number {
  return math.unit(value, from).toNumber(to)
}

export function formatNumber(v: number, precision = 6): string {
  if (!Number.isFinite(v)) return '—'
  return formatValue(v, precision)
}

/**
 * Parse free-text conversions like `25 ft -> m`, `50 psi to kPa`, `3 hp in kW`.
 * Returns null if the text isn't a conversion.
 */
export function quickConvert(text: string, precision = 6): string | null {
  const m = text.trim().match(/^(-?[\d.]+(?:e[+-]?\d+)?)\s*([^\s].*?)\s*(?:->|→|\bto\b|\bin\b)\s*(.+)$/i)
  if (!m) return null
  try {
    const v = math.unit(Number(m[1]), m[2]).toNumber(m[3])
    return `${formatValue(v, precision)} ${m[3]}`
  } catch {
    return null
  }
}
