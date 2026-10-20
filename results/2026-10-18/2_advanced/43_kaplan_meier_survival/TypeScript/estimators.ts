import type { Subject } from './dataset.ts';
import { z95 } from './numerics.ts';

export interface KmRow {
  time: number; risk: number; events: number; censored: number; survival: number; greenwood?: number;
  se?: number; lower?: number; upper?: number; hazard: number; hazardSe: number;
}
export const eventTimes = (subjects: Subject[]) => [...new Set(subjects.filter(s => s.event === 1).map(s => s.time))].sort((a, b) => a - b);
export const atRisk = (subjects: Subject[], time: number) => subjects.filter(s => s.time >= time).length;
export function kaplanMeier(subjects: Subject[]): KmRow[] {
  const times = eventTimes(subjects), rows: KmRow[] = [];
  let survival = 1, greenwood: number | undefined = 0, hazard = 0, variance = 0;
  times.forEach((time, i) => {
    const risk = atRisk(subjects, time), events = subjects.filter(s => s.time === time && s.event === 1).length;
    survival = survival * ((risk - events) / risk);
    if (risk === events) greenwood = undefined;
    else if (greenwood !== undefined) greenwood = greenwood + events / (risk * (risk - events));
    hazard = hazard + events / risk; variance = variance + events / (risk * risk);
    let se: number | undefined, lower: number | undefined, upper: number | undefined;
    if (survival !== 0 && greenwood !== undefined) {
      se = survival * Math.sqrt(greenwood);
      const log = Math.log(survival), omega = z95 * Math.sqrt(greenwood) / -log;
      lower = Math.exp(log * Math.exp(omega)); upper = Math.exp(log * Math.exp(-omega));
    }
    const censored = subjects.filter(s => s.event === 0 && s.time >= time && (i + 1 === times.length || s.time < times[i + 1])).length;
    rows.push({ time, risk, events, censored, survival, greenwood, se, lower, upper, hazard, hazardSe: Math.sqrt(variance) });
  });
  return rows;
}
export function rowAt(rows: KmRow[], time: number): KmRow {
  let result: KmRow = { time: 0, risk: 0, events: 0, censored: 0, survival: 1, greenwood: 0, se: 0, hazard: 0, hazardSe: 0 };
  for (const row of rows) { if (row.time > time) break; result = row; }
  return result;
}
export interface LifeRow { start: number; end: number; risk: number; events: number; censored: number; exposed: number; q: number; survival: number; se: number; hazard: number }
export function lifeTable(subjects: Subject[], width: number, count: number): LifeRow[] {
  const rows: LifeRow[] = [];
  let survival = 1, variance = 0;
  for (let i = 0; i < count; i++) {
    const start = i * width, end = (i + 1) * width, risk = atRisk(subjects, start);
    const inside = subjects.filter(s => s.time >= start && s.time < end), events = inside.filter(s => s.event === 1).length, censored = inside.length - events;
    const f = 2 * risk - censored, q = 2 * events / f;
    survival = survival * ((f - 2 * events) / f); variance = variance + 4 * events / (f * (f - 2 * events));
    rows.push({ start, end, risk, events, censored, exposed: f / 2, q, survival, se: survival * Math.sqrt(variance), hazard: 2000 * events / (width * (f - events)) });
  }
  return rows;
}
