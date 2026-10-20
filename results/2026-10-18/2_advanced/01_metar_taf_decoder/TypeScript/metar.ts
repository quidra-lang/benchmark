import { format, type GroupKind, type Slot, type Temperature } from './groups.ts';
import type { Group, ErrorRecorder } from './main.ts';

const MAIN_KINDS: [GroupKind, boolean][] = [['modifier', false], ['wind', false], ['variation', false],
  ['visibility', false], ['rvr', true], ['weather', true], ['cloud', true],
  ['temperature', false], ['pressure', false], ['noTrend', false]];
export const MAIN_SLOTS = MAIN_KINDS.map(([kind, repeat]): Slot => ({ kind, repeat, test: text => format(kind, text) }));
export interface TrendTime { kind: 'FM' | 'TL' | 'AT'; hour: number; minute: number }
export interface RawTrend { kind: 'BECMG' | 'TEMPO'; times: TrendTime[]; groups: Group[] }
export interface Remarks { pressures: number[]; temperatures: Temperature[] }
const isTrend = (group: Group) => group.text === 'BECMG' || group.text === 'TEMPO';
export function splitBody(body: Group[]): { main: Group[]; trends: Group[]; remarks: Group[] } {
  const remarkIndex = body.findIndex(group => group.text === 'RMK');
  const beforeRemarks = remarkIndex < 0 ? body : body.slice(0, remarkIndex);
  const remarks = remarkIndex < 0 ? [] : body.slice(remarkIndex + 1), trendIndex = beforeRemarks.findIndex(isTrend);
  return { main: trendIndex < 0 ? beforeRemarks : beforeRemarks.slice(0, trendIndex),
    trends: trendIndex < 0 ? [] : beforeRemarks.slice(trendIndex), remarks };
}
export function readTrends(groups: Group[], error: ErrorRecorder): RawTrend[] {
  const trends: RawTrend[] = [];
  let index = 0;
  while (index < groups.length) {
    const indicator = groups[index];
    let end = index + 1;
    while (end < groups.length && !isTrend(groups[end])) end++;
    let cursor = index + 1, invalid = false;
    const times: TrendTime[] = [];
    while (cursor < end) {
      const match = /^(FM|TL|AT)(\d{2})(\d{2})$/.exec(groups[cursor].text);
      if (!match || times.length > 0 && !(times.length === 1 && times[0].kind === 'FM' && match[1] === 'TL')) break;
      const hour = Number(match[2]), minute = Number(match[3]);
      if (hour > 23 || minute > 59) {
        error(groups[cursor].position, 'invalid period', groups[cursor].text); invalid = true; break;
      }
      const kind = match[1] === 'FM' ? 'FM' : match[1] === 'TL' ? 'TL' : 'AT';
      times.push({ kind, hour, minute }); cursor++;
    }
    if (!invalid) trends.push({ kind: indicator.text === 'BECMG' ? 'BECMG' : 'TEMPO', times, groups: groups.slice(cursor, end) });
    index = end;
  }
  return trends;
}
export function readRemarks(groups: Group[]): Remarks {
  const pressures: number[] = [], temperatures: Temperature[] = [];
  for (const group of groups) {
    let match = /^SLP(\d{3})$/.exec(group.text);
    if (match) {
      const value = Number(match[1]); pressures.push((value >= 500 ? 9000 : 10000) + value); continue;
    }
    match = /^T([01])(\d{3})([01])(\d{3})$/.exec(group.text);
    if (match) temperatures.push({ temperature: Number(match[2]) * (match[1] === '1' ? -1 : 1),
      dewPoint: Number(match[4]) * (match[3] === '1' ? -1 : 1) });
  }
  return { pressures, temperatures };
}
