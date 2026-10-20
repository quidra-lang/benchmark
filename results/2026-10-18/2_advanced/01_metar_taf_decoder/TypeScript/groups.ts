import { knots, inHg, hPa } from './units.ts';
import type { Station } from './main.ts';

export const DESCRIPTORS: Record<string, string> = { MI: 'shallow', BC: 'patches', PR: 'partial', DR: 'low drifting',
  BL: 'blowing', SH: 'showers', TS: 'thunderstorm', FZ: 'freezing' };
export const PHENOMENA: Record<string, string> = { DZ: 'drizzle', RA: 'rain', SN: 'snow', SG: 'snow grains',
  IC: 'ice crystals', PL: 'ice pellets', GR: 'hail', GS: 'small hail', UP: 'unknown precipitation', BR: 'mist',
  FG: 'fog', FU: 'smoke', VA: 'volcanic ash', DU: 'dust', SA: 'sand', HZ: 'haze', PY: 'spray',
  PO: 'dust whirls', SQ: 'squalls', FC: 'funnel cloud', SS: 'sandstorm', DS: 'duststorm' };
export const PRECIPITATION = new Set(['DZ', 'RA', 'SN', 'SG', 'IC', 'PL', 'GR', 'GS', 'UP']);
export const AMOUNTS: Record<string, string> = { FEW: 'few', SCT: 'scattered', BKN: 'broken', OVC: 'overcast' };
export const CLEAR: Record<string, string> = { SKC: 'sky clear', CLR: 'clear below 12000 ft', NSC: 'no significant cloud' };
export const INTENSITIES: Record<string, string> = { '-': 'light', '+': 'heavy', VC: 'nearby' };
const WEATHER_CODES = new Set([...Object.keys(DESCRIPTORS), ...Object.keys(PHENOMENA)]);
export interface Wind { direction: number | null; variable: boolean; calm: boolean; speed: number; gust: number | null; unit: 'KT' | 'MPS' }
export interface MileVisibility {
  kind: 'mile'; whole: number; numerator: number; denominator: number; qualifier: string; mixed: boolean; fractional: boolean;
}
export type Visibility = MileVisibility | { kind: 'cavok'; meters: number; qualifier: string }
  | { kind: 'meter'; meters: number; qualifier: string; code: string };
