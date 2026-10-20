import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as groups from './groups.ts';
import * as metar from './metar.ts';
import * as taf from './taf.ts';
import * as verification from './verification.ts';
import { Calendar, floorDiv, pad, sin, cos, mileFraction, meterValue, compareVisibility, fraction } from './units.ts';
import type { Cloud, MileVisibility, ParsedGroup, Pressure, Reading, RVR, Section, Slot, Visibility, Weather, WeatherState, Wind } from './groups.ts';

export interface Station { code: string; elevation: number; runways: { name: string; heading: number }[]; name: string }
interface Params { year: number; month: number; crosswind: number; tailwind: number; verify: string[] }
interface RawReport { number: number; words: string[] }
export interface Group { text: string; position: number }
export type ErrorRecorder = (position: number, reason: string, text?: string | null) => void;
interface ReportError { report: number; position: number; content: string }
export type Category = 'VFR' | 'MVFR' | 'IFR' | 'LIFR';
export interface CategorizedState extends WeatherState { category: Category }
interface Header { number: number; station: Station; time: number; bodyStart: number }
export interface ObservationHeader extends Header { kind: 'METAR' | 'SPECI' }
export interface ForecastHeader extends Header {
  kind: 'TAF'; modifier: 'AMD' | 'COR' | null; issueDay: number; start: number; end: number;
}
interface Component { head: number; cross: number }
interface RunwayWind { name: string; mean: Component; gust: Component | null; usable: boolean }
interface RunwayWinds { runways: RunwayWind[]; preferred: RunwayWind | null }
export interface Observation extends ObservationHeader {
  main: Section & CategorizedState & { ceiling: number | null };
  trends: (metar.RawTrend & { state: Section })[]; remarks: metar.Remarks;
  pressureAltitude: number | null; densityAltitude: number | null; runwayWinds: RunwayWinds | null; speciReasons: string[];
}
export interface Forecast extends ForecastHeader {
  base: Section; changes: taf.Change[]; timeline: Map<number, taf.TimelineHour>;
}
type Report = Observation | Forecast;
const CATEGORIES = verification.CATEGORIES;
const readLines = (filename: string) => readFileSync(join('input', filename), 'ascii').split('\n').slice(0, -1);

