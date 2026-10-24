import type { NumericRow, SpikeSettings } from './records.ts';

export type Reason = 'absent' | 'na' | 'flat' | 'spike';
export interface PreliminaryRow extends NumericRow {
  preliminary: number;
}
export interface FlatRun {
  start: number;
  end: number;
  value: number;
}
export interface Spike {
  time: number;
  value: number;
  residual: number;
  median: number;
  mad: number;
  limit: number;
}
export function median(sorted: number[]): number {
  const m = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[m] : (sorted[m - 1] + sorted[m]) / 2;
}
export function flatRuns(rows: NumericRow[], minimum: number): FlatRun[] {
  const runs: FlatRun[] = [];
  for (let a = 0; a < rows.length;) {
    let b = a;
    while (
      b + 1 < rows.length &&
      rows[b + 1].time === rows[b].time + 1 &&
      rows[b + 1].milli === rows[a].milli
    ) {
      b++;
    }
    if (b - a + 1 >= minimum) {
      runs.push({ start: rows[a].time, end: rows[b].time, value: rows[a].value });
    }
    a = b + 1;
  }
  return runs;
}
function lowerBound(values: number[], target: number): number {
  let lo = 0;
  let hi = values.length;
  while (lo < hi) {
    const m = Math.floor((lo + hi) / 2);
    if (values[m] < target) lo = m + 1;
    else hi = m;
  }
  return lo;
}
function mad(sorted: number[], center: number): number {
  let right = lowerBound(sorted, center);
  let left = right - 1;
  let previous = 0;
  let current = 0;
  for (let i = 0; i <= Math.floor(sorted.length / 2); i++) {
    previous = current;
    const a = left >= 0 ? Math.abs(sorted[left] - center) : Infinity;
    const b = right < sorted.length ? Math.abs(sorted[right] - center) : Infinity;
    if (a <= b) {
      current = a;
      left--;
    } else {
      current = b;
      right++;
    }
  }
  return sorted.length % 2 ? current : (previous + current) / 2;
}
export function spikeTests(
  rows: PreliminaryRow[],
  settings: SpikeSettings,
): { tested: number; spikes: Spike[] } {
  const sorted: number[] = [];
  const spikes: Spike[] = [];
  let left = 0;
  let right = 0;
  let tested = 0;
  for (const row of rows) {
    while (right < rows.length && rows[right].time <= row.time + settings.window) {
      const value = rows[right++].preliminary;
      sorted.splice(lowerBound(sorted, value), 0, value);
    }
    while (left < right && rows[left].time < row.time - settings.window) {
      const value = rows[left++].preliminary;
      sorted.splice(lowerBound(sorted, value), 1);
    }
    if (sorted.length < settings.count) continue;
    tested++;
    const center = median(sorted);
    const deviation = mad(sorted, center);
    const limit = Math.max(settings.factor * 1.4826 * deviation, settings.minimum);
    if (Math.abs(row.preliminary - center) > limit) {
      spikes.push({
        time: row.time,
        value: row.value,
        residual: row.preliminary,
        median: center,
        mad: deviation,
        limit,
      });
    }
  }
  return { tested, spikes };
}
export function gaps(
  first: number,
  last: number,
  reasons: Map<number, Reason>,
): { start: number; end: number; cause: Reason | 'mixed' }[] {
  const result: { start: number; end: number; cause: Reason | 'mixed' }[] = [];
  for (let time = first; time <= last;) {
    if (!reasons.has(time)) {
      time++;
      continue;
    }
    const start = time;
    let cause: Reason | 'mixed' = reasons.get(time)!;
    while (time <= last && reasons.has(time)) {
      if (reasons.get(time) !== cause) cause = 'mixed';
      time++;
    }
    result.push({ start, end: time - 1, cause });
  }
  return result;
}
