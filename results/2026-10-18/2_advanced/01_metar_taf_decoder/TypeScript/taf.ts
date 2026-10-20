import { format, type GroupKind, type Slot, type WeatherState } from './groups.ts';
import type { Calendar } from './units.ts';
import type { CategorizedState, Forecast, ForecastHeader, Group, ErrorRecorder } from './main.ts';

const KINDS: [GroupKind, boolean][] = [['wind', false], ['visibility', false], ['weather', true], ['cloud', true]];
export const SLOTS = KINDS.map(([kind, repeat]): Slot => ({ kind, repeat, test: text => format(kind, text) }));
export type PeriodKind = 'BECMG' | 'TEMPO' | 'PROB30' | 'PROB40' | 'PROB30 TEMPO' | 'PROB40 TEMPO';
export type RawChange = { kind: 'FM'; time: number; groups: Group[] }
  | { kind: PeriodKind; start: number; end: number; groups: Group[] };
export type Change = RawChange & { state: WeatherState };
export interface TimelineHour { prevailing: CategorizedState; temporary: { kind: PeriodKind; state: CategorizedState }[] }
const TEMPORARY = new Set<PeriodKind>(['TEMPO', 'PROB30', 'PROB40', 'PROB30 TEMPO', 'PROB40 TEMPO']);
function isIndicator(group: Group): boolean {
  return ['BECMG', 'TEMPO', 'PROB30', 'PROB40'].includes(group.text) || /^FM\d{6}$/.test(group.text);
}
export function splitBody(body: Group[], report: ForecastHeader, calendar: Calendar, error: ErrorRecorder): { base: Group[]; changes: RawChange[] } {
  let index = body.findIndex(isIndicator);
  if (index < 0) return { base: body, changes: [] };
  const base = body.slice(0, index), changes: RawChange[] = [];
  while (index < body.length) {
    const indicator = body[index];
    let kind: 'FM' | PeriodKind = indicator.text.startsWith('FM') ? 'FM' : indicator.text as PeriodKind;
    index++;
    if ((kind === 'PROB30' || kind === 'PROB40') && body[index]?.text === 'TEMPO') {
      kind = kind === 'PROB30' ? 'PROB30 TEMPO' : 'PROB40 TEMPO'; index++;
    }
    let end = index;
    while (end < body.length && !isIndicator(body[end])) end++;
    if (kind === 'FM') {
      const time = calendar.changeTime(indicator.text, report.issueDay);
      if (time === null || time < report.start || time >= report.end) error(indicator.position, 'invalid period', indicator.text);
      else changes.push({ kind, time, groups: body.slice(index, end) });
    } else if (index === end || !/^\d{4}\/\d{4}$/.test(body[index].text)) {
      error(indicator.position, 'missing period', kind);
    } else {
      const period = calendar.period(body[index].text, report.issueDay);
      if (period === null || period.start < report.start || period.end > report.end) error(body[index].position, 'invalid period', body[index].text);
      else changes.push({ kind, ...period, groups: body.slice(index + 1, end) });
    }
    index = end;
  }
  return { base, changes };
}
function stateOf(state: WeatherState): WeatherState {
  return { wind: state.wind, visibility: state.visibility, weather: state.weather, cloud: state.cloud };
}
function overlay(state: WeatherState, change: WeatherState): WeatherState {
  return { wind: change.wind ?? state.wind, visibility: change.visibility ?? state.visibility,
    weather: change.weather ?? state.weather, cloud: change.cloud ?? state.cloud };
}
export function expand(report: Pick<Forecast, 'start' | 'end' | 'base' | 'changes'>,
  categorize: (state: WeatherState) => CategorizedState): Map<number, TimelineHour> {
  const timeline = new Map<number, TimelineHour>();
  for (let hour = report.start; hour < report.end; hour += 60) {
    let prevailing = stateOf(report.base);
    for (const change of report.changes) {
      if (change.kind === 'FM' && change.time <= hour) prevailing = stateOf(change.state);
      if (change.kind === 'BECMG' && change.end <= hour) prevailing = overlay(prevailing, change.state);
    }
    const temporary: TimelineHour['temporary'] = [];
    for (const change of report.changes) {
      if (change.kind !== 'FM' && TEMPORARY.has(change.kind) && change.start <= hour && hour < change.end) {
        temporary.push({ kind: change.kind, state: categorize(overlay(prevailing, change.state)) });
      }
    }
    timeline.set(hour, { prevailing: categorize(prevailing), temporary });
  }
  return timeline;
}