function readInputs(): { stations: Map<string, Station>; params: Params; reports: RawReport[] } {
  const stations = new Map<string, Station>();
  for (const line of readLines('stations.txt')) {
    const [code, elevation, runwayList, ...name] = line.split(' ');
    const runways = runwayList.split(',').map(entry => {
      const [runwayName, heading] = entry.split('/');
      return { name: runwayName, heading: Number(heading) };
    });
    stations.set(code, { code, elevation: Number(elevation), runways, name: name.join(' ') });
  }
  const settings = new Map(readLines('params.txt').map((line): [string, string[]] => {
    const [name, ...values] = line.split(' '); return [name, values];
  }));
  const params: Params = { year: Number(settings.get('YEAR')![0]), month: Number(settings.get('MONTH')![0]),
    crosswind: Number(settings.get('CROSSWIND_LIMIT')![0]), tailwind: Number(settings.get('TAILWIND_LIMIT')![0]),
    verify: settings.get('VERIFY')! };
  const reports: RawReport[] = [];
  for (const line of readLines('reports.txt')) {
    const words = line.replace(/^ +/, '').split(' ');
    if (line.startsWith(' ')) reports[reports.length - 1].words.push(...words);
    else reports.push({ number: reports.length + 1, words });
  }
  return { stations, params, reports };
}
function errorRecorder(errors: ReportError[], reportNumber: number): ErrorRecorder {
  return (position, reason, text = null) => {
    errors.push({ report: reportNumber, position, content: reason + (text === null ? '' : ` "${text}"`) });
  };
}
function parseHeader(raw: RawReport, stations: Map<string, Station>, calendar: Calendar,
  error: ErrorRecorder): ObservationHeader | ForecastHeader | null {
  const words = raw.words, kind = words[0];
  if (kind !== 'METAR' && kind !== 'SPECI' && kind !== 'TAF') {
    error(1, 'rejected report, invalid type', kind); return null;
  }
  let cursor = 1, modifier: ForecastHeader['modifier'] = null;
  if (kind === 'TAF' && (words[cursor] === 'AMD' || words[cursor] === 'COR')) {
    modifier = words[cursor] === 'AMD' ? 'AMD' : 'COR'; cursor++;
  }
  const required = (item: string): string | null => {
    if (cursor === words.length) { error(words.length + 1, `rejected report, missing ${item}`); return null; }
    return words[cursor];
  };
  const stationWord = required('station');
  if (stationWord === null) return null;
  const station = stations.get(stationWord);
  if (!station) { error(cursor + 1, 'rejected report, invalid station', stationWord); return null; }
  cursor++;
  const timeWord = required('time');
  if (timeWord === null) return null;
  const time = calendar.observationTime(timeWord);
  if (time === null) { error(cursor + 1, 'rejected report, invalid time', timeWord); return null; }
  cursor++;
  if (kind !== 'TAF') return { number: raw.number, kind, station, time, bodyStart: cursor };
  const validityWord = required('validity');
  if (validityWord === null) return null;
  const issueDay = floorDiv(time, 1440) + 1, period = calendar.period(validityWord, issueDay, 1800);
  if (period === null) { error(cursor + 1, 'rejected report, invalid validity', validityWord); return null; }
  return { number: raw.number, kind, modifier, station, time, issueDay, ...period, bodyStart: cursor + 1 };
}
function joinGroups(words: string[], start: number): Group[] {
  const result: Group[] = [];
  for (let index = start; index < words.length; index++) {
    const position = index + 1;
    let text = words[index];
    if (/^\d$/.test(text) && index + 1 < words.length && /^\d\/\d{1,2}SM$/.test(words[index + 1])) text += ' ' + words[++index];
    result.push({ text, position });
  }
  return result;
}
function matchSection(body: Group[], slots: Slot[], context: Section['context'], station: Station, error: ErrorRecorder): Section {
  const section = groups.section(context);
  let current = 0;
  for (const group of body) {
    let found = current, candidate: ParsedGroup | null = null;
    for (; found < slots.length; found++) {
      candidate = slots[found].test(group.text);
      if (candidate !== null) break;
    }
    if (candidate === null) {
      const earlier = slots.slice(0, current).some(slot => slot.test(group.text) !== null);
      error(group.position, earlier ? 'out of order group' : 'unknown group', group.text); continue;
    }
    if (!groups.valid(candidate, section, station)) { error(group.position, 'invalid group', group.text); continue; }
    groups.accept(section, candidate);
    current = candidate.kind === 'visibility' && candidate.value.kind === 'cavok'
      ? slots.findIndex(slot => slot.kind === 'cloud') + 1 : found + (slots[found].repeat ? 0 : 1);
  }
  return section;
}
function ceiling(state: WeatherState): number | null {
  return (state.cloud ?? []).find(cloud => ['BKN', 'OVC', 'VV'].includes(cloud.amount))?.height ?? null;
}
function flightCategory(state: WeatherState): Category {
  const height = ceiling(state), visibility = state.visibility === null ? null : mileFraction(state.visibility);
  const less = (value: number) => visibility !== null && visibility[0] < value * visibility[1];
  const atMost = (value: number) => visibility !== null && visibility[0] <= value * visibility[1];
  if (height !== null && height < 500 || less(1)) return 'LIFR';
  if (height !== null && height < 1000 || less(3)) return 'IFR';
  if (height !== null && height <= 3000 || atMost(5)) return 'MVFR';
  return 'VFR';
}
function components(direction: number, heading: number, speed: number): Component {
  const angle = direction - heading;
  return { head: floorDiv(speed * cos(angle), 1000), cross: floorDiv(speed * sin(angle), 1000) };
}
function runwayWinds(wind: Wind | null, station: Station, params: Params): RunwayWinds | null {
  if (wind === null || wind.variable || wind.calm || wind.direction === null) return null;
  const runways: RunwayWind[] = [];
  let preferred: RunwayWind | null = null;
  for (const runway of station.runways) {
    const mean = components(wind.direction, runway.heading, wind.speed);
    const gust = wind.gust === null ? null : components(wind.direction, runway.heading, wind.gust), deciding = gust ?? mean;
    const usable = Math.abs(deciding.cross) <= params.crosswind && -deciding.head <= params.tailwind;
    const result = { name: runway.name, mean, gust, usable };
    runways.push(result);
    if (usable && (preferred === null || mean.head > preferred.mean.head)) preferred = result;
  }
  return { runways, preferred };
}
function windChanges(earlier: Wind | null, later: Wind | null, alpha: number): string[] {
  if (earlier === null || later === null) return [];
  const reasons: string[] = [];
  if (!earlier.variable && !earlier.calm && !later.variable && !later.calm
    && earlier.direction !== null && later.direction !== null && Math.max(earlier.speed, later.speed) >= 10) {
    const difference = Math.abs(earlier.direction - later.direction) % 360;
    if (Math.min(difference, 360 - difference) >= alpha) reasons.push('wind shift');
  }
  if (Math.abs(earlier.speed - later.speed) >= 10) reasons.push('wind speed');
  return reasons;
}
function speciCheck(previous: Observation | undefined, report: Observation): string[] {
  if (previous === undefined) return ['no previous report'];
  const before = previous.main, after = report.main, reasons: string[] = [];
  if (before.category !== after.category) reasons.push(`category ${before.category} to ${after.category}`);
  reasons.push(...windChanges(before.wind, after.wind, 45));
  const thunderstorm = (state: WeatherState) => (state.weather ?? []).some(weather => weather.descriptor === 'TS');
  const freezing = (state: WeatherState) => (state.weather ?? []).some(weather => weather.descriptor === 'FZ'
    && weather.phenomena.some(code => code === 'DZ' || code === 'RA'));
  if (thunderstorm(before) !== thunderstorm(after)) reasons.push(`thunderstorm ${thunderstorm(after) ? 'began' : 'ended'}`);
  if (freezing(before) !== freezing(after)) reasons.push(`freezing precipitation ${freezing(after) ? 'began' : 'ended'}`);
  return reasons.length ? reasons : ['no criteria met'];
}
function decodeObservation(header: ObservationHeader, body: Group[], params: Params, error: ErrorRecorder): Observation {
  const parts = metar.splitBody(body), state = matchSection(parts.main, metar.MAIN_SLOTS, 'main', header.station, error);
  const main = { ...state, ceiling: ceiling(state), category: flightCategory(state) };
  const trends = metar.readTrends(parts.trends, error).map(trend => ({ ...trend,
    state: matchSection(trend.groups, taf.SLOTS, 'trend', header.station, error) }));
  const pressureAltitude = main.pressure === null ? null : header.station.elevation + (2992 - main.pressure.inHg) * 10;
  const densityAltitude = pressureAltitude === null || main.temperature === null ? null
    : pressureAltitude + floorDiv(120 * (1000 * main.temperature.temperature - 15000 + 2 * pressureAltitude), 1000);
  return { ...header, main, trends, remarks: metar.readRemarks(parts.remarks), pressureAltitude, densityAltitude,
    runwayWinds: runwayWinds(main.wind, header.station, params), speciReasons: [] };
}
function decodeForecast(header: ForecastHeader, body: Group[], calendar: Calendar, error: ErrorRecorder): Forecast {
  const parts = taf.splitBody(body, header, calendar, error);
  const base = matchSection(parts.base, taf.SLOTS, 'base', header.station, error);
  const changes = parts.changes.map(change => ({ ...change,
    state: matchSection(change.groups, taf.SLOTS, 'change', header.station, error) }));
  return { ...header, base, changes,
    timeline: taf.expand({ ...header, base, changes }, state => ({ ...state, category: flightCategory(state) })) };
}