export interface Reading { qualifier: string; value: number }
export interface RVR { runway: string; first: Reading; second: Reading | null; unit: 'ft' | 'm'; trend: string | null }
export interface Weather { raw: string; nsw: boolean; intensity: string; codes: string[]; descriptor: string | null; phenomena: string[] }
export interface Cloud { raw: string; amount: string; height: number | null; suffix: string }
export interface Temperature { temperature: number; dewPoint: number }
export interface Pressure { unit: 'A' | 'Q'; value: number; inHg: number; hPa: number }
export interface WeatherState { wind: Wind | null; visibility: Visibility | null; weather: Weather[] | null; cloud: Cloud[] | null }
export interface Section extends WeatherState {
  context: 'main' | 'trend' | 'base' | 'change'; modifier: 'AUTO' | 'COR' | null; variation: [number, number] | null;
  rvr: RVR[]; temperature: Temperature | null; pressure: Pressure | null; noTrend: true | null;
}
interface GroupValues {
  modifier: 'AUTO' | 'COR'; wind: Wind; variation: [number, number]; visibility: Visibility; rvr: RVR;
  weather: Weather; cloud: Cloud; temperature: Temperature; pressure: Pressure; noTrend: true;
}
export type GroupKind = keyof GroupValues;
export type ParsedGroup = { [K in GroupKind]: { kind: K; value: GroupValues[K] } }[GroupKind];
export interface Slot { kind: GroupKind; repeat: boolean; test: (text: string) => ParsedGroup | null }
export function section(context: Section['context']): Section {
  return { context, modifier: null, wind: null, variation: null, visibility: null, rvr: [],
    weather: null, cloud: null, temperature: null, pressure: null, noTrend: null };
}
function visibilityFormat(text: string): Visibility | null {
  if (text === 'CAVOK') return { kind: 'cavok', meters: 10000, qualifier: 'P' };
  if (/^\d{4}$/.test(text)) {
    const value = Number(text);
    return { kind: 'meter', meters: value === 9999 ? 10000 : value, qualifier: value === 9999 ? 'P' : '', code: text };
  }
  let match = /^(\d) (\d)\/(\d{1,2})SM$/.exec(text);
  if (match) return { kind: 'mile', whole: Number(match[1]), numerator: Number(match[2]), denominator: Number(match[3]),
    qualifier: '', mixed: true, fractional: true };
  match = /^([MP]?)(?:(\d{1,2})|(\d)\/(\d{1,2}))SM$/.exec(text);
  return match ? { kind: 'mile', qualifier: match[1], whole: Number(match[2] ?? 0), numerator: Number(match[3] ?? 0),
    denominator: Number(match[4] ?? 1), mixed: false, fractional: match[3] !== undefined } : null;
}
function weatherFormat(text: string): Weather | null {
  if (text === 'NSW') return { raw: text, nsw: true, intensity: '', codes: [], descriptor: null, phenomena: [] };
  let intensity = '', body = text;
  if (body.startsWith('VC')) { intensity = 'VC'; body = body.slice(2); }
  else if (body.startsWith('-') || body.startsWith('+')) { intensity = body[0]; body = body.slice(1); }
  if (!body.length || body.length % 2 !== 0) return null;
  const codes: string[] = [];
  for (let index = 0; index < body.length; index += 2) {
    const code = body.slice(index, index + 2);
    if (!WEATHER_CODES.has(code)) return null;
    codes.push(code);
  }
  const descriptor = Object.hasOwn(DESCRIPTORS, codes[0]) ? codes[0] : null;
  return { raw: text, nsw: false, intensity, codes, descriptor, phenomena: descriptor === null ? codes : codes.slice(1) };
}
export function format(kind: GroupKind, text: string): ParsedGroup | null {
  let match: RegExpExecArray | null;
  switch (kind) {
    case 'modifier': return text === 'AUTO' || text === 'COR' ? { kind, value: text } : null;
    case 'wind':
      match = /^(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)$/.exec(text);
      return match ? { kind, value: { direction: match[1] === 'VRB' ? null : Number(match[1]), variable: match[1] === 'VRB',
        speed: Number(match[2]), gust: match[3] === undefined ? null : Number(match[3]),
        unit: match[4] === 'MPS' ? 'MPS' : 'KT', calm: match[1] === '000' } } : null;
    case 'variation':
      match = /^(\d{3})V(\d{3})$/.exec(text);
      return match ? { kind, value: [Number(match[1]), Number(match[2])] } : null;
    case 'visibility': {
      const value = visibilityFormat(text);
      return value === null ? null : { kind, value };
    }
    case 'rvr':
      match = /^R(\d{2}[LCR]?)\/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?$/.exec(text);
      return match ? { kind, value: { runway: match[1], first: { qualifier: match[2], value: Number(match[3]) },
        second: match[5] === undefined ? null : { qualifier: match[4], value: Number(match[5]) },
        unit: match[6] ? 'ft' : 'm', trend: match[7] ?? null } } : null;
    case 'weather': {
      const value = weatherFormat(text);
      return value === null ? null : { kind, value };
    }
    case 'cloud':
      if (Object.hasOwn(CLEAR, text)) return { kind, value: { raw: text, amount: text, height: null, suffix: '' } };
      match = /^(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?$/.exec(text);
      if (match) return { kind, value: { raw: text, amount: match[1], height: Number(match[2]) * 100, suffix: match[3] ?? '' } };
      match = /^VV(\d{3})$/.exec(text);
      return match ? { kind, value: { raw: text, amount: 'VV', height: Number(match[1]) * 100, suffix: '' } } : null;
    case 'temperature':
      match = /^(M?)(\d{2})\/(M?)(\d{2})$/.exec(text);
      return match ? { kind, value: { temperature: Number(match[2]) * (match[1] ? -1 : 1),
        dewPoint: Number(match[4]) * (match[3] ? -1 : 1) } } : null;
    case 'pressure':
      match = /^([AQ])(\d{4})$/.exec(text);
      if (!match) return null;
      return { kind, value: { unit: match[1] === 'A' ? 'A' : 'Q', value: Number(match[2]),
        inHg: match[1] === 'A' ? Number(match[2]) : inHg(Number(match[2])),
        hPa: match[1] === 'Q' ? Number(match[2]) : hPa(Number(match[2])) } };
    case 'noTrend': return text === 'NOSIG' ? { kind, value: true } : null;
  }
}
export function valid(candidate: ParsedGroup, current: Section, station: Station): boolean {
  const { kind, value } = candidate;
  switch (kind) {
    case 'wind':
      if (value.variable) { if (value.speed < 1) return false; }
      else if (value.direction === null || value.direction > 360 || value.direction % 10 !== 0
        || (value.direction === 0) !== (value.speed === 0)) return false;
      return value.gust === null || !value.calm && value.gust > value.speed;
    case 'variation':
      return value.every(direction => direction >= 10 && direction <= 360 && direction % 10 === 0)
        && value[0] !== value[1] && current.wind !== null && !current.wind.variable && !current.wind.calm;
    case 'visibility':
      return value.kind !== 'mile' || (!value.fractional ? value.whole >= 1
        : [2, 4, 8, 16].includes(value.denominator) && value.numerator >= 1
          && value.numerator < value.denominator && (!value.mixed || value.whole >= 1));
    case 'rvr': return station.runways.some(runway => runway.name === value.runway)
      && (value.second === null || value.first.value < value.second.value);
    case 'weather': {
      const accepted = current.weather ?? [];
      if (accepted.length >= 3 || accepted.some(weather => weather.nsw)) return false;
      if (value.nsw) return accepted.length === 0 && ['trend', 'change'].includes(current.context);
      if (value.phenomena.some(code => !Object.hasOwn(PHENOMENA, code))
        || new Set(value.phenomena).size !== value.phenomena.length) return false;
      if (value.phenomena.length === 0 && value.descriptor !== 'TS' && value.descriptor !== 'SH') return false;
      if (['-', '+'].includes(value.intensity) && !value.phenomena.some(code => PRECIPITATION.has(code))) return false;
      return value.phenomena.length < 2 || value.phenomena.every(code => PRECIPITATION.has(code));
    }
    case 'cloud': {
      const previous = current.cloud?.at(-1);
      return !previous || Object.hasOwn(AMOUNTS, value.amount) && Object.hasOwn(AMOUNTS, previous.amount)
        && value.height !== null && previous.height !== null && value.height > previous.height;
    }
    case 'temperature': return value.dewPoint <= value.temperature;
    case 'pressure': return value.unit === 'A' ? value.value >= 2500 && value.value <= 3150
      : value.value >= 850 && value.value <= 1070;
    default: return true;
  }
}
export function accept(current: Section, candidate: ParsedGroup): void {
  const { kind, value } = candidate;
  switch (kind) {
    case 'wind':
      current.wind = value.unit === 'MPS' ? { ...value, speed: knots(value.speed),
        gust: value.gust === null ? null : knots(value.gust), unit: 'KT' } : value;
      break;
    case 'visibility':
      current.visibility = value;
      if (value.kind === 'cavok') { current.weather = []; current.cloud = []; }
      break;
    case 'rvr': current.rvr.push(value); break;
    case 'weather': (current.weather ??= []).push(value); break;
    case 'cloud': (current.cloud ??= []).push(value); break;
    case 'modifier': current.modifier = value; break;
    case 'variation': current.variation = value; break;
    case 'temperature': current.temperature = value; break;
    case 'pressure': current.pressure = value; break;
    case 'noTrend': current.noTrend = value; break;
  }
}