function windPhrase(wind: Wind): string {
  if (wind.calm) return 'calm';
  let phrase = wind.variable ? `variable at ${wind.speed} KT` : `${pad(wind.direction!, 3)} degrees at ${wind.speed} KT`;
  if (wind.gust !== null) phrase += ` gusting ${wind.gust} KT`;
  return phrase;
}
function windCode(wind: Wind): string {
  if (wind.calm) return '00000KT';
  return (wind.variable ? 'VRB' : pad(wind.direction!, 3)) + pad(wind.speed, 2)
    + (wind.gust === null ? '' : 'G' + pad(wind.gust, 2)) + 'KT';
}
function mileNumber(visibility: MileVisibility): string {
  if (!visibility.fractional) return String(visibility.whole);
  const part = `${visibility.numerator}/${visibility.denominator}`;
  return visibility.whole === 0 ? part : `${visibility.whole} ${part}`;
}
function visibilityPhrase(visibility: Visibility): string {
  if (visibility.kind === 'cavok') return '10 km or more (CAVOK)';
  if (visibility.kind === 'meter') return visibility.qualifier === 'P' ? '10 km or more' : `${visibility.meters} m`;
  const qualifiers: Record<string, string> = { M: 'less than ', P: 'more than ', '': '' };
  return qualifiers[visibility.qualifier] + mileNumber(visibility) + ' SM';
}
function visibilityCode(visibility: Visibility): string {
  if (visibility.kind === 'cavok') return 'CAVOK';
  if (visibility.kind === 'meter') return visibility.code;
  return visibility.qualifier + mileNumber(visibility) + 'SM';
}
function weatherPhrase(weather: Weather): string {
  if (weather.nsw) return 'no significant weather';
  const parts: string[] = [];
  if (weather.intensity) parts.push(groups.INTENSITIES[weather.intensity]);
  if (weather.descriptor !== null) parts.push(groups.DESCRIPTORS[weather.descriptor]);
  if (weather.phenomena.length) parts.push(weather.phenomena.map(code => groups.PHENOMENA[code]).join(' and '));
  return parts.join(' ');
}
function cloudPhrase(cloud: Cloud): string {
  if (Object.hasOwn(groups.CLEAR, cloud.amount)) return groups.CLEAR[cloud.amount];
  if (cloud.amount === 'VV') return `vertical visibility ${cloud.height} ft`;
  let phrase = `${groups.AMOUNTS[cloud.amount]} at ${cloud.height} ft`;
  if (cloud.suffix) phrase += cloud.suffix === 'CB' ? ' cumulonimbus' : ' towering cumulus';
  return phrase;
}
function cloudCode(cloud: Cloud): string {
  return Object.hasOwn(groups.CLEAR, cloud.amount) ? cloud.amount
    : cloud.amount + pad(floorDiv(cloud.height!, 100), 3) + cloud.suffix;
}
function stateSummary(state: WeatherState): string {
  const parts: string[] = [];
  if (state.wind !== null) parts.push('wind ' + windPhrase(state.wind));
  if (state.visibility !== null) parts.push('visibility ' + visibilityPhrase(state.visibility));
  if (state.weather?.length) parts.push('weather ' + state.weather.map(weatherPhrase).join(', '));
  if (state.cloud?.length) parts.push('cloud ' + state.cloud.map(cloudPhrase).join(', '));
  return parts.length ? parts.join('; ') : 'no conditions';
}
function stateTokens(state: CategorizedState): string {
  const tokens: string[] = [];
  if (state.wind !== null) tokens.push(windCode(state.wind));
  if (state.visibility !== null) tokens.push(visibilityCode(state.visibility));
  for (const weather of state.weather ?? []) if (!weather.nsw) tokens.push(weather.raw);
  for (const cloud of state.cloud ?? []) tokens.push(cloudCode(cloud));
  tokens.push(state.category);
  return tokens.join(' ');
}
function decimalTenth(value: number): string {
  const absolute = Math.abs(value);
  return (value < 0 ? '-' : '') + floorDiv(absolute, 10) + '.' + absolute % 10;
}
function pressurePhrase(pressure: Pressure): string {
  const inches = `${floorDiv(pressure.inHg, 100)}.${pad(pressure.inHg % 100, 2)} inHg`, hectopascals = `${pressure.hPa} hPa`;
  return pressure.unit === 'A' ? `${inches} (${hectopascals})` : `${hectopascals} (${inches})`;
}
function rvrPhrase(rvr: RVR): string {
  const qualifiers: Record<string, string> = { M: 'less than ', P: 'more than ', '': '' };
  const reading = (value: Reading) => qualifiers[value.qualifier] + value.value;
  let phrase = `runway ${rvr.runway} `;
  phrase += rvr.second === null ? reading(rvr.first) : `between ${reading(rvr.first)} and ${reading(rvr.second)}`;
  phrase += ' ' + rvr.unit;
  const trends: Record<string, string> = { U: ', rising', D: ', falling', N: ', no change' };
  if (rvr.trend !== null) phrase += trends[rvr.trend];
  return phrase;
}
function componentPhrase(component: Component): string {
  let phrase = component.head < 0 ? `tailwind ${-component.head} KT` : `headwind ${component.head} KT`;
  phrase += component.cross === 0 ? ', crosswind 0 KT'
    : `, crosswind ${Math.abs(component.cross)} KT from ${component.cross > 0 ? 'right' : 'left'}`;
  return phrase;
}
function observationLines(report: Observation, calendar: Calendar): string[] {
  const main = report.main, lines = [`time: ${calendar.stamp(report.time)}`];
  if (main.modifier !== null) lines.push(`modifier: ${main.modifier === 'AUTO' ? 'automated' : 'corrected'}`);
  let wind = main.wind === null ? 'not reported' : windPhrase(main.wind);
  if (main.variation !== null) wind += `, varying between ${pad(main.variation[0], 3)} and ${pad(main.variation[1], 3)} degrees`;
  lines.push('wind: ' + wind, 'visibility: ' + (main.visibility === null ? 'not reported' : visibilityPhrase(main.visibility)));
  for (const rvr of main.rvr) lines.push('runway visual range: ' + rvrPhrase(rvr));
  for (const weather of main.weather ?? []) lines.push('weather: ' + weatherPhrase(weather));
  if (main.visibility?.kind === 'cavok') lines.push('cloud: no significant cloud');
  else if (main.cloud === null) lines.push('cloud: not reported');
  else for (const cloud of main.cloud) lines.push('cloud: ' + cloudPhrase(cloud));
  if (main.temperature === null) lines.push('temperature: not reported');
  else {
    const { temperature, dewPoint } = main.temperature;
    lines.push(`temperature: ${temperature} C, dew point ${dewPoint} C, spread ${temperature - dewPoint} C`);
  }
  lines.push('altimeter: ' + (main.pressure === null ? 'not reported' : pressurePhrase(main.pressure)));
  if (main.noTrend !== null) lines.push('trend: no significant change');
  const timeWords = { FM: 'from', TL: 'until', AT: 'at' };
  for (const trend of report.trends) {
    let phrase = trend.kind === 'BECMG' ? 'becoming' : 'temporarily';
    for (const time of trend.times) phrase += ` ${timeWords[time.kind]} ${pad(time.hour, 2)}:${pad(time.minute, 2)}Z`;
    lines.push(`trend: ${phrase}: ${stateSummary(trend.state)}`);
  }
  for (const pressure of report.remarks.pressures) lines.push(`sea level pressure: ${decimalTenth(pressure)} hPa`);
  for (const temperature of report.remarks.temperatures) lines.push(`precise temperature: ${decimalTenth(temperature.temperature)} C, dew point ${decimalTenth(temperature.dewPoint)} C`);
  lines.push('ceiling: ' + (main.ceiling === null ? 'none' : `${main.ceiling} ft`), 'flight category: ' + main.category);
  lines.push('pressure altitude: ' + (report.pressureAltitude === null ? 'not available' : `${report.pressureAltitude} ft`));
  lines.push('density altitude: ' + (report.densityAltitude === null ? 'not available' : `${report.densityAltitude} ft`));
  if (report.runwayWinds === null) lines.push('runway wind: not computed');
  else {
    for (const runway of report.runwayWinds.runways) {
      let phrase = componentPhrase(runway.mean);
      if (runway.gust !== null) phrase += '; gusts ' + componentPhrase(runway.gust);
      lines.push(`runway ${runway.name}: ${phrase}`);
    }
    const usable = report.runwayWinds.runways.filter(runway => runway.usable).map(runway => runway.name);
    lines.push('usable runways: ' + (usable.length ? usable.join(' ') : 'none'));
    lines.push('preferred runway: ' + (report.runwayWinds.preferred?.name ?? 'none'));
  }
  if (report.kind === 'SPECI') lines.push('speci check: ' + report.speciReasons.join(', '));
  return lines;
}
function forecastLines(report: Forecast, calendar: Calendar): string[] {
  const lines = ['issued: ' + calendar.stamp(report.time)];
  if (report.modifier !== null) lines.push(`modifier: ${report.modifier === 'AMD' ? 'amended' : 'corrected'}`);
  lines.push(`valid: ${calendar.stamp(report.start)} to ${calendar.stamp(report.end)}`, 'base: ' + stateSummary(report.base));
  for (const change of report.changes) {
    const period = change.kind === 'FM' ? calendar.stamp(change.time) : `${calendar.stamp(change.start)} to ${calendar.stamp(change.end)}`;
    lines.push(`${change.kind} ${period}: ${stateSummary(change.state)}`);
  }
  return lines;
}
function decodedBlock(report: Report, calendar: Calendar): string[] {
  const header = `REPORT ${report.number}: ${report.kind} ${report.station.code} (${report.station.name})`;
  const lines = report.kind === 'TAF' ? forecastLines(report, calendar) : observationLines(report, calendar);
  return [header, ...lines.map(line => '  ' + line)];
}
function categoryCounts(states: CategorizedState[]): string {
  const counts: Record<Category, number> = { VFR: 0, MVFR: 0, IFR: 0, LIFR: 0 };
  for (const state of states) counts[state.category]++;
  return CATEGORIES.map(category => `${category} ${counts[category]}`).join(', ');
}
function timelineBlock(report: Forecast, calendar: Calendar): string[] {
  const lines = [`TAF ${report.station.code} issued ${calendar.stamp(report.time)} valid ${calendar.stamp(report.start)} to ${calendar.stamp(report.end)}`];
  for (const [time, hour] of report.timeline) {
    let line = `${calendar.stamp(time)} ${stateTokens(hour.prevailing)}`;
    for (const temporary of hour.temporary) line += ` | ${temporary.kind} ${stateTokens(temporary.state)}`;
    lines.push(line);
  }
  lines.push('summary: ' + categoryCounts([...report.timeline.values()].map(hour => hour.prevailing)));
  return lines;
}
function categoriesLine(report: Observation, calendar: Calendar): string {
  const main = report.main, visibility = main.visibility === null ? 'NONE' : main.visibility.qualifier + meterValue(main.visibility);
  return [report.station.code, calendar.stamp(report.time), main.ceiling ?? 'NONE', visibility, main.category].join(',');
}
function extreme<T>(observations: Observation[], valueOf: (report: Observation) => T | null,
  compare: (a: T, b: T) => number): { observation: Observation; value: T } | null {
  let selected: { observation: Observation; value: T } | null = null;
  for (const observation of observations) {
    const value = valueOf(observation);
    if (value !== null && (selected === null || compare(value, selected.value) < 0)) selected = { observation, value };
  }
  return selected;
}
function extremeLines(observations: Observation[], calendar: Calendar): string[] {
  const temperature = (report: Observation) => report.main.temperature?.temperature ?? null;
  const strength = (wind: Wind) => wind.gust ?? wind.speed;
  const line = <T>(label: string, selected: { observation: Observation; value: T } | null, phrase: (value: T) => string) =>
    label + ': ' + (selected === null ? 'not available' : `${phrase(selected.value)} at ${calendar.stamp(selected.observation.time)}`);
  return [
    line('lowest temperature', extreme(observations, temperature, (a, b) => a - b), value => `${value} C`),
    line('highest temperature', extreme(observations, temperature, (a, b) => b - a), value => `${value} C`),
    line('strongest wind', extreme(observations, report => report.main.wind, (a, b) => strength(b) - strength(a)), windPhrase),
    line('lowest ceiling', extreme(observations, report => report.main.ceiling, (a, b) => a - b), value => `${value} ft`),
    line('lowest visibility', extreme(observations, report => report.main.visibility, compareVisibility), visibilityPhrase),
  ];
}
function contingencyLines(result: verification.Analysis): string[] {
  const row = (label: string, values: (number | string)[]) => label.padEnd(8, ' ') + values.map(value => String(value).padStart(6, ' ')).join('');
  const lines = [row('forecast', [...CATEGORIES, 'total'])];
  for (let index = 0; index < 4; index++) lines.push(row(CATEGORIES[index], [...result.table[index], result.rows[index]]));
  lines.push(row('total', [...result.columns, result.total]));
  return lines;
}
function amendmentLines(result: verification.Analysis, calendar: Calendar): string[] {
  const lines: string[] = [];
  for (const choice of result.choices) {
    const observed = choice.observation.main, forecast = choice.forecast.prevailing, reasons: string[] = [];
    if (!choice.temporaryHit) reasons.push(`category ${observed.category}, forecast ${forecast.category}`);
    if (windChanges(forecast.wind, observed.wind, 60).length && observed.wind !== null && forecast.wind !== null) {
      reasons.push(`wind ${windCode(observed.wind)}, forecast ${windCode(forecast.wind)}`);
    }
    if (reasons.length) lines.push(`amendment ${calendar.stamp(choice.observation.time)}: ${reasons.join('; ')}`);
  }
  return lines;
}
function verificationBlock(station: Station, observations: Observation[], forecasts: Forecast[], calendar: Calendar): string[] {
  const result = verification.analyze(observations, forecasts), metars = observations.filter(report => report.kind === 'METAR').length;
  const lines = [`station ${station.code} (${station.name})`, `reports: METAR ${metars}, SPECI ${observations.length - metars}`,
    'observed categories: ' + categoryCounts(observations.map(report => report.main))];
  lines.push(...extremeLines(observations, calendar), `verified: ${result.total}`, `no forecast: ${result.noForecast}`);
  lines.push(...contingencyLines(result), 'hit rate: ' + fraction(...result.hitRate));
  lines.push('hit rate with temporary groups: ' + fraction(...result.temporaryHitRate), 'heidke skill score: ' + fraction(...result.skill));
  for (let index = 0; index < 4; index++) {
    const metric = result.metrics[index];
    lines.push(`${CATEGORIES[index]}: pod ${fraction(...metric.pod)}, far ${fraction(...metric.far)}`);
  }
  for (let index = 0; index < 5; index++) {
    const bucket = result.buckets[index];
    lines.push(`hours ${index * 6}-${index * 6 + 5}: ${fraction(bucket.hits, bucket.pairs)}`);
  }
  lines.push(...amendmentLines(result, calendar));
  return lines;
}
const blockText = (blocks: string[][]) => blocks.length ? blocks.map(block => block.join('\n')).join('\n\n') + '\n' : '';
const lineText = (lines: string[]) => lines.length ? lines.join('\n') + '\n' : '';
function main(): void {
  const { stations, params, reports: rawReports } = readInputs(), calendar = new Calendar(params.year, params.month);
  const reports: Report[] = [], observations: Observation[] = [], forecasts: Forecast[] = [], errors: ReportError[] = [];
  const previous = new Map<string, Observation>();
  for (const raw of rawReports) {
    const error = errorRecorder(errors, raw.number), header = parseHeader(raw, stations, calendar, error);
    if (header === null) continue;
    const body = joinGroups(raw.words, header.bodyStart);
    if (header.kind === 'TAF') {
      const report = decodeForecast(header, body, calendar, error);
      forecasts.push(report); reports.push(report);
    } else {
      const report = decodeObservation(header, body, params, error);
      if (report.kind === 'SPECI') report.speciReasons = speciCheck(previous.get(report.station.code), report);
      previous.set(report.station.code, report); observations.push(report); reports.push(report);
    }
  }
  const verificationBlocks = params.verify.map(code => verificationBlock(stations.get(code)!,
    observations.filter(report => report.station.code === code), forecasts.filter(report => report.station.code === code), calendar));
  errors.sort((first, second) => first.report - second.report || first.position - second.position);
  const outputs = new Map<string, string>([
    ['decoded.txt', blockText(reports.map(report => decodedBlock(report, calendar)))],
    ['categories.csv', lineText(['station,time,ceiling,visibility,category', ...observations.map(report => categoriesLine(report, calendar))])],
    ['taf_timeline.txt', blockText(forecasts.map(report => timelineBlock(report, calendar)))],
    ['verification.txt', blockText(verificationBlocks)],
    ['errors.txt', lineText(errors.map(error => `report ${error.report} word ${error.position}: ${error.content}`))],
  ]);
  mkdirSync('output', { recursive: true });
  for (const [name, text] of outputs) writeFileSync(join('output', name), text, 'ascii');
}
main();
